import CryptoKit
import Foundation
import os
import Security

/// PKCE verifier/challenge pair for one authorization attempt.
private struct PKCEPair {
  /// High-entropy verifier sent to the token endpoint.
  let verifier: String

  /// SHA-256 challenge sent to the authorize endpoint.
  let challenge: String

  /// Creates a fresh verifier and its derived S256 challenge.
  init() {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    verifier = Self.base64URLEncoded(Data(bytes))

    let digest = SHA256.hash(data: Data(verifier.utf8))
    challenge = Self.base64URLEncoded(Data(digest))
  }

  /// Base64url encoding without padding, as required by RFC 7636.
  private static func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

/// Token endpoint JSON response shared by Google and Linear.
private struct OAuthTokenResponse: Decodable {
  /// Fresh access token.
  let accessToken: String?

  /// Refresh token, present on first grant and on rotated refreshes.
  let refreshToken: String?

  /// Access token lifetime in seconds.
  let expiresIn: TimeInterval?

  /// Granted scope string.
  let scope: String?

  /// Machine-readable provider error code.
  let error: String?

  /// Human-readable provider error detail.
  let errorDescription: String?

  /// Maps the response into a persisted token bundle.
  func tokens(fallbackRefreshToken: String?) throws -> OAuthTokens {
    if let error {
      throw OAuthError.tokenExchangeFailed(errorDescription ?? error)
    }

    guard let accessToken, !accessToken.isEmpty else {
      throw OAuthError.tokenExchangeFailed("Token response did not include an access token.")
    }

    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken ?? fallbackRefreshToken,
      expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
      scope: scope
    )
  }

  /// Maps snake_case provider JSON keys.
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case scope
    case error
    case errorDescription = "error_description"
  }
}

/// Manages the full OAuth lifecycle for one provider: sign-in, token storage,
/// refresh, sign-out, and authenticated API requests with one retry.
actor OAuthSession {
  /// Shared session for the Google Calendar provider.
  static let google = OAuthSession(provider: .google)

  /// Shared session for the Linear provider.
  static let linear = OAuthSession(provider: .linear)

  /// Provider this session manages.
  let provider: AuthProvider

  /// Keychain store backing token persistence.
  private let keychain: KeychainStore

  /// Logger for OAuth diagnostics.
  private let logger = Logger(subsystem: "build.local.Dayline", category: "oauth")

  /// In-memory token cache avoiding repeated Keychain reads.
  private var cachedTokens: OAuthTokens?

  /// Whether tokens have been loaded from the Keychain at least once.
  private var didLoadTokens = false

  /// Creates a session for one provider.
  init(provider: AuthProvider, keychain: KeychainStore = KeychainStore(service: "build.local.Dayline.oauth")) {
    self.provider = provider
    self.keychain = keychain
  }

  /// Whether any stored credentials exist for this provider.
  func hasTokens() -> Bool {
    (try? storedTokens()) != nil
  }

  /// Runs the browser authorization flow and persists the resulting tokens.
  func signIn() async throws {
    guard provider.isConfigured else {
      throw OAuthError.notConfigured
    }

    let pkce = PKCEPair()
    let state = UUID().uuidString
    let authorizeURL = provider.authorizeURL(codeChallenge: pkce.challenge, state: state)
    logger.info("Starting \(self.provider.id, privacy: .public) sign-in")

    let callbackURL = try await BrowserOAuthCoordinator.shared.authenticate(
      url: authorizeURL,
      callbackScheme: provider.callbackScheme
    )

    let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
    let queryItems = components?.queryItems ?? []

    guard queryItems.first(where: { $0.name == "state" })?.value == state else {
      throw OAuthError.stateMismatch
    }

    if let providerError = queryItems.first(where: { $0.name == "error" })?.value {
      let description = queryItems.first(where: { $0.name == "error_description" })?.value
      throw OAuthError.authorizationFailed(description ?? providerError)
    }

    guard let code = queryItems.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      throw OAuthError.invalidCallback
    }

    let tokens = try await exchangeCode(code, verifier: pkce.verifier)
    try persist(tokens)
    logger.info("Stored \(self.provider.id, privacy: .public) tokens")
  }

  /// Revokes and removes stored credentials for this provider.
  func signOut() async {
    if let tokens = try? storedTokens() {
      await revoke(tokens.accessToken)
    }
    cachedTokens = nil
    didLoadTokens = true
    try? keychain.delete(account: provider.keychainAccount)
  }

  /// Performs an authorized request, refreshing and retrying once on 401.
  func authorizedData(for request: URLRequest) async throws -> Data {
    let firstToken = try await validAccessToken()
    var (data, response) = try await perform(request, accessToken: firstToken)

    if response.statusCode == 401 {
      let refreshedToken = try await forceRefreshedAccessToken()
      (data, response) = try await perform(request, accessToken: refreshedToken)

      guard response.statusCode != 401 else {
        try? keychain.delete(account: provider.keychainAccount)
        cachedTokens = nil
        throw OAuthError.reauthenticationRequired
      }
    }

    guard (200..<300).contains(response.statusCode) else {
      let detail = String(data: data, encoding: .utf8)?.compactLine(limit: 160) ?? ""
      throw OAuthError.httpError(response.statusCode, detail)
    }

    return data
  }

  /// Returns a usable access token, refreshing when expired.
  private func validAccessToken() async throws -> String {
    guard let tokens = try storedTokens() else {
      throw OAuthError.notSignedIn
    }

    if tokens.isAccessTokenUsable {
      return tokens.accessToken
    }

    return try await forceRefreshedAccessToken()
  }

  /// Refreshes the access token and persists the rotated bundle.
  private func forceRefreshedAccessToken() async throws -> String {
    guard let tokens = try storedTokens(), let refreshToken = tokens.refreshToken else {
      throw OAuthError.reauthenticationRequired
    }

    do {
      let refreshed = try await refresh(refreshToken: refreshToken)
      try persist(refreshed)
      return refreshed.accessToken
    } catch let error as OAuthError {
      if case .refreshFailed = error {
        try? keychain.delete(account: provider.keychainAccount)
        cachedTokens = nil
        throw OAuthError.reauthenticationRequired
      }
      throw error
    }
  }

  /// Exchanges an authorization code for the initial token bundle.
  private func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokens {
    let response = try await postTokenRequest(parameters: [
      "grant_type": "authorization_code",
      "client_id": provider.clientID,
      "code": code,
      "redirect_uri": provider.redirectURI,
      "code_verifier": verifier
    ])
    return try response.tokens(fallbackRefreshToken: nil)
  }

  /// Mints a new access token from a refresh token.
  private func refresh(refreshToken: String) async throws -> OAuthTokens {
    let response = try await postTokenRequest(parameters: [
      "grant_type": "refresh_token",
      "client_id": provider.clientID,
      "refresh_token": refreshToken
    ])
    if response.error == "invalid_grant" {
      throw OAuthError.refreshFailed(response.errorDescription ?? "The refresh token is no longer valid.")
    }
    return try response.tokens(fallbackRefreshToken: refreshToken)
  }

  /// Revokes one token with the provider on a best-effort basis.
  private func revoke(_ token: String) async {
    var request = URLRequest(url: provider.revokeEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = Self.formEncoded([
      "token": token,
      "client_id": provider.clientID
    ])
    _ = try? await URLSession.shared.data(for: request)
  }

  /// Sends a form-encoded request to the provider token endpoint.
  private func postTokenRequest(parameters: [String: String]) async throws -> OAuthTokenResponse {
    var request = URLRequest(url: provider.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = Self.formEncoded(parameters)

    let (data, response) = try await URLSession.shared.data(for: request)
    let body = String(data: data, encoding: .utf8)?.compactLine(limit: 240) ?? ""
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

    do {
      let decoded = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
      if let error = decoded.error {
        logger.error("Token endpoint error (\(statusCode)): \(error, privacy: .public) \(decoded.errorDescription ?? "", privacy: .public)")
        return decoded
      }
      if statusCode >= 400 {
        throw OAuthError.tokenExchangeFailed(body.isEmpty ? "Token request failed (\(statusCode))." : body)
      }
      return decoded
    } catch let error as OAuthError {
      throw error
    } catch {
      logger.error("Token decode failed (\(statusCode)): \(body, privacy: .public)")
      throw OAuthError.tokenExchangeFailed(body.isEmpty ? error.localizedDescription : body)
    }
  }

  /// Performs one request attempt with a bearer token attached.
  private func perform(_ request: URLRequest, accessToken: String) async throws -> (Data, HTTPURLResponse) {
    var authorizedRequest = request
    authorizedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: authorizedRequest)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw OAuthError.invalidCallback
    }

    return (data, httpResponse)
  }

  /// Loads tokens from cache or Keychain.
  private func storedTokens() throws -> OAuthTokens? {
    if didLoadTokens {
      return cachedTokens
    }

    defer { didLoadTokens = true }

    guard let data = try keychain.data(for: provider.keychainAccount) else {
      cachedTokens = nil
      return nil
    }

    cachedTokens = try JSONDecoder().decode(OAuthTokens.self, from: data)
    return cachedTokens
  }

  /// Persists tokens to cache and Keychain.
  private func persist(_ tokens: OAuthTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    try keychain.save(data, for: provider.keychainAccount)
    cachedTokens = tokens
    didLoadTokens = true
  }

  /// Form-encodes parameters using strict RFC 3986 percent escaping.
  private static func formEncoded(_ parameters: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")

    let body = parameters
      .map { key, value in
        let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
        let escapedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(escapedKey)=\(escapedValue)"
      }
      .sorted()
      .joined(separator: "&")

    return Data(body.utf8)
  }
}

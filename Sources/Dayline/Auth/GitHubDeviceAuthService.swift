import Foundation

/// Device-code details shown to the user while GitHub authorization is pending.
struct GitHubDeviceCode: Sendable {
  /// Opaque code sent back when polling for the token.
  let deviceCode: String

  /// Short code the user types on GitHub's activation page.
  let userCode: String

  /// Page where the user enters the code.
  let verificationURI: URL

  /// Seconds until the device code stops being accepted.
  let expiresIn: Int

  /// Minimum seconds between token poll attempts.
  let interval: Int
}

/// Errors surfaced by the GitHub device authorization flow.
enum GitHubDeviceAuthError: LocalizedError {
  /// The build has no GitHub OAuth client ID.
  case notConfigured

  /// GitHub returned a response that could not be decoded.
  case invalidResponse

  /// The device code expired before the user finished authorizing.
  case expired

  /// The user denied the authorization request.
  case denied

  /// The user cancelled the pending authorization from the app.
  case cancelled

  /// GitHub rejected a request with an HTTP error.
  case httpError(Int, String?)

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "This build is missing its GitHub OAuth client ID."
    case .invalidResponse:
      "GitHub returned an unexpected response."
    case .expired:
      "The sign-in code expired. Try again."
    case .denied:
      "Authorization was denied on GitHub."
    case .cancelled:
      "Sign-in was cancelled."
    case .httpError(let status, let detail):
      detail.map { "GitHub error \(status): \($0)" } ?? "GitHub error \(status)."
    }
  }
}

/// Runs GitHub's OAuth device authorization grant, which needs no client secret.
actor GitHubDeviceAuthService {
  /// Shared service using the app's Keychain namespace.
  static let shared = GitHubDeviceAuthService()

  private let store: any CredentialStore
  private let session: URLSession

  /// Bumped to invalidate any in-flight device authorization poll.
  private var signInGeneration = 0

  init(store: any CredentialStore = KeychainStore(service: "build.local.Dayline.oauth")) {
    self.store = store
    self.session = .shared
  }

  /// Whether a GitHub access token is stored.
  func hasToken() -> Bool {
    accessToken() != nil
  }

  /// Returns the stored GitHub access token, if any.
  func accessToken() -> String? {
    guard let data = try? store.data(for: AuthProvider.github.keychainAccount),
          let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data),
          !tokens.accessToken.isEmpty else {
      return nil
    }
    return tokens.accessToken
  }

  /// Deletes the stored GitHub credentials.
  func signOut() {
    try? store.delete(account: AuthProvider.github.keychainAccount)
  }

  /// Starts the device flow and returns the code the user must enter on GitHub.
  func beginSignIn() async throws -> GitHubDeviceCode {
    signInGeneration += 1

    guard AuthProvider.github.isConfigured else {
      throw GitHubDeviceAuthError.notConfigured
    }

    let response: DeviceCodeResponse = try await post(
      URL(string: "https://github.com/login/device/code")!,
      form: [
        "client_id": AuthProvider.github.clientID,
        "scope": AuthProvider.github.scope
      ]
    )

    guard let verificationURI = URL(string: response.verificationUri) else {
      throw GitHubDeviceAuthError.invalidResponse
    }

    return GitHubDeviceCode(
      deviceCode: response.deviceCode,
      userCode: response.userCode,
      verificationURI: verificationURI,
      expiresIn: response.expiresIn,
      interval: max(response.interval, 1)
    )
  }

  /// Cancels any in-flight device authorization poll.
  func cancelSignIn() {
    signInGeneration += 1
  }

  /// Polls until the user authorizes the device code, then persists the token.
  func pollForAuthorization(_ code: GitHubDeviceCode) async throws {
    let generation = signInGeneration
    var interval = code.interval
    let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))

    while Date() < deadline {
      try await Task.sleep(for: .seconds(interval))
      try Task.checkCancellation()
      guard generation == signInGeneration else {
        throw GitHubDeviceAuthError.cancelled
      }

      do {
        let token: AccessTokenResponse = try await post(  // autoreview:allow-secret
          AuthProvider.github.tokenEndpoint,
          form: [
            "client_id": AuthProvider.github.clientID,
            "device_code": code.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
          ]
        )
        try Task.checkCancellation()
        guard generation == signInGeneration else {
          throw GitHubDeviceAuthError.cancelled
        }
        let tokens = OAuthTokens(
          accessToken: token.accessToken,  // autoreview:allow-secret
          refreshToken: nil,
          expiresAt: nil,
          scope: token.scope
        )
        try store.save(JSONEncoder().encode(tokens), for: AuthProvider.github.keychainAccount)
        return
      } catch let pollError as PollError {
        switch pollError.reason {
        case "authorization_pending":
          continue
        case "slow_down":
          interval += 5
          continue
        case "expired_token":
          throw GitHubDeviceAuthError.expired
        case "access_denied":
          throw GitHubDeviceAuthError.denied
        default:
          throw GitHubDeviceAuthError.httpError(400, pollError.description)
        }
      }
    }

    throw GitHubDeviceAuthError.expired
  }

  /// Sends one form POST with JSON accept headers and decodes the response.
  private func post<Response: Decodable & Sendable>(_ url: URL, form: [String: String]) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var formAllowedCharacters = CharacterSet.urlQueryAllowed
    formAllowedCharacters.remove(charactersIn: "&=+")
    request.httpBody = form
      .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: formAllowedCharacters) ?? $0.value)" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    guard (200..<300).contains(status) else {
      let message = (try? decoder.decode(PollError.self, from: data))?.description
      throw GitHubDeviceAuthError.httpError(status, message ?? String(data: data, encoding: .utf8))
    }

    if let pollError = try? decoder.decode(PollError.self, from: data), pollError.reason != nil {
      throw pollError
    }

    guard let decoded = try? decoder.decode(Response.self, from: data) else {
      throw GitHubDeviceAuthError.invalidResponse
    }
    return decoded
  }

  /// GitHub device-code response payload.
  private struct DeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
  }

  /// GitHub access-token response payload.
  private struct AccessTokenResponse: Decodable, Sendable {
    let accessToken: String
    let scope: String?
  }

  /// GitHub error payload returned with HTTP 200 while polling.
  private struct PollError: Error, Decodable, Sendable {
    let reason: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
      case reason = "error"
      case description = "errorDescription"
    }
  }
}

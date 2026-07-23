import Foundation

/// OAuth provider that Dayline can connect to.
enum AuthProvider: String, CaseIterable, Identifiable, Sendable {
  /// Google Calendar account.
  case google

  /// Linear workspace account.
  case linear

  /// GitHub account used as an alternative issue source.
  case github

  /// Stable identity.
  var id: String {
    rawValue
  }

  /// Human-readable provider name.
  var title: String {
    switch self {
    case .google:
      "Google Calendar"
    case .linear:
      "Linear"
    case .github:
      "GitHub"
    }
  }

  /// Public OAuth client ID baked into the app or supplied via environment.
  var clientID: String {
    switch self {
    case .google:
      AuthConfig.googleClientID
    case .linear:
      AuthConfig.linearClientID
    case .github:
      AuthConfig.githubClientID
    }
  }

  /// Whether a usable client ID is available.
  var isConfigured: Bool {
    !clientID.isEmpty
  }

  /// Keychain account key used for this provider's token bundle.
  var keychainAccount: String {
    rawValue
  }

  /// Requested OAuth scopes.
  var scope: String {
    switch self {
    case .google:
      "https://www.googleapis.com/auth/calendar.readonly"
    case .linear:
      "read,write"
    case .github:
      "repo read:user"
    }
  }

  /// URL scheme the provider redirects back to after authorization.
  var callbackScheme: String {
    switch self {
    case .google:
      Self.googleReversedClientIDScheme(from: clientID)
    case .linear:
      AuthConfig.linearCallbackScheme
    case .github:
      // GitHub uses the device authorization grant, which has no redirect.
      AuthConfig.linearCallbackScheme
    }
  }

  /// Redirect URI sent with authorization and token exchange requests.
  var redirectURI: String {
    switch self {
    case .google:
      "\(callbackScheme):/oauth/callback"
    case .linear:
      "\(callbackScheme)://oauth/callback"
    case .github:
      "\(callbackScheme)://oauth/github/callback"
    }
  }

  /// Authorization page URL.
  var authorizeEndpoint: URL {
    switch self {
    case .google:
      URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    case .linear:
      URL(string: "https://linear.app/oauth/authorize")!
    case .github:
      URL(string: "https://github.com/login/oauth/authorize")!
    }
  }

  /// Token exchange and refresh URL.
  var tokenEndpoint: URL {
    switch self {
    case .google:
      URL(string: "https://oauth2.googleapis.com/token")!
    case .linear:
      URL(string: "https://api.linear.app/oauth/token")!
    case .github:
      URL(string: "https://github.com/login/oauth/access_token")!
    }
  }

  /// Token revocation URL used on sign-out.
  var revokeEndpoint: URL {
    switch self {
    case .google:
      URL(string: "https://oauth2.googleapis.com/revoke")!
    case .linear:
      URL(string: "https://api.linear.app/oauth/revoke")!
    case .github:
      URL(string: "https://github.com/login/oauth/revoke")!
    }
  }

  /// Builds the provider authorization URL for a PKCE authorization-code flow.
  func authorizeURL(codeChallenge: String, state: String) -> URL {
    var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
    var queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: scope),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: codeChallenge),
      URLQueryItem(name: "code_challenge_method", value: "S256")
    ]

    if self == .google {
      queryItems.append(URLQueryItem(name: "access_type", value: "offline"))
      queryItems.append(URLQueryItem(name: "prompt", value: "select_account consent"))
    }

    components.queryItems = queryItems
    return components.url!
  }

  /// Google iOS-type clients redirect through the reversed client ID scheme.
  private static func googleReversedClientIDScheme(from clientID: String) -> String {
    let suffix = ".apps.googleusercontent.com"
    guard clientID.hasSuffix(suffix) else {
      return "com.googleusercontent.apps.invalid"
    }
    let prefix = String(clientID.dropLast(suffix.count))
    return "com.googleusercontent.apps.\(prefix)"
  }
}

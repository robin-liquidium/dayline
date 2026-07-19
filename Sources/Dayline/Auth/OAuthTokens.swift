import Foundation

/// Token bundle persisted in the Keychain for one OAuth provider.
struct OAuthTokens: Codable, Sendable {
  /// Short-lived bearer token used for API calls.
  var accessToken: String

  /// Long-lived token used to mint new access tokens.
  var refreshToken: String?

  /// Time when the access token stops being accepted.
  var expiresAt: Date?

  /// Granted scope string reported by the provider.
  var scope: String?

  /// Whether the access token can still be used without refreshing.
  var isAccessTokenUsable: Bool {
    guard let expiresAt else {
      return true
    }
    return expiresAt.timeIntervalSinceNow > 60
  }
}

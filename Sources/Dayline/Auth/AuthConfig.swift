import Foundation

/// OAuth client identifiers shipped with the app. Client IDs are public
/// identifiers, not secrets; both providers use PKCE instead of a secret.
enum AuthConfig {
  /// Google OAuth client ID (iOS application type, bundle ID `build.local.Dayline`).
  static var googleClientID: String {
    ProcessInfo.processInfo.environment["DAYLINE_GOOGLE_CLIENT_ID"]
      ?? Bundle.main.object(forInfoDictionaryKey: "DaylineGoogleClientID") as? String
      ?? bundledGoogleClientID
  }

  /// Linear OAuth client ID (public OAuth app with refresh tokens enabled).
  static var linearClientID: String {
    ProcessInfo.processInfo.environment["DAYLINE_LINEAR_CLIENT_ID"]
      ?? Bundle.main.object(forInfoDictionaryKey: "DaylineLinearClientID") as? String
      ?? bundledLinearClientID
  }

  /// Bundled Google OAuth client ID, empty until configured for distribution.
  private static let bundledGoogleClientID = "551177930544-9sl0govp6ok205csb939j4p2dhckrgbk.apps.googleusercontent.com"

  /// Bundled Linear OAuth client ID, empty until configured for distribution.
  private static let bundledLinearClientID = "00c88957100199ecb91362294a3f6e55"
}

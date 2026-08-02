import Foundation

/// Bundle-configurable storage namespaces that keep development installs isolated.
enum AppRuntimeConfig {
  /// Generic-password Keychain service used for OAuth credentials.
  static var oauthKeychainService: String {
    configuredString(
      Bundle.main.object(forInfoDictionaryKey: "DaylineOAuthKeychainService") as? String,
      fallback: "build.local.Dayline.oauth"
    )
  }

  /// Application Support folder containing notes and diagnostics.
  static var applicationSupportFolderName: String {
    configuredString(
      Bundle.main.object(forInfoDictionaryKey: "DaylineApplicationSupportFolder") as? String,
      fallback: "Dayline"
    )
  }

  /// Uses a non-empty bundle override while preserving shipped storage defaults.
  static func configuredString(_ value: String?, fallback: String) -> String {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return fallback
    }
    return value
  }
}

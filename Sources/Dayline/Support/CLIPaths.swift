import Foundation

/// Resolves CLI executable paths used by Dayline and its test harnesses.
enum CLIPaths {
  /// Absolute path to the Google Workspace CLI.
  static var gws: String {
    ProcessInfo.processInfo.environment["DAYLINE_GWS_PATH"] ?? "/opt/homebrew/bin/gws"
  }

  /// Absolute path to the Linear CLI.
  static var linear: String {
    ProcessInfo.processInfo.environment["DAYLINE_LINEAR_PATH"] ?? "/opt/homebrew/bin/linear"
  }
}

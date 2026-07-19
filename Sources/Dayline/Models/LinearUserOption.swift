import Foundation

/// Linear user option used by the issue creator assignee picker.
struct LinearUserOption: Identifiable, Equatable {
  /// Stable Linear user identifier.
  let id: String

  /// Human-readable Linear profile name.
  let name: String

  /// Linear username.
  let displayName: String

  /// Whether the user is currently active in Linear.
  let isActive: Bool

  /// Compact menu label for pickers.
  var label: String {
    displayName.isEmpty || displayName == name ? name : "\(name) (\(displayName))"
  }
}

import Foundation

/// Linear user option used by the issue creator assignee picker.
struct LinearUserOption: Identifiable, Equatable {
  /// Stable Linear user identifier.
  let id: String

  /// Human-readable Linear profile name.
  let name: String

  /// Linear username accepted by the CLI assignee flag.
  let displayName: String

  /// Whether the user is currently active in Linear.
  let isActive: Bool

  /// Value passed to `linear issue create --assignee`.
  var assigneeValue: String {
    displayName.isEmpty ? name : displayName
  }

  /// Compact menu label for pickers.
  var label: String {
    displayName.isEmpty || displayName == name ? name : "\(name) (\(displayName))"
  }
}

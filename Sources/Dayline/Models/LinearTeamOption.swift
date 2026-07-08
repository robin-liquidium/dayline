import Foundation

/// Linear team option used by the issue creator.
struct LinearTeamOption: Identifiable, Equatable {
  /// Stable Linear team identifier.
  let id: String

  /// Short Linear team key.
  let key: String

  /// Human-readable team name.
  let name: String

  /// Available workflow states for the team.
  let states: [LinearWorkflowState]

  /// Compact menu label for pickers.
  var label: String {
    "\(key) - \(name)"
  }
}

import Foundation

/// Which issues a provider shows in the menu.
enum IssueAssigneeFilter: String, CaseIterable, Identifiable, Codable, Sendable {
  /// Only issues assigned to the signed-in user.
  case assignedToMe

  /// Every open issue in the enabled teams or repositories.
  case allOpen

  /// Stable identity.
  var id: String { rawValue }

  /// Human-readable filter name.
  var label: String {
    switch self {
    case .assignedToMe:
      "Assigned to me"
    case .allOpen:
      "All open issues"
    }
  }
}

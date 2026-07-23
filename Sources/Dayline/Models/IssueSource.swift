import Foundation

/// Which provider supplies the issues section of the menu.
enum IssueSource: String, CaseIterable, Identifiable, Sendable {
  /// Linear workspace issues.
  case linear

  /// GitHub issues assigned to the user.
  case github

  /// Stable identity.
  var id: String {
    rawValue
  }

  /// Human-readable source name.
  var label: String {
    switch self {
    case .linear:
      "Linear"
    case .github:
      "GitHub"
    }
  }
}

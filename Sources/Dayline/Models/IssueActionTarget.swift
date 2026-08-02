import Foundation

/// Provider-qualified issue identity used by hover actions and popovers.
enum IssueActionTarget: Hashable, Sendable {
  case linear(String)
  case github(String)
  case reminder(String)

  /// Whether this provider exposes label and assignee mutation APIs.
  var supportsPeopleAndLabels: Bool {
    if case .reminder = self { return false }
    return true
  }
}

struct IssueLabelOption: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let color: String
}

struct IssueAssigneeOption: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
}

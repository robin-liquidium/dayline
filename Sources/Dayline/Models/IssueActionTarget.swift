import Foundation

/// Provider-qualified issue identity used by hover actions and popovers.
enum IssueActionTarget: Hashable, Sendable {
  case linear(String)
  case github(String)
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

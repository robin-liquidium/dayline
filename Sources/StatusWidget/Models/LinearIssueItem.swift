import Foundation

/// A normalized Linear issue assigned to the current authenticated user.
struct LinearIssueItem: Identifiable, Equatable {
  /// Linear issue identifier, such as `DEV-123`.
  let id: String

  /// Human-readable issue title.
  let title: String

  /// Linear priority number where lower positive values are more important.
  let priority: Int

  /// Human-readable priority label supplied by Linear.
  let priorityLabel: String

  /// Current Linear workflow state name.
  let stateName: String

  /// Current Linear workflow state identifier.
  let stateID: String

  /// Current Linear workflow state type, such as `started` or `unstarted`.
  let stateType: String

  /// Workflow states available on the issue's Linear team.
  let workflowStates: [LinearWorkflowState]

  /// Optional Linear due date in `YYYY-MM-DD` form.
  let dueDate: String?

  /// Browser URL for opening the issue in Linear.
  let url: URL?

  /// Sort rank that puts urgent and high-priority issues before unprioritized work.
  var prioritySortRank: Int {
    priority == 0 ? Int.max : priority
  }

  /// Sort rank that puts active work before todo and backlog.
  var stateSortRank: Int {
    switch stateType {
    case "started":
      0
    case "unstarted":
      1
    case "backlog":
      2
    default:
      3
    }
  }
}

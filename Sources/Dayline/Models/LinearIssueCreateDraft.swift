import Foundation

/// User-entered fields for creating a Linear issue through the API.
struct LinearIssueCreateDraft {
  /// Required issue title.
  var title = ""

  /// Optional markdown issue description.
  var description = ""

  /// Optional assignee: `self` or a Linear user ID.
  var assignee = "self"

  /// Required Linear team ID.
  var team = ""

  /// Optional workflow state ID.
  var state = ""

  /// Optional priority value where 1 is urgent and 4 is low.
  var priority: Int?

  /// Optional due date in `YYYY-MM-DD` form.
  var dueDate = ""

  /// Optional issue estimate.
  var estimate: Int?

  /// Optional project name.
  var project = ""

  /// Optional cycle name, number, or `active`.
  var cycle = ""

  /// Optional project milestone name, applied only when a project is set.
  var milestone = ""

  /// Optional parent issue identifier such as `TEAM-123`.
  var parent = ""

  /// Optional comma-separated label names.
  var labels = ""

  /// Whether the issue should be moved into a started state after creation.
  var shouldStart = false
}

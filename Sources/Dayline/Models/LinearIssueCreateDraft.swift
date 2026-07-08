import Foundation

/// User-entered fields for creating a Linear issue through the CLI.
struct LinearIssueCreateDraft {
  /// Required issue title.
  var title = ""

  /// Optional markdown issue description.
  var description = ""

  /// Optional assignee name accepted by the Linear CLI, commonly `self`.
  var assignee = "self"

  /// Optional team key or name accepted by the Linear CLI.
  var team = ""

  /// Optional workflow state name or type accepted by the Linear CLI.
  var state = ""

  /// Optional priority value where 1 is urgent and 4 is low.
  var priority: Int?

  /// Optional due date accepted by the Linear CLI.
  var dueDate = ""

  /// Optional issue estimate.
  var estimate: Int?

  /// Optional project name or slug.
  var project = ""

  /// Optional cycle name, number, or `active`.
  var cycle = ""

  /// Optional project milestone name.
  var milestone = ""

  /// Optional parent issue identifier.
  var parent = ""

  /// Optional comma-separated label names.
  var labels = ""

  /// Whether the issue should be moved into started state after creation.
  var shouldStart = false

  /// Whether the Linear CLI should skip the team's default template.
  var shouldSkipDefaultTemplate = false
}

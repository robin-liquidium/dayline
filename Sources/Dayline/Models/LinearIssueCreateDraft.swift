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

  /// Optional due date selected with the native macOS date picker.
  var dueDate: Date?

  /// Due date encoded in Linear's `YYYY-MM-DD` form.
  var formattedDueDate: String? {
    guard let dueDate else { return nil }
    return Self.formattedDueDate(dueDate, timeZone: .current)
  }

  /// Encodes a due date as a Gregorian calendar day in the supplied time zone.
  static func formattedDueDate(_ dueDate: Date, timeZone: TimeZone) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: dueDate)
    guard let year = components.year, let month = components.month, let day = components.day else {
      return nil
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  /// Optional issue estimate.
  var estimate: Int?

  /// Optional Linear project ID.
  var project = ""

  /// Optional Linear cycle ID.
  var cycle = ""

  /// Optional Linear project milestone ID, applied only when a project is set.
  var milestone = ""

  /// Optional parent issue identifier such as `TEAM-123`.
  var parent = ""

  /// Optional Linear label ID.
  var label = ""
}

import Foundation

/// User-selectable ordering for Linear issues in the menu.
enum LinearIssueOrder: String, CaseIterable, Identifiable {
  /// Highest Linear priorities first.
  case priority

  /// Earliest due dates first, with undated issues last.
  case dueDate

  /// Started work first, then todo and backlog.
  case status

  /// Alphabetical ordering by issue title.
  case title

  /// Stable identity for SwiftUI pickers.
  var id: String { rawValue }

  /// Human-readable label for Settings.
  var label: String {
    switch self {
    case .priority:
      "Priority"
    case .dueDate:
      "Due date"
    case .status:
      "Status"
    case .title:
      "Title"
    }
  }
}

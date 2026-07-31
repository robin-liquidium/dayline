import Foundation

/// Optional metadata fields that can appear on issue rows in the menu.
struct IssueRowFields: OptionSet, Equatable, Sendable {
  let rawValue: Int

  /// Assignee pill.
  static let assignee = IssueRowFields(rawValue: 1 << 0)

  /// Labels pill.
  static let labels = IssueRowFields(rawValue: 1 << 1)

  /// Project pill (Linear only).
  static let project = IssueRowFields(rawValue: 1 << 2)

  /// Last-updated pill.
  static let updated = IssueRowFields(rawValue: 1 << 3)

  /// Due date pill (Linear only).
  static let dueDate = IssueRowFields(rawValue: 1 << 4)

  /// Fields shown before any customization, matching the previous fixed rows.
  static let `default`: IssueRowFields = [.updated, .dueDate]
}

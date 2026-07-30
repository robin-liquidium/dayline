import Foundation

/// Menu item currently shown in a hover-triggered detail preview.
enum PreviewTarget: Equatable {
  /// Calendar event preview anchored to an event row.
  case event(CalendarEventItem.ID)

  /// Linear or GitHub issue preview anchored to an issue row.
  case issue(IssueActionTarget)
}

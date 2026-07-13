import Foundation

/// A normalized calendar event ready for display in the menu bar popover.
struct CalendarEventItem: Identifiable, Equatable {
  /// Stable event identifier from Google Calendar.
  let id: String

  /// Human-readable event title.
  let title: String

  /// Event start time in local `Date` form.
  let startDate: Date

  /// Event end time in local `Date` form.
  let endDate: Date

  /// Optional location copied from the calendar event.
  let location: String?

  /// Optional browser URL for opening the calendar event itself.
  let calendarURL: URL?

  /// Preferred URL for clicking the event, such as Google Meet or a URL in the location.
  let openURL: URL?

  /// Returns whether the event is active at the supplied moment.
  func isHappening(at date: Date) -> Bool {
    date >= startDate && date < endDate
  }

  /// Picks from start-time-sorted events, keeping an active event ahead of upcoming ones.
  static func menuBarCandidate(
    in events: [CalendarEventItem],
    at date: Date,
    leadTime: TimeInterval,
    postStartGrace: TimeInterval
  ) -> CalendarEventItem? {
    if let activeEvent = events.first(where: { $0.isHappening(at: date) }) {
      return activeEvent
    }

    return events.first { event in
      date >= event.startDate.addingTimeInterval(-leadTime)
        && date <= event.startDate.addingTimeInterval(postStartGrace)
    }
  }
}

import Foundation

/// Today/tomorrow slices produced from the globally merged Google agenda.
struct CalendarAgendaSections: Equatable, Sendable {
  let today: [CalendarEventItem]
  let tomorrow: [CalendarEventItem]
}

/// A normalized calendar event ready for display in the menu bar popover.
struct CalendarEventItem: Identifiable, Equatable, Sendable {
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

  /// Calendar names contributing this event after cross-calendar deduplication.
  let sourceCalendarNames: [String]

  /// Stable account/calendar keys contributing this event, aligned with source names.
  let sourceIDs: [String]

  /// Stable occurrence key used only when Google supplies an iCalendar UID.
  let deduplicationKey: String?

  init(
    id: String,
    title: String,
    startDate: Date,
    endDate: Date,
    location: String?,
    calendarURL: URL?,
    openURL: URL?,
    sourceCalendarNames: [String] = [],
    sourceIDs: [String] = [],
    deduplicationKey: String? = nil
  ) {
    self.id = id
    self.title = title
    self.startDate = startDate
    self.endDate = endDate
    self.location = location
    self.calendarURL = calendarURL
    self.openURL = openURL
    self.sourceCalendarNames = sourceCalendarNames
    self.sourceIDs = sourceIDs
    self.deduplicationKey = deduplicationKey
  }

  /// Collision-proof row identity across linked accounts and calendars.
  static func compositeID(accountID: UUID, calendarID: String, eventID: String) -> String {
    "\(accountID.uuidString)|\(calendarID)|\(eventID)"
  }

  /// Stable identity for one contributing account/calendar source.
  static func sourceID(accountID: UUID, calendarID: String) -> String {
    "\(accountID.uuidString)|\(calendarID)"
  }

  /// Compact source label for the agenda row.
  var sourceLabel: String? {
    guard let first = sourceCalendarNames.first else {
      return nil
    }
    let additionalCount = sourceCalendarNames.count - 1
    return additionalCount == 0 ? first : "\(first) +\(additionalCount)"
  }

  /// Full source label used by VoiceOver.
  var accessibilitySourceLabel: String? {
    sourceCalendarNames.isEmpty ? nil : sourceCalendarNames.joined(separator: ", ")
  }

  /// Returns whether the event is active at the supplied moment.
  func isHappening(at date: Date) -> Bool {
    date >= startDate && date < endDate
  }

  /// Sorts and collapses copies of the same Google meeting occurrence.
  static func mergedAgenda(_ events: [CalendarEventItem]) -> [CalendarEventItem] {
    var merged: [CalendarEventItem] = []
    var indexesByDeduplicationKey: [String: Int] = [:]

    for event in events.sorted(by: agendaOrder) {
      guard let key = event.deduplicationKey else {
        merged.append(event)
        continue
      }

      if let index = indexesByDeduplicationKey[key] {
        let existing = merged[index]
        var names = existing.sourceCalendarNames
        var sourceIDs = existing.sourceIDs
        if sourceIDs.isEmpty || event.sourceIDs.isEmpty {
          for name in event.sourceCalendarNames where !names.contains(name) {
            names.append(name)
          }
        } else {
          for sourceIndex in event.sourceIDs.indices where !sourceIDs.contains(event.sourceIDs[sourceIndex]) {
            sourceIDs.append(event.sourceIDs[sourceIndex])
            if event.sourceCalendarNames.indices.contains(sourceIndex) {
              names.append(event.sourceCalendarNames[sourceIndex])
            }
          }
        }
        merged[index] = CalendarEventItem(
          id: existing.id,
          title: existing.title,
          startDate: existing.startDate,
          endDate: existing.endDate,
          location: existing.location ?? event.location,
          calendarURL: existing.calendarURL ?? event.calendarURL,
          openURL: existing.openURL ?? event.openURL,
          sourceCalendarNames: names,
          sourceIDs: sourceIDs,
          deduplicationKey: key
        )
      } else {
        indexesByDeduplicationKey[key] = merged.count
        merged.append(event)
      }
    }

    return merged.sorted(by: agendaOrder)
  }

  /// Deduplicates, globally sorts, partitions, and caps an agenda after all sources load.
  static func agendaSections(
    from events: [CalendarEventItem],
    tomorrowStart: Date,
    dayAfterTomorrow: Date,
    todayLimit: Int,
    tomorrowLimit: Int
  ) -> CalendarAgendaSections {
    let merged = mergedAgenda(events)
    return CalendarAgendaSections(
      today: merged
        .filter { $0.startDate < tomorrowStart }
        .prefix(todayLimit)
        .map { $0 },
      tomorrow: merged
        .filter { $0.endDate > tomorrowStart && $0.startDate < dayAfterTomorrow }
        .prefix(tomorrowLimit)
        .map { $0 }
    )
  }

  /// Deterministic agenda ordering shared by merged and non-merged events.
  private static func agendaOrder(_ lhs: CalendarEventItem, _ rhs: CalendarEventItem) -> Bool {
    if lhs.startDate != rhs.startDate {
      return lhs.startDate < rhs.startDate
    }
    let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
    if titleComparison != .orderedSame {
      return titleComparison == .orderedAscending
    }
    return lhs.id < rhs.id
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

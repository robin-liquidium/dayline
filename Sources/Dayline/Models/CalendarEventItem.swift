import Foundation

/// Today/tomorrow slices produced from the globally merged Google agenda.
struct CalendarAgendaSections: Equatable, Sendable {
  let today: [CalendarEventItem]
  let tomorrow: [CalendarEventItem]
  let allDayToday: [CalendarEventItem]
  let allDayTomorrow: [CalendarEventItem]
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

  /// Whether this event occupies one or more complete calendar days.
  let isAllDay: Bool

  /// Optional browser URL for opening the calendar event itself.
  let calendarURL: URL?

  /// Conferencing URL sourced from structured provider data or a recognized meeting host.
  let meetingURL: URL?

  /// Preferred URL for clicking the event, such as Google Meet or a URL in the location.
  let openURL: URL?

  /// Whether the event has a real join link rather than an unrelated or calendar URL.
  var hasMeetingLink: Bool {
    meetingURL != nil
  }

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
    isAllDay: Bool = false,
    calendarURL: URL?,
    meetingURL: URL? = nil,
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
    self.isAllDay = isAllDay
    self.calendarURL = Self.safeWebURL(calendarURL)
    self.meetingURL = Self.safeWebURL(meetingURL)
    self.openURL = self.meetingURL ?? Self.safeWebURL(openURL)
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

  /// Allows only browser-safe web URLs for event actions.
  static func safeWebURL(_ url: URL?) -> URL? {
    guard let url,
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
      return nil
    }
    return url
  }

  /// Recognizes common conferencing links when a provider did not identify one structurally.
  static func recognizedMeetingURL(_ url: URL?) -> URL? {
    guard let url = safeWebURL(url), let host = url.host?.lowercased() else {
      return nil
    }
    let path = url.path.split(separator: "/").map { $0.lowercased() }

    switch host {
    case "meet.google.com":
      guard (path.count == 1 && isGoogleMeetCode(path[0]))
        || (path.count == 2 && path[0] == "lookup" && !path[1].isEmpty) else { return nil }
    case let host where isHost(host, under: "zoom.us"):
      guard path.count >= 2,
            (["j", "s", "w"].contains(path[0]) && path[1].allSatisfy(\.isNumber)
              || path[0] == "my" && !path[1].isEmpty
              || path.count == 3 && path[0] == "wc" && path[1] == "join"
                && path[2].allSatisfy(\.isNumber)
              || path.count == 3 && path[0] == "wc" && path[1].allSatisfy(\.isNumber)
                && path[2] == "join") else { return nil }
    case "teams.microsoft.com", "teams.live.com":
      let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let isLauncher = path == ["dl", "launcher", "launcher.html"]
        && queryItems.contains(where: {
          $0.name.caseInsensitiveCompare("type") == .orderedSame
            && $0.value?.caseInsensitiveCompare("meetup-join") == .orderedSame
        })
        && queryItems.contains(where: {
          $0.name.caseInsensitiveCompare("url") == .orderedSame
            && $0.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        })
      guard isLauncher
        || (path.count >= 2 && path[0] == "meet" && !path[1].isEmpty)
        || (path.count >= 3 && path[0] == "l" && path[1] == "meetup-join" && !path[2].isEmpty) else { return nil }
    case "instant.webex.com":
      guard path == ["gen", "v1", "talk"]
        || (path.count == 2 && path[0] == "visit" && !path[1].isEmpty) else { return nil }
    case let host where isHost(host, under: "webex.com"):
      let hasGuestJoinPath = host != "join.webex.com"
        && host.hasSuffix(".join.webex.com")
        && path.count >= 2
        && path[0] == "guest"
        && !path[1].isEmpty
      let hasMeetingPath = path.count >= 2
        && ["meet", "join"].contains(path[0])
        && !path[1].isEmpty
      let hasLegacyJoin = path.last == "j.php"
        && URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
          .contains(where: { $0.name.caseInsensitiveCompare("MTID") == .orderedSame && $0.value?.isEmpty == false }) == true
      guard hasGuestJoinPath || hasMeetingPath || hasLegacyJoin else { return nil }
    case "meet.jit.si":
      guard let room = path.first, !room.isEmpty, !["about", "static"].contains(room) else { return nil }
    case let host where isHost(host, under: "whereby.com"):
      guard let room = path.first,
            !room.isEmpty,
            !["about", "information", "pricing"].contains(room) else { return nil }
    case "facetime.apple.com":
      guard path.first == "join" else { return nil }
    case "chime.aws":
      guard path.count == 1, isChimeMeetingPath(path[0]) else { return nil }
    case let host where isHost(host, under: "around.co"):
      guard path.count >= 2, path[0] == "r", !path[1].isEmpty else { return nil }
    default:
      return nil
    }
    return url
  }

  private static func isHost(_ host: String, under domain: String) -> Bool {
    host == domain || host.hasSuffix(".\(domain)")
  }

  private static func isGoogleMeetCode(_ value: String) -> Bool {
    let groups = value.split(separator: "-")
    return groups.map(\.count) == [3, 4, 3]
      && groups.joined().allSatisfy { $0.isASCII && $0.isLetter }
  }

  private static func isChimeMeetingPath(_ value: String) -> Bool {
    if [10, 13].contains(value.count), value.allSatisfy(\.isNumber) {
      return true
    }
    let reserved = ["about", "download", "pricing", "signup"]
    return (12...35).contains(value.count)
      && !reserved.contains(value)
      && value.contains(where: { $0.isASCII && $0.isLetter })
      && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
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
        let meetingURL = existing.meetingURL ?? event.meetingURL
        merged[index] = CalendarEventItem(
          id: existing.id,
          title: existing.title,
          startDate: existing.startDate,
          endDate: existing.endDate,
          location: existing.location ?? event.location,
          isAllDay: existing.isAllDay || event.isAllDay,
          calendarURL: existing.calendarURL ?? event.calendarURL,
          meetingURL: meetingURL,
          openURL: meetingURL ?? existing.openURL ?? event.openURL,
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
    todayStart: Date,
    tomorrowStart: Date,
    dayAfterTomorrow: Date,
    todayLimit: Int,
    tomorrowLimit: Int,
    todayAllDayLimit: Int = .max,
    tomorrowAllDayLimit: Int = .max
  ) -> CalendarAgendaSections {
    let merged = mergedAgenda(events)
    return CalendarAgendaSections(
      today: merged
        .filter { !$0.isAllDay && $0.endDate > todayStart && $0.startDate < tomorrowStart }
        .prefix(todayLimit)
        .map { $0 },
      tomorrow: merged
        .filter { !$0.isAllDay && $0.endDate > tomorrowStart && $0.startDate < dayAfterTomorrow }
        .prefix(tomorrowLimit)
        .map { $0 },
      allDayToday: merged
        .filter { $0.isAllDay && $0.endDate > todayStart && $0.startDate < tomorrowStart }
        .prefix(todayAllDayLimit)
        .map { $0 },
      allDayTomorrow: merged
        .filter { $0.isAllDay && $0.endDate > tomorrowStart && $0.startDate < dayAfterTomorrow }
        .prefix(tomorrowAllDayLimit)
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
    let timedEvents = events.filter { !$0.isAllDay }
    if let activeEvent = timedEvents.first(where: { $0.isHappening(at: date) }) {
      return activeEvent
    }

    return timedEvents.first { event in
      date >= event.startDate.addingTimeInterval(-leadTime)
        && date <= event.startDate.addingTimeInterval(postStartGrace)
    }
  }
}

import EventKit
import Foundation

/// Reads device calendars and events through EventKit.
final class AppleCalendarService: @unchecked Sendable {
  /// Stable local identifier namespacing Apple-sourced event identities.
  static let accountID = UUID(uuidString: "a9c0ffee-0000-4000-8000-0000000000a9")!

  private let eventStore = EKEventStore()

  /// Whether the bundle may ask for calendar access without crashing.
  static var canRequestAccess: Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
  }

  /// Whether Dayline currently holds full calendar access.
  var hasFullAccess: Bool {
    EKEventStore.authorizationStatus(for: .event) == .fullAccess
  }

  /// Asks the system for full access to calendar events.
  func requestFullAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToEvents()
  }

  /// Lists device calendars with default-enabled selections.
  func calendarSources() -> [AppleCalendarSource] {
    eventStore.calendars(for: .event).map { calendar in
      AppleCalendarSource(
        id: calendar.calendarIdentifier,
        title: calendar.title,
        sourceName: calendar.source.title,
        isEnabled: true
      )
    }
  }

  /// Loads timed events from the selected calendars in the given window.
  func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [CalendarEventItem] {
    let eventStore = EKEventStore()
    let calendars = eventStore.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
    guard !calendars.isEmpty else {
      return []
    }
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
    return eventStore.events(matching: predicate).compactMap { event in
      guard !event.isAllDay,
            let eventID = event.eventIdentifier,
            let startDate = event.startDate,
            let endDate = event.endDate else {
        return nil
      }
      let occurrenceDate = event.occurrenceDate ?? startDate
      let occurrenceID = "\(eventID)|\(occurrenceDate.timeIntervalSince1970)"
      let deduplicationKey = event.calendarItemExternalIdentifier.map {
        "\($0)|\(occurrenceDate.timeIntervalSince1970)"
      }
      return CalendarEventItem(
        id: CalendarEventItem.compositeID(
          accountID: Self.accountID,
          calendarID: event.calendar.calendarIdentifier,
          eventID: occurrenceID
        ),
        title: event.title ?? "",
        startDate: startDate,
        endDate: endDate,
        location: event.location,
        calendarURL: nil,
        openURL: event.url,
        sourceCalendarNames: [event.calendar.title],
        sourceIDs: [CalendarEventItem.sourceID(accountID: Self.accountID, calendarID: event.calendar.calendarIdentifier)],
        deduplicationKey: deduplicationKey
      )
    }
  }
}

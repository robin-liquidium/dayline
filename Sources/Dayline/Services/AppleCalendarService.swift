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
        isEnabled: true,
        allowsModifications: calendar.allowsContentModifications
      )
    }
  }

  /// Identifier of the system calendar used for newly created events.
  func defaultCalendarIDForNewEvents() -> String? {
    guard hasFullAccess else { return nil }
    return eventStore.defaultCalendarForNewEvents?.calendarIdentifier
  }

  /// Creates one explicitly confirmed event in a writable device calendar.
  func createEvent(_ draft: AppleCalendarEventCreateDraft) throws {
    guard hasFullAccess else { throw AppleCalendarServiceError.accessDenied }
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw AppleCalendarServiceError.missingTitle }
    guard let calendar = eventStore.calendar(withIdentifier: draft.calendarID),
          calendar.allowsContentModifications else {
      throw AppleCalendarServiceError.calendarNotWritable
    }

    let event = EKEvent(eventStore: eventStore)
    event.title = title
    event.calendar = calendar
    event.isAllDay = draft.isAllDay
    if draft.isAllDay {
      let startDay = Calendar.current.startOfDay(for: draft.startDate)
      let selectedEndDay = Calendar.current.startOfDay(for: draft.endDate)
      guard selectedEndDay >= startDay else { throw AppleCalendarServiceError.invalidDateRange }
      event.startDate = startDay
      event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedEndDay)
        ?? selectedEndDay.addingTimeInterval(24 * 60 * 60)
    } else {
      guard draft.endDate > draft.startDate else { throw AppleCalendarServiceError.invalidDateRange }
      event.startDate = draft.startDate
      event.endDate = draft.endDate
    }

    do {
      try eventStore.save(event, span: .thisEvent, commit: true)
    } catch {
      eventStore.reset()
      throw error
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
      guard let eventID = event.eventIdentifier,
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
        isAllDay: event.isAllDay,
        calendarURL: nil,
        openURL: event.url,
        sourceCalendarNames: [event.calendar.title],
        sourceIDs: [CalendarEventItem.sourceID(accountID: Self.accountID, calendarID: event.calendar.calendarIdentifier)],
        deduplicationKey: deduplicationKey
      )
    }
  }
}

/// User-actionable failures from Apple Calendar event creation.
enum AppleCalendarServiceError: LocalizedError {
  case accessDenied
  case missingTitle
  case calendarNotWritable
  case invalidDateRange

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Apple Calendar access is unavailable. Reconnect it in Settings."
    case .missingTitle:
      "Enter an event title."
    case .calendarNotWritable:
      "Choose a writable Apple calendar."
    case .invalidDateRange:
      "The event must end after it starts."
    }
  }
}

import EventKit
import Foundation

/// Reads device calendars and events through EventKit.
final class AppleCalendarService: @unchecked Sendable {
  /// Stable local identifier namespacing Apple-sourced event identities.
  static let accountID = UUID(uuidString: "a9c0ffee-0000-4000-8000-0000000000a9")!

  /// One long-lived store: creating an EKEventStore per refresh is expensive and
  /// a shared store is what receives EKEventStoreChanged notifications.
  private let eventStore = EKEventStore()
  private var changeObserver: NSObjectProtocol?
  /// Serializes background reads with saves and resets, which invalidate EKEvent objects.
  private let storeLock = NSLock()

  deinit {
    if let changeObserver {
      NotificationCenter.default.removeObserver(changeObserver)
    }
  }

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
    let granted = try await eventStore.requestFullAccessToEvents()
    if granted {
      // Make calendars granted just now visible to the long-lived store.
      storeLock.withLock { eventStore.reset() }
    }
    return granted
  }

  /// Calls the handler on the main actor whenever calendar data changes outside Dayline.
  func setChangeHandler(_ handler: @escaping @MainActor () -> Void) {
    guard changeObserver == nil else { return }
    changeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { _ in
      MainActor.assumeIsolated { handler() }
    }
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
    // Held from lookup through save so a concurrent reset cannot invalidate the objects.
    storeLock.lock()
    defer { storeLock.unlock() }
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

  /// Loads events from the selected calendars in the given window, skipping
  /// canceled events and invitations the user declined.
  func events(in calendarIDs: Set<String>, from start: Date, to end: Date) -> [CalendarEventItem] {
    storeLock.lock()
    defer { storeLock.unlock() }
    let calendars = eventStore.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
    guard !calendars.isEmpty else {
      return []
    }
    let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
    let matches = eventStore.events(matching: predicate)
    // A decline hides that meeting's other copies in the same account (e.g. a
    // shared calendar), but never a copy another account may have accepted.
    var declinedKeysBySource: [String: Set<String>] = [:]
    for event in matches where Self.currentUserDeclined(event) {
      if let key = Self.occurrenceKey(event) {
        declinedKeysBySource[event.calendar.source.sourceIdentifier, default: []].insert(key)
      }
    }
    return matches.compactMap { event in
      if Self.currentUserDeclined(event) {
        return nil
      }
      if let key = Self.occurrenceKey(event),
         declinedKeysBySource[event.calendar.source.sourceIdentifier]?.contains(key) == true {
        return nil
      }
      guard event.status != .canceled,
            let eventID = event.eventIdentifier,
            let startDate = event.startDate,
            let endDate = event.endDate else {
        return nil
      }
      let occurrenceDate = event.occurrenceDate ?? startDate
      let occurrenceID = "\(eventID)|\(occurrenceDate.timeIntervalSince1970)"
      let deduplicationKey = Self.occurrenceKey(event)
      let eventURL = CalendarEventItem.safeWebURL(event.url)
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
        meetingURL: CalendarEventItem.recognizedMeetingURL(eventURL),
        openURL: eventURL,
        sourceCalendarNames: [event.calendar.title],
        sourceIDs: [CalendarEventItem.sourceID(accountID: Self.accountID, calendarID: event.calendar.calendarIdentifier)],
        deduplicationKey: deduplicationKey
      )
    }
  }
}

extension AppleCalendarService {
  /// Key shared with other copies of this occurrence, such as the Google event.
  static func occurrenceKey(_ event: EKEvent) -> String? {
    guard let externalID = event.calendarItemExternalIdentifier,
          let occurrenceDate = event.occurrenceDate ?? event.startDate else {
      return nil
    }
    return "\(externalID)|\(occurrenceDate.timeIntervalSince1970)"
  }

  /// Whether the signed-in user declined this invitation.
  static func currentUserDeclined(_ event: EKEvent) -> Bool {
    event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
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

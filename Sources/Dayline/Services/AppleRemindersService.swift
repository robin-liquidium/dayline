import EventKit
import Foundation

/// EventKit operations used by the Apple Reminders issue provider.
@MainActor
protocol AppleRemindersServing: AnyObject {
  var hasFullAccess: Bool { get }
  func requestFullAccess() async throws -> Bool
  func reminderLists() -> [AppleReminderList]
  func defaultReminderListID() -> String?
  func fetchIncompleteReminders(in listIDs: Set<String>) async throws -> [AppleReminderItem]
  func createReminder(_ draft: AppleReminderCreateDraft) throws -> AppleReminderItem
  func setReminderCompleted(id: String) throws
  func updateReminderPriority(id: String, priority: AppleReminderPriority) throws -> AppleReminderItem
  func updateReminderDueDate(id: String, dueDate: Date?) throws -> AppleReminderItem
  func setChangeHandler(_ handler: (@MainActor () -> Void)?)
}

/// Reads and changes Apple Reminders through EventKit.
@MainActor
final class AppleRemindersService: AppleRemindersServing {
  private let eventStore: EKEventStore
  private var changeObserver: NSObjectProtocol?
  private var changeHandler: (@MainActor () -> Void)?

  init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
  }

  deinit {
    if let changeObserver {
      NotificationCenter.default.removeObserver(changeObserver)
    }
  }

  /// Whether this bundle includes the privacy string required before requesting access.
  static var canRequestAccess: Bool {
    Bundle.main.object(forInfoDictionaryKey: "NSRemindersFullAccessUsageDescription") != nil
  }

  /// Whether Dayline currently has read/write access to Reminders.
  var hasFullAccess: Bool {
    EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
  }

  /// Requests full Reminders access and resets the store so newly granted data is visible.
  func requestFullAccess() async throws -> Bool {
    let granted = try await eventStore.requestFullAccessToReminders()
    if granted {
      eventStore.reset()
    }
    return granted
  }

  /// Lists every Reminders list, including read-only lists that can still be displayed.
  func reminderLists() -> [AppleReminderList] {
    guard hasFullAccess else { return [] }
    return eventStore.calendars(for: .reminder)
      .map { calendar in
        AppleReminderList(
          id: calendar.calendarIdentifier,
          title: calendar.title,
          sourceName: calendar.source.title,
          sourceID: calendar.source.sourceIdentifier,
          isEnabled: true,
          allowsModifications: calendar.allowsContentModifications
        )
      }
      .sorted {
        let sourceComparison = $0.sourceName.localizedStandardCompare($1.sourceName)
        if sourceComparison != .orderedSame { return sourceComparison == .orderedAscending }
        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
      }
  }

  /// Identifier of the system list used for newly created reminders.
  func defaultReminderListID() -> String? {
    guard hasFullAccess else { return nil }
    return eventStore.defaultCalendarForNewReminders()?.calendarIdentifier
  }

  /// Fetches all incomplete reminders from the selected lists.
  func fetchIncompleteReminders(in listIDs: Set<String>) async throws -> [AppleReminderItem] {
    guard hasFullAccess else { throw AppleRemindersServiceError.accessDenied }
    let calendars = eventStore.calendars(for: .reminder).filter {
      listIDs.contains($0.calendarIdentifier)
    }
    guard !calendars.isEmpty else { return [] }

    let predicate = eventStore.predicateForIncompleteReminders(
      withDueDateStarting: nil,
      ending: nil,
      calendars: calendars
    )
    return try await withCheckedThrowingContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        guard let reminders else {
          continuation.resume(throwing: AppleRemindersServiceError.fetchFailed)
          return
        }
        continuation.resume(returning: reminders.map(Self.item(from:)))
      }
    }
  }

  /// Creates a new reminder in one writable selected list.
  func createReminder(_ draft: AppleReminderCreateDraft) throws -> AppleReminderItem {
    guard hasFullAccess else { throw AppleRemindersServiceError.accessDenied }
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { throw AppleRemindersServiceError.missingTitle }
    let calendar = try writableCalendar(with: draft.listID)

    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    reminder.title = title
    let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    reminder.notes = notes.isEmpty ? nil : notes
    reminder.priority = draft.priority.rawValue
    reminder.dueDateComponents = draft.dueDate.map {
      Self.dateComponents(for: $0, includesTime: draft.dueDateIncludesTime)
    }
    try eventStore.save(reminder, commit: true)
    return Self.item(from: reminder)
  }

  /// Marks an incomplete reminder complete. EventKit advances recurring reminders itself.
  func setReminderCompleted(id: String) throws {
    let reminder = try writableReminder(with: id)
    reminder.isCompleted = true
    try eventStore.save(reminder, commit: true)
  }

  /// Changes a reminder's EventKit priority.
  func updateReminderPriority(
    id: String,
    priority: AppleReminderPriority
  ) throws -> AppleReminderItem {
    let reminder = try writableReminder(with: id)
    reminder.priority = priority.rawValue
    try eventStore.save(reminder, commit: true)
    return Self.item(from: reminder)
  }

  /// Changes or clears a reminder's due date while preserving an existing due time.
  func updateReminderDueDate(id: String, dueDate: Date?) throws -> AppleReminderItem {
    let reminder = try writableReminder(with: id)
    if let dueDate {
      let existing = reminder.dueDateComponents
      let includesTime = existing?.hour != nil || existing?.minute != nil || existing?.second != nil
      var components = Self.dateComponents(for: dueDate, includesTime: includesTime)
      if includesTime {
        components.hour = existing?.hour
        components.minute = existing?.minute
        components.second = existing?.second
        components.timeZone = existing?.timeZone ?? .current
      }
      reminder.dueDateComponents = components
    } else {
      reminder.dueDateComponents = nil
    }
    try eventStore.save(reminder, commit: true)
    return Self.item(from: reminder)
  }

  /// Observes EventKit changes so Dayline can refresh when Reminders changes elsewhere.
  func setChangeHandler(_ handler: (@MainActor () -> Void)?) {
    changeHandler = handler
    guard changeObserver == nil else { return }
    changeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.changeHandler?()
      }
    }
  }

  /// Converts an EventKit reminder into an actor-independent value model.
  private static func item(from reminder: EKReminder) -> AppleReminderItem {
    let components = reminder.dueDateComponents
    return AppleReminderItem(
      id: reminder.calendarItemIdentifier,
      title: reminder.title ?? "",
      notes: reminder.notes,
      listID: reminder.calendar.calendarIdentifier,
      listTitle: reminder.calendar.title,
      priority: AppleReminderPriority(eventKitValue: reminder.priority),
      dueDate: components.flatMap(dueDate(from:)),
      updatedAt: reminder.lastModifiedDate,
      url: reminder.url,
      isRecurring: reminder.hasRecurrenceRules,
      allowsModifications: reminder.calendar.allowsContentModifications
    )
  }

  /// Builds Gregorian EventKit components while preserving date-only floating semantics.
  private static func dateComponents(for date: Date, includesTime: Bool) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let units: Set<Calendar.Component> = includesTime
      ? [.year, .month, .day, .hour, .minute]
      : [.year, .month, .day]
    var components = calendar.dateComponents(units, from: date)
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = includesTime ? .current : nil
    return components
  }

  /// Preserves EventKit's floating date-only and timed due-date semantics.
  private static func dueDate(from components: DateComponents) -> AppleReminderDueDate? {
    let includesTime = components.hour != nil || components.minute != nil || components.second != nil
    if !includesTime,
       let year = components.year,
       let month = components.month,
       let day = components.day {
      return .dateOnly(year: year, month: month, day: day)
    }
    var calendar = components.calendar ?? Calendar(identifier: .gregorian)
    if let timeZone = components.timeZone {
      calendar.timeZone = timeZone
    }
    guard let date = calendar.date(from: components) else { return nil }
    return .timed(date, timeZoneIdentifier: components.timeZone?.identifier)
  }

  /// Returns one writable reminder from this service's event store.
  private func writableReminder(with id: String) throws -> EKReminder {
    guard hasFullAccess else { throw AppleRemindersServiceError.accessDenied }
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      throw AppleRemindersServiceError.reminderUnavailable
    }
    guard reminder.calendar.allowsContentModifications else {
      throw AppleRemindersServiceError.readOnlyList
    }
    return reminder
  }

  /// Returns one writable Reminders list from this service's event store.
  private func writableCalendar(with id: String) throws -> EKCalendar {
    guard let calendar = eventStore.calendar(withIdentifier: id),
          calendar.allowedEntityTypes.contains(.reminder) else {
      throw AppleRemindersServiceError.listUnavailable
    }
    guard calendar.allowsContentModifications else {
      throw AppleRemindersServiceError.readOnlyList
    }
    return calendar
  }
}

/// User-facing failures from EventKit reminder operations.
enum AppleRemindersServiceError: LocalizedError {
  case accessDenied
  case missingTitle
  case listUnavailable
  case readOnlyList
  case reminderUnavailable
  case fetchFailed

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      "Allow Dayline to access Reminders in System Settings → Privacy & Security → Reminders."
    case .missingTitle:
      "Enter a reminder title."
    case .listUnavailable:
      "That Reminders list is no longer available."
    case .readOnlyList:
      "That Reminders list is read-only."
    case .reminderUnavailable:
      "That reminder is no longer available."
    case .fetchFailed:
      "Apple Reminders did not return a reminder snapshot. Try refreshing again."
    }
  }
}

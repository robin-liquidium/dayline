import Foundation

/// One incomplete Apple Reminder normalized for Dayline's issue feed.
struct AppleReminderItem: Identifiable, Equatable, Sendable {
  /// EventKit's local calendar-item identifier.
  let id: String

  /// Reminder title.
  let title: String

  /// Optional reminder notes.
  let notes: String?

  /// Identifier of the Reminders list containing this item.
  let listID: String

  /// User-visible Reminders list name.
  let listTitle: String

  /// Normalized Apple Reminders priority.
  let priority: AppleReminderPriority

  /// Due date that preserves EventKit's distinction between floating dates and timed values.
  let dueDate: AppleReminderDueDate?

  /// Last modification timestamp reported by EventKit.
  let updatedAt: Date?

  /// Optional user-attached URL. This is not a deep link to Reminders.app.
  let url: URL?

  /// Whether this reminder repeats.
  let isRecurring: Bool

  /// Whether its containing list accepts changes.
  let allowsModifications: Bool

  /// Returns a copy with selected mutable fields replaced.
  func replacing(
    priority: AppleReminderPriority? = nil,
    dueDate: AppleReminderDueDate?? = nil,
    updatedAt: Date?? = nil
  ) -> AppleReminderItem {
    AppleReminderItem(
      id: id,
      title: title,
      notes: notes,
      listID: listID,
      listTitle: listTitle,
      priority: priority ?? self.priority,
      dueDate: dueDate ?? self.dueDate,
      updatedAt: updatedAt ?? self.updatedAt,
      url: url,
      isRecurring: isRecurring,
      allowsModifications: allowsModifications
    )
  }
}

/// Due-date semantics supported by Apple Reminders.
enum AppleReminderDueDate: Equatable, Sendable {
  /// A floating Gregorian date with no time or time zone.
  case dateOnly(year: Int, month: Int, day: Int)

  /// A timed due date, retaining its EventKit time-zone identity when supplied.
  case timed(Date, timeZoneIdentifier: String?)

  /// Date value suitable for SwiftUI controls and sorting.
  var date: Date {
    switch self {
    case .dateOnly(let year, let month, let day):
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = .current
      return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantFuture
    case .timed(let date, _):
      return date
    }
  }

  /// Whether this reminder has a specific due time.
  var includesTime: Bool {
    if case .timed = self { return true }
    return false
  }

  /// Whether this due value has passed.
  ///
  /// EventKit stores date-only components in the Gregorian calendar. Interpret those
  /// components as a floating Gregorian day in the user's time zone. Timed values are
  /// absolute instants, so their stored time-zone identity does not affect this comparison.
  func isOverdue(at now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
    switch self {
    case .dateOnly(let year, let month, let day):
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      guard let dueDay = calendar.date(from: DateComponents(
        year: year,
        month: month,
        day: day
      )) else { return false }
      return dueDay < calendar.startOfDay(for: now)
    case .timed(let date, _):
      return date < now
    }
  }

  /// Returns a due value on a new day while preserving any existing time and time zone.
  func replacingDay(with date: Date) -> AppleReminderDueDate {
    switch self {
    case .dateOnly:
      return Self.dateOnly(from: date)
    case .timed(let existingDate, let timeZoneIdentifier):
      let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
      var reminderCalendar = Calendar(identifier: .gregorian)
      reminderCalendar.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
      let time = reminderCalendar.dateComponents([.hour, .minute, .second], from: existingDate)
      let components = DateComponents(
        timeZone: reminderCalendar.timeZone,
        year: day.year,
        month: day.month,
        day: day.day,
        hour: time.hour,
        minute: time.minute,
        second: time.second
      )
      return .timed(
        reminderCalendar.date(from: components) ?? date,
        timeZoneIdentifier: timeZoneIdentifier
      )
    }
  }

  /// Creates a floating date-only reminder value in the current calendar.
  static func dateOnly(from date: Date) -> AppleReminderDueDate {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return .dateOnly(
      year: components.year ?? 1,
      month: components.month ?? 1,
      day: components.day ?? 1
    )
  }
}

/// Values collected by Dayline's new-reminder window.
struct AppleReminderCreateDraft: Equatable, Sendable {
  var title = ""
  var notes = ""
  var listID = ""
  var priority: AppleReminderPriority = .none
  var dueDate: Date?
  var dueDateIncludesTime = false
}

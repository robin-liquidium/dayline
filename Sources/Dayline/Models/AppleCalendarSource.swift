import Foundation

/// One device calendar exposed by EventKit with its Dayline selection.
struct AppleCalendarSource: Codable, Identifiable, Equatable, Sendable {
  /// EventKit calendar identifier.
  let id: String

  /// Calendar display name.
  var title: String

  /// Name of the source account or service owning the calendar.
  var sourceName: String

  /// Whether Dayline includes this calendar in the merged agenda.
  var isEnabled: Bool

  /// Whether EventKit allows Dayline to create events in this calendar.
  var allowsModifications: Bool = false

  /// Restores explicit saved choices while leaving newly discovered calendars enabled.
  static func restoringSelections(
    in discovered: [AppleCalendarSource],
    from persisted: [String: Bool]
  ) -> [AppleCalendarSource] {
    discovered.map { calendar in
      var calendar = calendar
      if let isEnabled = persisted[calendar.id] {
        calendar.isEnabled = isEnabled
      }
      return calendar
    }
  }
}

/// Values collected by Dayline's Apple Calendar event editor.
struct AppleCalendarEventCreateDraft: Equatable, Sendable {
  var title = ""
  var calendarID = ""
  var startDate = Date()
  var endDate = Date().addingTimeInterval(30 * 60)
  var isAllDay = false
}

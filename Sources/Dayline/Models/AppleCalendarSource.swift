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
}

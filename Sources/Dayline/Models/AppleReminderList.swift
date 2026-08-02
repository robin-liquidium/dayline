import Foundation

/// One Apple Reminders list exposed by EventKit.
struct AppleReminderList: Identifiable, Equatable, Sendable {
  /// EventKit calendar identifier for this Reminders list.
  let id: String

  /// User-visible list name.
  let title: String

  /// Account that owns the list, such as iCloud or On My Mac.
  let sourceName: String

  /// EventKit source identifier used to reconcile a list after a full sync changes its local ID.
  let sourceID: String

  /// Whether reminders from this list appear in Dayline.
  var isEnabled: Bool

  /// Whether EventKit allows Dayline to create and change reminders in this list.
  let allowsModifications: Bool

  /// Secondary persisted identity used only when it uniquely identifies a rediscovered list.
  var fallbackSelectionKey: String {
    "source:\(sourceID)|name:\(sourceName)|list:\(title)"
  }

  /// Restores explicit list selections while default-enabling newly discovered lists.
  static func restoringSelections(
    in discovered: [AppleReminderList],
    from persisted: [String: Bool]
  ) -> [AppleReminderList] {
    let fallbackCounts = Dictionary(grouping: discovered, by: \.fallbackSelectionKey)
      .mapValues(\.count)
    return discovered.map { list in
      var restored = list
      if let isEnabled = persisted[list.id] {
        restored.isEnabled = isEnabled
      } else if fallbackCounts[list.fallbackSelectionKey] == 1,
                let isEnabled = persisted[list.fallbackSelectionKey] {
        restored.isEnabled = isEnabled
      }
      return restored
    }
  }
}

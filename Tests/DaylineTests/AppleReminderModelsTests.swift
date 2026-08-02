import Foundation
import Testing
@testable import Dayline

struct AppleReminderModelsTests {
  @Test func eventKitPrioritiesNormalizeAcrossTheFullSupportedRange() {
    let expected: [AppleReminderPriority] = [
      .none, .high, .high, .high, .high, .medium, .low, .low, .low, .low
    ]
    #expect((0...9).map { AppleReminderPriority(eventKitValue: $0) } == expected)
    #expect(AppleReminderPriority(eventKitValue: -1) == .none)
    #expect(AppleReminderPriority(eventKitValue: 10) == .none)
  }

  @Test func changingTimedReminderDayPreservesTimeAndTimeZone() throws {
    let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let original = try #require(calendar.date(from: DateComponents(
      timeZone: timeZone,
      year: 2026,
      month: 3,
      day: 28,
      hour: 17,
      minute: 45
    )))
    let replacementDay = try #require(calendar.date(from: DateComponents(
      timeZone: timeZone,
      year: 2026,
      month: 3,
      day: 30,
      hour: 9
    )))

    let replaced = AppleReminderDueDate
      .timed(original, timeZoneIdentifier: timeZone.identifier)
      .replacingDay(with: replacementDay)

    guard case .timed(let date, let identifier) = replaced else {
      Issue.record("Expected a timed due date")
      return
    }
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    #expect(identifier == timeZone.identifier)
    #expect(components.year == 2026)
    #expect(components.month == 3)
    #expect(components.day == 30)
    #expect(components.hour == 17)
    #expect(components.minute == 45)
  }

  @Test func listSelectionsSurviveIdentifierChangesOnlyWhenFallbackIsUnique() {
    let original = AppleReminderList(
      id: "old-id",
      title: "Work",
      sourceName: "iCloud",
      sourceID: "icloud-source",
      isEnabled: true,
      allowsModifications: true
    )
    let rediscovered = AppleReminderList(
      id: "new-id",
      title: "Work",
      sourceName: "iCloud",
      sourceID: "icloud-source",
      isEnabled: true,
      allowsModifications: true
    )
    let restored = AppleReminderList.restoringSelections(
      in: [rediscovered],
      from: [original.fallbackSelectionKey: false]
    )
    #expect(restored.map(\.isEnabled) == [false])

    let duplicate = AppleReminderList(
      id: "second-new-id",
      title: "Work",
      sourceName: "iCloud",
      sourceID: "icloud-source",
      isEnabled: true,
      allowsModifications: true
    )
    let ambiguous = AppleReminderList.restoringSelections(
      in: [rediscovered, duplicate],
      from: [original.fallbackSelectionKey: false]
    )
    #expect(ambiguous.map(\.isEnabled) == [true, true])
  }

  @Test func everyIssueProviderCombinationHasStableTabOrder() {
    #expect(IssueSource.available(linear: false, github: false, reminders: false) == [])
    #expect(IssueSource.available(linear: true, github: false, reminders: false) == [.linear])
    #expect(IssueSource.available(linear: false, github: true, reminders: false) == [.github])
    #expect(IssueSource.available(linear: false, github: false, reminders: true) == [.reminders])
    #expect(IssueSource.available(linear: true, github: true, reminders: false) == [.linear, .github])
    #expect(IssueSource.available(linear: true, github: false, reminders: true) == [.linear, .reminders])
    #expect(IssueSource.available(linear: false, github: true, reminders: true) == [.github, .reminders])
    #expect(IssueSource.available(linear: true, github: true, reminders: true) == [.linear, .github, .reminders])
  }
}

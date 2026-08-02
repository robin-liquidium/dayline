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

  @Test func dateOnlyCreationUsesGregorianDayFromNonGregorianUserCalendar() throws {
    let userTimeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = userTimeZone
    let selectedDate = try #require(buddhist.date(from: DateComponents(
      timeZone: userTimeZone,
      year: 2569,
      month: 8,
      day: 2,
      hour: 0,
      minute: 30
    )))

    #expect(AppleReminderDueDate.dateOnly(
      from: selectedDate,
      currentTimeZone: userTimeZone
    ) == .dateOnly(year: 2026, month: 8, day: 2))
  }

  @Test func timedDayReplacementUsesGregorianPickerDayInUserTimeZone() throws {
    let userTimeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
    let reminderTimeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    var buddhist = Calendar(identifier: .buddhist)
    buddhist.timeZone = userTimeZone
    let selectedDate = try #require(buddhist.date(from: DateComponents(
      timeZone: userTimeZone,
      year: 2569,
      month: 8,
      day: 2,
      hour: 0,
      minute: 30
    )))
    var reminderCalendar = Calendar(identifier: .gregorian)
    reminderCalendar.timeZone = reminderTimeZone
    let existingDate = try #require(reminderCalendar.date(from: DateComponents(
      timeZone: reminderTimeZone,
      year: 2026,
      month: 7,
      day: 20,
      hour: 17,
      minute: 45
    )))

    let replaced = AppleReminderDueDate
      .timed(existingDate, timeZoneIdentifier: reminderTimeZone.identifier)
      .replacingDay(with: selectedDate, currentTimeZone: userTimeZone)

    guard case .timed(let date, let identifier) = replaced else {
      Issue.record("Expected a timed due date")
      return
    }
    let components = reminderCalendar.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: date
    )
    #expect(identifier == reminderTimeZone.identifier)
    #expect(components.year == 2026)
    #expect(components.month == 8)
    #expect(components.day == 2)
    #expect(components.hour == 17)
    #expect(components.minute == 45)
  }

  @Test func timedReminderEarlierTodayIsOverdue() throws {
    let (calendar, now) = try overdueTestClock()
    let dueDate = try #require(calendar.date(byAdding: .hour, value: -1, to: now))
    #expect(AppleReminderDueDate.timed(dueDate, timeZoneIdentifier: nil).isOverdue(
      at: now
    ))
  }

  @Test func timedReminderLaterTodayIsNotOverdue() throws {
    let (calendar, now) = try overdueTestClock()
    let dueDate = try #require(calendar.date(byAdding: .hour, value: 1, to: now))
    #expect(!AppleReminderDueDate.timed(dueDate, timeZoneIdentifier: nil).isOverdue(
      at: now
    ))
  }

  @Test func dateOnlyReminderDueTodayIsNotOverdue() throws {
    let (calendar, now) = try overdueTestClock()
    #expect(!AppleReminderDueDate.dateOnly(year: 2026, month: 8, day: 2).isOverdue(
      at: now,
      timeZone: calendar.timeZone
    ))
  }

  @Test func dateOnlyReminderDueYesterdayIsOverdue() throws {
    let (calendar, now) = try overdueTestClock()
    #expect(AppleReminderDueDate.dateOnly(year: 2026, month: 8, day: 1).isOverdue(
      at: now,
      timeZone: calendar.timeZone
    ))
  }

  @Test func dateOnlyReminderAlwaysUsesGregorianCalendarInUserTimeZone() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = timeZone
    let now = try #require(gregorian.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 2,
      hour: 12
    )))
    var userCalendar = Calendar(identifier: .buddhist)
    userCalendar.timeZone = timeZone

    #expect(userCalendar.component(.year, from: now) == 2569)
    #expect(!AppleReminderDueDate.dateOnly(year: 2026, month: 8, day: 2).isOverdue(
      at: now,
      timeZone: timeZone
    ))
  }

  private func overdueTestClock() throws -> (Calendar, Date) {
    let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let now = try #require(calendar.date(from: DateComponents(
      timeZone: timeZone,
      year: 2026,
      month: 8,
      day: 2,
      hour: 12
    )))
    return (calendar, now)
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

  @MainActor
  @Test func temporarilyUndiscoveredListSelectionsRemainPersisted() {
    let discovered = AppleReminderList(
      id: "visible-id",
      title: "Visible",
      sourceName: "iCloud",
      sourceID: "icloud",
      isEnabled: true,
      allowsModifications: true
    )
    let merged = StatusStore.mergingAppleReminderSelections(
      persisted: ["temporarily-missing-id": false],
      discoveredLists: [discovered]
    )

    #expect(merged["temporarily-missing-id"] == false)
    #expect(merged[discovered.id] == true)
    #expect(merged[discovered.fallbackSelectionKey] == true)
  }
}

@MainActor
@Suite(.serialized)
struct AppleReminderStatusStoreTests {
  @Test func staleDisconnectedLoadCannotClearNewerReminderSnapshot() {
    #expect(StatusStore.appleReminderLoadIsCurrent(
      capturedRevision: 4,
      capturedConnected: false,
      currentRevision: 4,
      currentConnected: false
    ))
    #expect(!StatusStore.appleReminderLoadIsCurrent(
      capturedRevision: 4,
      capturedConnected: false,
      currentRevision: 5,
      currentConnected: false
    ))
    #expect(!StatusStore.appleReminderLoadIsCurrent(
      capturedRevision: 4,
      capturedConnected: false,
      currentRevision: 4,
      currentConnected: true
    ))
  }

  @Test func creatorRequestStillAdvancesWithoutWritableEnabledLists() {
    let store = StatusStore(mockData: MockData.make(issueSources: [.reminders]))
    for list in store.appleReminderLists where list.allowsModifications {
      store.setAppleReminderListEnabled(list.id, enabled: false)
    }
    let previousRequest = store.appleReminderCreationRequestID

    #expect(!store.canCreateAppleReminder)
    store.requestAppleReminderCreation()
    #expect(store.appleReminderCreationRequestID != previousRequest)
  }

  @Test func disconnectDoesNotErasePreferredCreationList() {
    let store = StatusStore(mockData: MockData.make(issueSources: [.reminders]))
    let preferredListID = store.appleReminderCreateDefaultListID
    #expect(!preferredListID.isEmpty)

    store.disconnectAppleReminders()

    #expect(store.appleReminderCreateDefaultListID == preferredListID)
  }

  @Test func createdReminderExpandsVisibleSliceWhenSortPlacesItLater() async throws {
    let store = StatusStore(mockData: MockData.make(issueSources: [.reminders]))
    let listID = try #require(store.writableAppleReminderLists.last?.id)
    let title = "Late sorted reminder \(UUID().uuidString)"

    try await store.createAppleReminder(draft: AppleReminderCreateDraft(
      title: title,
      notes: "Visible immediately",
      listID: listID,
      priority: .none,
      dueDate: nil,
      dueDateIncludesTime: false
    ))

    #expect(store.appleReminders.contains(where: { $0.title == title }))
  }

  @Test func createdReminderPreservesSupportedDraftFields() async throws {
    let store = StatusStore(mockData: MockData.make(issueSources: [.reminders]))
    let list = try #require(store.writableAppleReminderLists.last)
    let dueDate = Date(timeIntervalSince1970: 1_786_000_000)
    let title = "Field mapping (UUID().uuidString)"

    try await store.createAppleReminder(draft: AppleReminderCreateDraft(
      title: title,
      notes: "Mapped notes",
      listID: list.id,
      priority: .low,
      dueDate: dueDate,
      dueDateIncludesTime: true
    ))

    let created = try #require(store.appleReminders.first(where: { $0.title == title }))
    #expect(created.notes == "Mapped notes")
    #expect(created.listID == list.id)
    #expect(created.priority == .low)
    #expect(created.dueDate == .timed(dueDate, timeZoneIdentifier: TimeZone.current.identifier))
  }
}

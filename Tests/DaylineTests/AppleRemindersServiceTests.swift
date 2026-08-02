import Foundation
import Testing
@testable import Dayline

@MainActor
struct AppleRemindersServiceTests {
  @Test func replacingTimedDueDayPreservesFloatingTimeZoneAndVisibleDay() throws {
    let pickerTimeZone = try #require(TimeZone(secondsFromGMT: 2 * 60 * 60))
    let selectedDate = try #require(ISO8601DateFormatter().date(from: "2026-08-04T22:30:00Z"))
    let existing = DateComponents(
      calendar: Calendar(identifier: .gregorian),
      timeZone: nil,
      year: 2026,
      month: 7,
      day: 1,
      hour: 9,
      minute: 45
    )

    let replaced = AppleRemindersService.dueDateComponents(
      replacingDayWith: selectedDate,
      existing: existing,
      currentTimeZone: pickerTimeZone
    )

    #expect(replaced.year == 2026)
    #expect(replaced.month == 8)
    #expect(replaced.day == 5)
    #expect(replaced.hour == 9)
    #expect(replaced.minute == 45)
    #expect(replaced.timeZone == nil)
  }

  @Test func replacingTimedDueDayPreservesExplicitTimeZone() throws {
    let reminderTimeZone = try #require(TimeZone(identifier: "America/New_York"))
    let pickerTimeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    let selectedDate = try #require(ISO8601DateFormatter().date(from: "2026-08-05T10:00:00Z"))
    let existing = DateComponents(
      calendar: Calendar(identifier: .gregorian),
      timeZone: reminderTimeZone,
      year: 2026,
      month: 7,
      day: 1,
      hour: 17,
      minute: 15
    )

    let replaced = AppleRemindersService.dueDateComponents(
      replacingDayWith: selectedDate,
      existing: existing,
      currentTimeZone: pickerTimeZone
    )

    #expect(replaced.day == 5)
    #expect(replaced.hour == 17)
    #expect(replaced.minute == 15)
    #expect(replaced.timeZone == reminderTimeZone)
  }

  @Test func reminderPreviewOnlyAllowsWebURLs() {
    #expect(AppleReminderPreviewPopover.safeAttachedURL(URL(string: "https://example.com")) != nil)
    #expect(AppleReminderPreviewPopover.safeAttachedURL(URL(string: "http://example.com")) != nil)
    #expect(AppleReminderPreviewPopover.safeAttachedURL(URL(string: "file:///tmp/private")) == nil)
    #expect(AppleReminderPreviewPopover.safeAttachedURL(URL(string: "x-apple-reminder://unsafe")) == nil)
  }

  @Test func inertServiceNeverExposesEventKitData() async throws {
    let service = InertAppleRemindersService()
    #expect(!service.hasFullAccess)
    #expect(service.reminderLists().isEmpty)
    #expect(service.defaultReminderListID() == nil)
    #expect(try await service.fetchIncompleteReminders(in: ["anything"]) == [])
  }

  @Test func unauthorizedStoreDegradesWithoutReadingReminderData() async {
    let service = AppleRemindersService()
    guard !service.hasFullAccess else { return }

    #expect(service.reminderLists().isEmpty)
    #expect(service.defaultReminderListID() == nil)
    do {
      _ = try await service.fetchIncompleteReminders(in: ["missing"])
      Issue.record("Expected an access-denied failure")
    } catch AppleRemindersServiceError.accessDenied {
      // Expected: the test runner has no Reminders permission.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

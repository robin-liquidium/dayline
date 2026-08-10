import Foundation
import Testing
@testable import Dayline

struct MockDataTests {
  @Test func tomorrowEventsStayWithinTomorrowLateInTheDay() throws {
    let calendar = Calendar.current
    let now = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 19,
      hour: 23,
      minute: 30
    )))
    let tomorrowStart = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
    let dayAfterStart = try #require(calendar.date(byAdding: .day, value: 1, to: tomorrowStart))

    let events = MockData.make(now: now).tomorrowEvents

    #expect(!events.isEmpty)
    #expect(events.allSatisfy { $0.startDate >= tomorrowStart && $0.startDate < dayAfterStart })
  }

  @Test func mockCanRepresentRemindersAsTheOnlyIssueProvider() {
    let mock = MockData.make(issueSources: [.reminders])
    #expect(mock.issueSources == [.reminders])
    #expect(!mock.appleReminders.isEmpty)
    #expect(mock.connectionStatuses.first { $0.provider == .linear }?.state == .disconnected)
    #expect(mock.connectionStatuses.first { $0.provider == .github }?.state == .disconnected)
  }

  @Test @MainActor func allDayRowsSupportHoverPreviewAndCopyWhenVisible() throws {
    let store = StatusStore(mockData: MockData.make())
    store.setShowsAllDayEvents(true)
    let event = try #require(store.visibleAllDayEvents.first)

    store.setHoveredEvent(event.id)

    #expect(store.presentPreviewForHovered())
    #expect(store.previewTarget == .event(event.id))
    #expect(store.copyHoveredEventLink())
    #expect(store.copiedEventID == event.id)
  }
}

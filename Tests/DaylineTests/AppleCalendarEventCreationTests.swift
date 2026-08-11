import Foundation
import Testing
@testable import Dayline

struct AppleCalendarEventCreationTests {
  @Test @MainActor func mockStoreExposesOnlyWritableEnabledCalendarsForCreation() throws {
    let store = StatusStore(mockData: MockData.make())

    #expect(store.appleCalendarConnected)
    #expect(store.hasConnectedGoogleCalendar)
    #expect(store.canCreateAppleCalendarEvent)
    #expect(store.writableAppleCalendars.map(\.id) == ["mock-apple-work"])
    #expect(store.defaultAppleCalendarEventCalendarID == "mock-apple-work")
  }

  @Test @MainActor func eventCreationRequestAlwaysAdvances() {
    let store = StatusStore(mockData: MockData.make())
    let previousRequest = store.appleCalendarEventCreationRequestID

    store.requestAppleCalendarEventCreation()

    #expect(store.appleCalendarEventCreationRequestID != previousRequest)
  }

  @Test @MainActor func mockAllDayCreationStoresAnExclusiveEndDate() async throws {
    let store = StatusStore(mockData: MockData.make())
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
    let inclusiveEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))

    try await store.createAppleCalendarEvent(draft: AppleCalendarEventCreateDraft(
      title: "Conference",
      calendarID: "mock-apple-work",
      startDate: start,
      endDate: inclusiveEnd,
      isAllDay: true
    ))

    let created = try #require(store.allDayEvents.first(where: { $0.title == "Conference" }))
    #expect(created.isAllDay)
    #expect(created.startDate == start)
    #expect(created.endDate == calendar.date(byAdding: .day, value: 1, to: inclusiveEnd))
    #expect(!store.events.contains(where: { $0.id == created.id }))
  }

  @Test @MainActor func mockTimedCreationRejectsInvalidRanges() async {
    let store = StatusStore(mockData: MockData.make())
    let start = Date(timeIntervalSince1970: 10_000)

    await #expect(throws: AppleCalendarServiceError.self) {
      try await store.createAppleCalendarEvent(draft: AppleCalendarEventCreateDraft(
        title: "Broken",
        calendarID: "mock-apple-work",
        startDate: start,
        endDate: start,
        isAllDay: false
      ))
    }
  }
}

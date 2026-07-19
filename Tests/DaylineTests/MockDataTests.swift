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
}

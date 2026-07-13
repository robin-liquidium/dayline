import Foundation
import Testing
@testable import Dayline

struct CalendarEventItemTests {
  @Test func menuBarCandidateKeepsActiveEventAheadOfUpcomingEvent() {
    let now = Date(timeIntervalSince1970: 10_000)
    let activeEvent = event(
      id: "active",
      startDate: now.addingTimeInterval(-20 * 60),
      endDate: now.addingTimeInterval(10 * 60)
    )
    let upcomingEvent = event(
      id: "upcoming",
      startDate: now.addingTimeInterval(5 * 60),
      endDate: now.addingTimeInterval(35 * 60)
    )

    let candidate = CalendarEventItem.menuBarCandidate(
      in: [activeEvent, upcomingEvent],
      at: now,
      leadTime: 30 * 60,
      postStartGrace: 5 * 60
    )

    #expect(candidate == activeEvent)
  }

  @Test func menuBarCandidateShowsUpcomingEventWithinLeadTime() {
    let now = Date(timeIntervalSince1970: 10_000)
    let upcomingEvent = event(
      id: "upcoming",
      startDate: now.addingTimeInterval(20 * 60),
      endDate: now.addingTimeInterval(50 * 60)
    )

    let candidate = CalendarEventItem.menuBarCandidate(
      in: [upcomingEvent],
      at: now,
      leadTime: 30 * 60,
      postStartGrace: 5 * 60
    )

    #expect(candidate == upcomingEvent)
  }

  @Test func menuBarCandidateReturnsNothingOutsideDisplayWindow() {
    let now = Date(timeIntervalSince1970: 10_000)
    let laterEvent = event(
      id: "later",
      startDate: now.addingTimeInterval(45 * 60),
      endDate: now.addingTimeInterval(75 * 60)
    )

    let candidate = CalendarEventItem.menuBarCandidate(
      in: [laterEvent],
      at: now,
      leadTime: 30 * 60,
      postStartGrace: 5 * 60
    )

    #expect(candidate == nil)
  }

  private func event(id: String, startDate: Date, endDate: Date) -> CalendarEventItem {
    CalendarEventItem(
      id: id,
      title: id,
      startDate: startDate,
      endDate: endDate,
      location: nil,
      calendarURL: nil,
      openURL: nil
    )
  }
}

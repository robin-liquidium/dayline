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

  @Test func menuBarCandidateIncludesUpcomingEventAtLeadTimeBoundary() {
    let now = Date(timeIntervalSince1970: 10_000)
    let upcomingEvent = event(
      id: "upcoming",
      startDate: now.addingTimeInterval(30 * 60),
      endDate: now.addingTimeInterval(60 * 60)
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

  @Test func mergedAgendaCollapsesSharedMeetingOccurrenceAndCombinesSources() {
    let start = Date(timeIntervalSince1970: 20_000)
    let workCopy = event(
      id: "work-copy",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      source: "Work",
      deduplicationKey: "meeting-uid|20000"
    )
    let personalCopy = event(
      id: "personal-copy",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      source: "Personal",
      deduplicationKey: "meeting-uid|20000"
    )

    let merged = CalendarEventItem.mergedAgenda([personalCopy, workCopy])

    #expect(merged.count == 1)
    #expect(merged[0].sourceCalendarNames == ["Personal", "Work"])
    #expect(merged[0].sourceLabel == "Personal +1")
  }

  @Test func mergedAgendaKeepsUsefulFieldsAndDistinctSourcesFromDuplicateCopies() {
    let start = Date(timeIntervalSince1970: 20_000)
    let sparseCopy = event(
      id: "a-sparse",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      source: "Work",
      deduplicationKey: "meeting-uid|20000"
    )
    let linkedCopy = CalendarEventItem(
      id: "b-linked",
      title: "b-linked",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      location: "Studio",
      calendarURL: URL(string: "https://calendar.google.com"),
      openURL: URL(string: "https://meet.google.com/example"),
      sourceCalendarNames: ["Work", "Shared"],
      deduplicationKey: "meeting-uid|20000"
    )

    let merged = CalendarEventItem.mergedAgenda([sparseCopy, linkedCopy])

    #expect(merged.count == 1)
    #expect(merged[0].location == "Studio")
    #expect(merged[0].openURL == URL(string: "https://meet.google.com/example"))
    #expect(merged[0].sourceCalendarNames == ["Work", "Shared"])
  }

  @Test func rebuildingAfterSourceRemovalUsesTheRemainingSourcePayload() throws {
    let firstAccountID = UUID()
    let secondAccountID = UUID()
    let start = Date(timeIntervalSince1970: 20_000)
    let first = event(
      id: CalendarEventItem.compositeID(accountID: firstAccountID, calendarID: "work", eventID: "meeting"),
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      source: "Work",
      deduplicationKey: "meeting-uid|20000",
      sourceIDs: [CalendarEventItem.sourceID(accountID: firstAccountID, calendarID: "work")]
    )
    let second = event(
      id: CalendarEventItem.compositeID(accountID: secondAccountID, calendarID: "shared", eventID: "meeting"),
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      source: "Shared",
      deduplicationKey: "meeting-uid|20000",
      sourceIDs: [CalendarEventItem.sourceID(accountID: secondAccountID, calendarID: "shared")]
    )

    let disabledSourceID = CalendarEventItem.sourceID(accountID: firstAccountID, calendarID: "work")
    let remainingRawEvents = [first, second].filter { !$0.sourceIDs.contains(disabledSourceID) }
    let remaining = try #require(CalendarEventItem.mergedAgenda(remainingRawEvents).first)

    #expect(remaining.sourceCalendarNames == ["Shared"])
    #expect(remaining.sourceIDs == [CalendarEventItem.sourceID(accountID: secondAccountID, calendarID: "shared")])
  }

  @Test func agendaSectionsIncludesAnOvernightEventInTomorrow() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let overnight = event(
      id: "overnight",
      startDate: tomorrowStart.addingTimeInterval(-60 * 60),
      endDate: tomorrowStart.addingTimeInterval(60 * 60)
    )

    let sections = CalendarEventItem.agendaSections(
      from: [overnight],
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: 6,
      tomorrowLimit: 8
    )

    #expect(sections.today == [overnight])
    #expect(sections.tomorrow == [overnight])
  }

  @Test func mergedAgendaKeepsRecurringOccurrencesSeparate() {
    let firstStart = Date(timeIntervalSince1970: 20_000)
    let secondStart = firstStart.addingTimeInterval(7 * 24 * 60 * 60)
    let first = event(
      id: "first",
      startDate: firstStart,
      endDate: firstStart.addingTimeInterval(30 * 60),
      source: "Work",
      deduplicationKey: "recurring-uid|20000"
    )
    let second = event(
      id: "second",
      startDate: secondStart,
      endDate: secondStart.addingTimeInterval(30 * 60),
      source: "Work",
      deduplicationKey: "recurring-uid|624800"
    )

    #expect(CalendarEventItem.mergedAgenda([second, first]).map(\.id) == ["first", "second"])
  }

  @Test func mergedAgendaDoesNotGuessDuplicatesWithoutICalendarUID() {
    let start = Date(timeIntervalSince1970: 20_000)
    let first = event(id: "first", startDate: start, endDate: start.addingTimeInterval(30 * 60))
    let second = event(id: "second", startDate: start, endDate: start.addingTimeInterval(30 * 60))

    #expect(CalendarEventItem.mergedAgenda([first, second]).count == 2)
  }

  @Test func compositeIDsRemainUniqueAcrossAccountsAndCalendars() {
    let firstAccount = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let secondAccount = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    let first = CalendarEventItem.compositeID(accountID: firstAccount, calendarID: "primary", eventID: "event-1")
    let secondCalendar = CalendarEventItem.compositeID(accountID: firstAccount, calendarID: "team", eventID: "event-1")
    let secondAccountID = CalendarEventItem.compositeID(accountID: secondAccount, calendarID: "primary", eventID: "event-1")

    #expect(Set([first, secondCalendar, secondAccountID]).count == 3)
  }

  @Test func agendaSectionsGloballySortsAndAppliesDayLimits() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let events = [
      event(id: "today-3", startDate: Date(timeIntervalSince1970: 30_000), endDate: Date(timeIntervalSince1970: 31_000)),
      event(id: "tomorrow-2", startDate: Date(timeIntervalSince1970: 100_000), endDate: Date(timeIntervalSince1970: 101_000)),
      event(id: "today-1", startDate: Date(timeIntervalSince1970: 10_000), endDate: Date(timeIntervalSince1970: 11_000)),
      event(id: "tomorrow-1", startDate: Date(timeIntervalSince1970: 90_000), endDate: Date(timeIntervalSince1970: 91_000)),
      event(id: "today-2", startDate: Date(timeIntervalSince1970: 20_000), endDate: Date(timeIntervalSince1970: 21_000))
    ]

    let sections = CalendarEventItem.agendaSections(
      from: events,
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: 2,
      tomorrowLimit: 1
    )

    #expect(sections.today.map(\.id) == ["today-1", "today-2"])
    #expect(sections.tomorrow.map(\.id) == ["tomorrow-1"])
  }

  @Test @MainActor func partialSourceFailureRetainsSuccessfulEvents() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let successfulEvent = event(
      id: "healthy-account-event",
      startDate: Date(timeIntervalSince1970: 20_000),
      endDate: Date(timeIntervalSince1970: 21_000)
    )

    let result = StatusStore.assembleCalendarAgenda(
      sourceBatches: [
        CalendarAgendaSourceBatch(events: [successfulEvent], warning: nil),
        CalendarAgendaSourceBatch(events: [], warning: "Work (other@example.com): Timed out")
      ],
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )

    #expect(result.today == [successfulEvent])
    #expect(result.warnings == ["Work (other@example.com): Timed out"])
    #expect(result.shouldReplaceEvents)
  }

  @Test @MainActor func totalSourceFailurePreservesThePreviousAgenda() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)

    let result = StatusStore.assembleCalendarAgenda(
      sourceBatches: [
        CalendarAgendaSourceBatch(events: [], warning: "Work: Timed out"),
        CalendarAgendaSourceBatch(events: [], warning: "Personal: Offline")
      ],
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )

    #expect(result.today.isEmpty)
    #expect(result.tomorrow.isEmpty)
    #expect(!result.shouldReplaceEvents)
  }

  private func event(
    id: String,
    startDate: Date,
    endDate: Date,
    source: String? = nil,
    deduplicationKey: String? = nil,
    sourceIDs: [String] = []
  ) -> CalendarEventItem {
    CalendarEventItem(
      id: id,
      title: id,
      startDate: startDate,
      endDate: endDate,
      location: nil,
      calendarURL: nil,
      openURL: nil,
      sourceCalendarNames: source.map { [$0] } ?? [],
      sourceIDs: sourceIDs,
      deduplicationKey: deduplicationKey
    )
  }
}

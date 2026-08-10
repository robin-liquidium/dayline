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

  @Test func menuBarCandidateNeverUsesAllDayEvents() {
    let now = Date(timeIntervalSince1970: 10_000)
    let allDay = event(
      id: "all-day",
      startDate: now.addingTimeInterval(-60 * 60),
      endDate: now.addingTimeInterval(20 * 60 * 60),
      isAllDay: true
    )

    let candidate = CalendarEventItem.menuBarCandidate(
      in: [allDay],
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
      meetingURL: URL(string: "https://meet.google.com/example"),
      openURL: URL(string: "https://meet.google.com/example"),
      sourceCalendarNames: ["Work", "Shared"],
      deduplicationKey: "meeting-uid|20000"
    )

    let merged = CalendarEventItem.mergedAgenda([sparseCopy, linkedCopy])

    #expect(merged.count == 1)
    #expect(merged[0].location == "Studio")
    #expect(merged[0].meetingURL == URL(string: "https://meet.google.com/example"))
    #expect(merged[0].openURL == URL(string: "https://meet.google.com/example"))
    #expect(merged[0].sourceCalendarNames == ["Work", "Shared"])
  }

  @Test func mergedAgendaPrefersARealJoinLinkOverAnUnrelatedURL() throws {
    let start = Date(timeIntervalSince1970: 20_000)
    let genericURL = try #require(URL(string: "https://example.com/agenda"))
    let meetingURL = try #require(URL(string: "https://meet.google.com/dayline-test"))
    let genericCopy = CalendarEventItem(
      id: "a-generic",
      title: "Meeting",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: nil,
      openURL: genericURL,
      deduplicationKey: "meeting-uid|20000"
    )
    let meetingCopy = CalendarEventItem(
      id: "b-meeting",
      title: "Meeting",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: nil,
      meetingURL: meetingURL,
      openURL: meetingURL,
      deduplicationKey: "meeting-uid|20000"
    )

    let merged = try #require(CalendarEventItem.mergedAgenda([genericCopy, meetingCopy]).first)

    #expect(merged.meetingURL == meetingURL)
    #expect(merged.openURL == meetingURL)
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
      todayStart: Date(timeIntervalSince1970: 0),
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
      todayStart: Date(timeIntervalSince1970: 0),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: 2,
      tomorrowLimit: 1
    )

    #expect(sections.today.map(\.id) == ["today-1", "today-2"])
    #expect(sections.tomorrow.map(\.id) == ["tomorrow-1"])
  }

  @Test func agendaSectionsKeepsAllDayEventsOutOfTimedLimits() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let timed = event(
      id: "timed",
      startDate: Date(timeIntervalSince1970: 20_000),
      endDate: Date(timeIntervalSince1970: 21_000)
    )
    let allDay = event(
      id: "all-day",
      startDate: Date(timeIntervalSince1970: 0),
      endDate: tomorrowStart,
      isAllDay: true
    )
    let multiDay = event(
      id: "multi-day",
      startDate: Date(timeIntervalSince1970: 0),
      endDate: dayAfterTomorrow,
      isAllDay: true
    )

    let sections = CalendarEventItem.agendaSections(
      from: [allDay, timed, multiDay],
      todayStart: Date(timeIntervalSince1970: 0),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: 1,
      tomorrowLimit: 1,
      todayAllDayLimit: 1,
      tomorrowAllDayLimit: 1
    )

    #expect(sections.today == [timed])
    #expect(sections.allDayToday.map(\.id) == ["all-day"])
    #expect(sections.allDayTomorrow == [multiDay])
  }

  @Test func agendaSectionsDropsEventsThatEndedAtMidnight() {
    let todayStart = Date(timeIntervalSince1970: 86_400)
    let tomorrowStart = todayStart.addingTimeInterval(86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let endedTimedEvent = event(
      id: "ended-timed-event",
      startDate: todayStart.addingTimeInterval(-60 * 60),
      endDate: todayStart
    )
    let activeTimedEvent = event(
      id: "active-timed-event",
      startDate: todayStart,
      endDate: todayStart.addingTimeInterval(60 * 60)
    )
    let endedYesterday = event(
      id: "ended-yesterday",
      startDate: todayStart.addingTimeInterval(-86_400),
      endDate: todayStart,
      isAllDay: true
    )
    let activeToday = event(
      id: "active-today",
      startDate: todayStart,
      endDate: tomorrowStart,
      isAllDay: true
    )

    let sections = CalendarEventItem.agendaSections(
      from: [endedTimedEvent, activeTimedEvent, endedYesterday, activeToday],
      todayStart: todayStart,
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow,
      todayLimit: 6,
      tomorrowLimit: 8
    )

    #expect(sections.today == [activeTimedEvent])
    #expect(sections.allDayToday == [activeToday])
  }

  @Test func malformedAllDayPreviewNeverEndsBeforeItStarts() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 86_400)
    let malformed = event(id: "malformed", startDate: start, endDate: start, isAllDay: true)

    #expect(EventPreviewPopover.inclusiveAllDayEnd(for: malformed, calendar: calendar) == start)
  }

  @Test func googleDateOnlyValuesResolveAsLocalGregorianDays() throws {
    let value = try JSONDecoder().decode(
      GoogleCalendarEventDate.self,
      from: Data(#"{"date":"2026-08-10"}"#.utf8)
    )
    let date = try #require(value.resolvedDate)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current

    #expect(value.isDateOnly)
    #expect(calendar.dateComponents([.year, .month, .day], from: date)
      == DateComponents(year: 2026, month: 8, day: 10))
  }

  @Test func googleEventsRequestSerializesTheLocalDayStartBoundary() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    let now = try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 8,
      day: 10,
      hour: 22,
      minute: 30
    )))
    let todayStart = calendar.startOfDay(for: now)
    let end = try #require(calendar.date(byAdding: .day, value: 2, to: todayStart))
    let url = try #require(CalendarService.eventsRequestURL(
      calendarID: "work@example.com",
      from: todayStart,
      to: end
    ))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
      item.value.map { (item.name, $0) }
    })
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]

    #expect(query["timeMin"] == formatter.string(from: todayStart))
    #expect(query["timeMin"] != formatter.string(from: now))
  }

  @Test func googleConferenceMoreEntryIsNotAJoinLink() throws {
    let event = try decodeGoogleEvent(conferenceEntryType: "more")
    let item = try #require(event.displayItem(
      accountID: UUID(),
      calendar: GoogleCalendarSource(id: "work", name: "Work", isPrimary: true, isEnabled: true),
      now: .distantPast
    ))

    #expect(item.meetingURL == nil)
    #expect(!item.hasMeetingLink)
    #expect(item.openURL == URL(string: "https://calendar.google.com/event"))
  }

  @Test func googleStructuredVideoEntryRemainsAJoinLink() throws {
    let event = try decodeGoogleEvent(conferenceEntryType: "video")
    let item = try #require(event.displayItem(
      accountID: UUID(),
      calendar: GoogleCalendarSource(id: "work", name: "Work", isPrimary: true, isEnabled: true),
      now: .distantPast
    ))

    #expect(item.meetingURL == URL(string: "https://calls.example.com/room/dayline"))
    #expect(item.hasMeetingLink)
    #expect(item.openURL == item.meetingURL)
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
        CalendarAgendaSourceBatch(provider: .google, events: [successfulEvent], warning: nil),
        CalendarAgendaSourceBatch(provider: .google, events: [], warning: "Work (other@example.com): Timed out")
      ],
      todayStart: Date(timeIntervalSince1970: 0),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )

    #expect(result.today == [successfulEvent])
    #expect(result.warnings == ["Work (other@example.com): Timed out"])
    #expect(result.shouldReplaceGoogleEvents)
  }

  @Test @MainActor func totalSourceFailurePreservesThePreviousAgenda() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)

    let result = StatusStore.assembleCalendarAgenda(
      sourceBatches: [
        CalendarAgendaSourceBatch(provider: .google, events: [], warning: "Work: Timed out"),
        CalendarAgendaSourceBatch(provider: .google, events: [], warning: "Personal: Offline")
      ],
      todayStart: Date(timeIntervalSince1970: 0),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )

    #expect(result.today.isEmpty)
    #expect(result.tomorrow.isEmpty)
    #expect(!result.shouldReplaceGoogleEvents)
  }

  @Test @MainActor func appleSuccessDoesNotReplaceFailedGoogleEvents() {
    let tomorrowStart = Date(timeIntervalSince1970: 86_400)
    let dayAfterTomorrow = tomorrowStart.addingTimeInterval(86_400)
    let appleEvent = event(
      id: "apple-event",
      startDate: Date(timeIntervalSince1970: 20_000),
      endDate: Date(timeIntervalSince1970: 21_000)
    )

    let result = StatusStore.assembleCalendarAgenda(
      sourceBatches: [
        CalendarAgendaSourceBatch(provider: .google, events: [], warning: "Work: Offline"),
        CalendarAgendaSourceBatch(provider: .apple, events: [appleEvent], warning: nil)
      ],
      todayStart: Date(timeIntervalSince1970: 0),
      tomorrowStart: tomorrowStart,
      dayAfterTomorrow: dayAfterTomorrow
    )

    #expect(!result.shouldReplaceGoogleEvents)
    #expect(result.shouldReplaceAppleEvents)
    #expect(result.googleSourceEvents.isEmpty)
    #expect(result.appleSourceEvents == [appleEvent])
  }

  private func event(
    id: String,
    startDate: Date,
    endDate: Date,
    source: String? = nil,
    deduplicationKey: String? = nil,
    sourceIDs: [String] = [],
    isAllDay: Bool = false
  ) -> CalendarEventItem {
    CalendarEventItem(
      id: id,
      title: id,
      startDate: startDate,
      endDate: endDate,
      location: nil,
      isAllDay: isAllDay,
      calendarURL: nil,
      openURL: nil,
      sourceCalendarNames: source.map { [$0] } ?? [],
      sourceIDs: sourceIDs,
      deduplicationKey: deduplicationKey
    )
  }

  private func decodeGoogleEvent(conferenceEntryType: String) throws -> GoogleCalendarEvent {
    try JSONDecoder().decode(
      GoogleCalendarEvent.self,
      from: Data(#"""
      {
        "id": "conference-event",
        "summary": "Conference event",
        "start": { "dateTime": "2026-08-10T10:00:00Z" },
        "end": { "dateTime": "2026-08-10T11:00:00Z" },
        "conferenceData": {
          "entryPoints": [
            {
              "entryPointType": "\#(conferenceEntryType)",
              "uri": "https://calls.example.com/room/dayline"
            }
          ]
        },
        "htmlLink": "https://calendar.google.com/event"
      }
      """#.utf8)
    )
  }
}

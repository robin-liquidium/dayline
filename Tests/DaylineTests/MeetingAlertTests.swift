import Foundation
import Testing
@testable import Dayline

struct MeetingAlertTests {
  @Test @MainActor func snoozeDurationUsesFiveMinutesAndClampsStoredValues() {
    #expect(StatusStore.defaultMeetingAlertSnoozeMinutes == 5)
    #expect(StatusStore.clampedMeetingAlertSnoozeMinutes(0) == 1)
    #expect(StatusStore.clampedMeetingAlertSnoozeMinutes(10) == 10)
    #expect(StatusStore.clampedMeetingAlertSnoozeMinutes(121) == 120)
  }

  @Test @MainActor func explicitSnoozeExtendsEligibilityWithoutOutlivingTheMeeting() {
    let start = Date(timeIntervalSince1970: 10_000)
    let event = CalendarEventItem(
      id: "meeting",
      title: "Meeting",
      startDate: start,
      endDate: start.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: nil,
      openURL: nil
    )

    #expect(StatusStore.meetingAlertEligibilityEnd(for: event, snoozedUntil: nil)
      == start.addingTimeInterval(10 * 60))
    #expect(StatusStore.meetingAlertEligibilityEnd(
      for: event,
      snoozedUntil: start.addingTimeInterval(-10 * 60)
    ) == start.addingTimeInterval(10 * 60))
    #expect(StatusStore.meetingAlertEligibilityEnd(
      for: event,
      snoozedUntil: start.addingTimeInterval(15 * 60)
    ) == start.addingTimeInterval(25 * 60))
    #expect(StatusStore.meetingAlertEligibilityEnd(
      for: event,
      snoozedUntil: start.addingTimeInterval(25 * 60)
    ) == event.endDate)
  }

  @Test @MainActor func linkOnlyAlertsRejectCalendarPagesAndKeepJoinLinks() {
    let now = Date(timeIntervalSince1970: 10_000)
    let calendarURL = URL(string: "https://calendar.google.com/event")!
    let eventWithoutMeetingLink = CalendarEventItem(
      id: "calendar-only",
      title: "Calendar only",
      startDate: now,
      endDate: now.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: calendarURL,
      openURL: calendarURL
    )
    let eventWithMeetingLink = CalendarEventItem(
      id: "linked",
      title: "Linked meeting",
      startDate: now,
      endDate: now.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: calendarURL,
      meetingURL: URL(string: "https://meet.google.com/dayline-test"),
      openURL: URL(string: "https://meet.google.com/dayline-test")
    )

    #expect(!eventWithoutMeetingLink.hasMeetingLink)
    #expect(eventWithMeetingLink.hasMeetingLink)
    #expect(!StatusStore.isMeetingAlertEligible(
      eventWithoutMeetingLink,
      at: now,
      lead: 0,
      requiresMeetingLink: true,
      snoozedUntil: nil,
      isDismissed: false
    ))
    #expect(StatusStore.isMeetingAlertEligible(
      eventWithMeetingLink,
      at: now,
      lead: 0,
      requiresMeetingLink: true,
      snoozedUntil: nil,
      isDismissed: false
    ))
    #expect(StatusStore.isMeetingAlertEligible(
      eventWithoutMeetingLink,
      at: now,
      lead: 0,
      requiresMeetingLink: false,
      snoozedUntil: nil,
      isDismissed: false
    ))
  }

  @Test func meetingLinkProvenanceRejectsGenericAndUnsafeURLs() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let restaurantURL = try #require(URL(string: "https://example.com/restaurant"))
    let arbitraryStructuredURL = try #require(URL(string: "https://calls.example.org/room/123"))
    let unsafeURL = try #require(URL(string: "file:///tmp/dayline"))
    let genericEvent = CalendarEventItem(
      id: "restaurant",
      title: "Lunch",
      startDate: now,
      endDate: now.addingTimeInterval(30 * 60),
      location: "Restaurant",
      calendarURL: nil,
      openURL: restaurantURL
    )
    let structuredEvent = CalendarEventItem(
      id: "structured",
      title: "Provider call",
      startDate: now,
      endDate: now.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: nil,
      meetingURL: arbitraryStructuredURL,
      openURL: arbitraryStructuredURL
    )
    let unsafeEvent = CalendarEventItem(
      id: "unsafe",
      title: "Unsafe",
      startDate: now,
      endDate: now.addingTimeInterval(30 * 60),
      location: nil,
      calendarURL: unsafeURL,
      meetingURL: unsafeURL,
      openURL: unsafeURL
    )

    #expect(!genericEvent.hasMeetingLink)
    #expect(CalendarEventItem.recognizedMeetingURL(restaurantURL) == nil)
    #expect(CalendarEventItem.recognizedMeetingURL(URL(string: "https://us02web.zoom.us/j/123")) != nil)
    #expect(structuredEvent.hasMeetingLink)
    #expect(structuredEvent.meetingURL == arbitraryStructuredURL)
    #expect(unsafeEvent.calendarURL == nil)
    #expect(unsafeEvent.meetingURL == nil)
    #expect(unsafeEvent.openURL == nil)
  }
}

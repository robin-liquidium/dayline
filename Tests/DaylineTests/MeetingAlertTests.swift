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
    #expect(structuredEvent.hasMeetingLink)
    #expect(structuredEvent.meetingURL == arbitraryStructuredURL)
    #expect(unsafeEvent.calendarURL == nil)
    #expect(unsafeEvent.meetingURL == nil)
    #expect(unsafeEvent.openURL == nil)
  }

  @Test func recognizedMeetingLinksRequireProviderJoinPaths() {
    let validURLs = [
      "https://meet.google.com/abc-defg-hij",
      "https://meet.google.com/lookup/team-room",
      "https://us02web.zoom.us/j/1234567890",
      "https://zoom.us/s/1234567890",
      "https://us02web.zoom.us/wc/join/1234567890",
      "https://us02web.zoom.us/wc/1234567890/join",
      "https://teams.microsoft.com/l/meetup-join/19%3ameeting_example%40thread.v2/0",
      "https://teams.microsoft.com/meet/123456789?p=secret",
      "https://teams.live.com/meet/123456789",
      "https://teams.microsoft.com/dl/launcher/launcher.html?TYPE=MEETUP-JOIN&URL=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fexample",
      "https://company.webex.com/meet/alex",
      "https://company.webex.com/join/123456789",
      "https://company.webex.com/company/j.php?MTID=example",
      "https://dayline.join.webex.com/guest/vod",
      "https://instant.webex.com/gen/v1/talk",
      "https://instant.webex.com/visit/dayline-room",
      "https://meet.jit.si/dayline-room",
      "https://whereby.com/dayline-room",
      "https://facetime.apple.com/join#v=1&p=example",
      "https://chime.aws/0123456789",
      "https://chime.aws/robin-dayline-room",
      "https://around.co/r/dayline-room"
    ]
    let nonMeetingURLs = [
      "https://meet.google.com/",
      "https://meet.google.com/about",
      "https://zoom.us/",
      "https://zoom.us/pricing",
      "https://zoom.us/wc/join/not-a-number",
      "https://zoom.us/wc/not-a-number/join",
      "https://zoom.us/wc/1234567890",
      "https://zoom.us/wc/1234567890/join/extra",
      "https://zoom.us/wc/join/1234567890/extra",
      "https://teams.microsoft.com/",
      "https://teams.microsoft.com/l/chat/123",
      "https://teams.microsoft.com/dl/launcher/launcher.html",
      "https://teams.microsoft.com/dl/launcher/launcher.html?type=meetup-join",
      "https://teams.microsoft.com/dl/launcher/launcher.html?url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fmeetup-join%2Fexample",
      "https://teams.microsoft.com/dl/launcher/launcher.html?type=chat&url=https%3A%2F%2Fteams.microsoft.com%2Fl%2Fchat%2Fexample",
      "https://teams.microsoft.com/dl/launcher?type=meetup-join&url=example",
      "https://company.webex.com/",
      "https://company.webex.com/company/j.php",
      "https://company.webex.com/products/meet",
      "https://company.webex.com/pricing/join-a-meeting",
      "https://dayline.join.webex.com/",
      "https://dayline.join.webex.com/pricing",
      "https://company.webex.com/guest/vod",
      "https://instant.webex.com/",
      "https://instant.webex.com/pricing",
      "https://instant.webex.com/gen/v1",
      "https://instant.webex.com/gen/v1/talk/extra",
      "https://instant.webex.com/visit",
      "https://instant.webex.com/visit/dayline-room/extra",
      "https://meet.jit.si/about",
      "https://whereby.com/pricing",
      "https://facetime.apple.com/",
      "https://chime.aws/pricing",
      "https://chime.aws/about",
      "https://chime.aws/signup",
      "https://chime.aws/download",
      "https://chime.aws/short-name",
      "https://chime.aws/dayline.meeting-room",
      "https://chime.aws/dayline-room/extra",
      "https://chime.aws/123456789012",
      "https://chime.aws/abcdefghijklmnopqrstuvwxyz1234567890",
      "https://around.co/pricing"
    ]

    #expect(validURLs.allSatisfy {
      CalendarEventItem.recognizedMeetingURL(URL(string: $0)) != nil
    })
    #expect(nonMeetingURLs.allSatisfy {
      CalendarEventItem.recognizedMeetingURL(URL(string: $0)) == nil
    })
  }
}

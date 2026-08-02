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
}

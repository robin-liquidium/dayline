import Foundation
import Testing
@testable import Dayline

@Suite("Linear issue create draft")
struct LinearIssueCreateDraftTests {
  @Test("Due dates are omitted until selected and encoded without a timestamp")
  func dueDateFormatting() {
    var draft = LinearIssueCreateDraft()
    #expect(draft.formattedDueDate == nil)

    let calendar = Calendar.current
    draft.dueDate = calendar.date(from: DateComponents(
      year: 2026,
      month: 7,
      day: 21,
      hour: 12
    ))

    #expect(draft.formattedDueDate == "2026-07-21")
  }

  @Test("Due dates use Gregorian calendar days in the current-style time zone")
  func dueDateFormattingAcrossTimeZones() throws {
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-07-21T23:30:00Z"))
    let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

    #expect(LinearIssueCreateDraft.formattedDueDate(instant, timeZone: berlin) == "2026-07-22")
    #expect(LinearIssueCreateDraft.formattedDueDate(instant, timeZone: losAngeles) == "2026-07-21")
  }
}

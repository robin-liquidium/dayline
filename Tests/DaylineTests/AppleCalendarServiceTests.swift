import Testing
@testable import Dayline

struct AppleCalendarServiceTests {
  @Test func unauthorizedAccessReturnsEmptyCalendarsAndEvents() {
    let service = AppleCalendarService()
    // The headless test runner holds no calendar permission, so both calls
    // must degrade to empty results instead of throwing or crashing.
    let sources = service.calendarSources()
    #expect(sources.isEmpty)
    let events = service.events(in: ["any"], from: .distantPast, to: .distantFuture)
    #expect(events.isEmpty)
  }

  @Test func accountIDIsStableForEventIdentity() {
    #expect(AppleCalendarService.accountID.uuidString.lowercased() == "a9c0ffee-0000-4000-8000-0000000000a9")
  }

  @Test func restoresExplicitlyDisabledCalendarsIncludingAllDisabled() {
    let discovered = [
      AppleCalendarSource(id: "work", title: "Work", sourceName: "iCloud", isEnabled: true),
      AppleCalendarSource(id: "home", title: "Home", sourceName: "iCloud", isEnabled: true)
    ]

    let restored = AppleCalendarSource.restoringSelections(
      in: discovered,
      from: ["work": false, "home": false]
    )

    #expect(restored.map(\.isEnabled) == [false, false])
  }

  @Test func newlyDiscoveredCalendarsStayEnabled() {
    let discovered = [
      AppleCalendarSource(id: "work", title: "Work", sourceName: "iCloud", isEnabled: true),
      AppleCalendarSource(id: "new", title: "New", sourceName: "iCloud", isEnabled: true)
    ]

    let restored = AppleCalendarSource.restoringSelections(
      in: discovered,
      from: ["work": false]
    )

    #expect(restored.map(\.isEnabled) == [false, true])
  }
}

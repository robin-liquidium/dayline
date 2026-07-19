import Foundation
import Testing
@testable import Dayline

struct GoogleAccountTests {
  @Test func catalogReconciliationPreservesSelectionsAndUsesGoogleDefaultsForNewCalendars() {
    let account = GoogleAccount(
      id: UUID(),
      providerAccountID: "robin@example.com",
      displayLabel: "robin@example.com",
      calendars: [
        GoogleCalendarSource(id: "primary", name: "Old name", isPrimary: true, isEnabled: false),
        GoogleCalendarSource(id: "removed", name: "Removed", isPrimary: false, isEnabled: true)
      ]
    )
    let discovered = [
      GoogleCalendarSource(id: "primary", name: "Renamed", isPrimary: true, isEnabled: true),
      GoogleCalendarSource(id: "new-selected", name: "New selected", isPrimary: false, isEnabled: true),
      GoogleCalendarSource(id: "new-hidden", name: "New unselected", isPrimary: false, isEnabled: false)
    ]

    let reconciled = account.reconcilingCalendars(discovered)

    #expect(reconciled.calendars.map(\.id) == ["primary", "new-selected", "new-hidden"])
    #expect(reconciled.calendars.first(where: { $0.id == "primary" })?.name == "Renamed")
    #expect(reconciled.calendars.first(where: { $0.id == "primary" })?.isEnabled == false)
    #expect(reconciled.calendars.first(where: { $0.id == "new-selected" })?.isEnabled == true)
    #expect(reconciled.calendars.first(where: { $0.id == "new-hidden" })?.isEnabled == false)
    #expect(!reconciled.calendars.contains(where: { $0.id == "removed" }))
  }
}

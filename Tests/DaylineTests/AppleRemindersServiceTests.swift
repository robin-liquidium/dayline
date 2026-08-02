import Testing
@testable import Dayline

@MainActor
struct AppleRemindersServiceTests {
  @Test func unauthorizedStoreDegradesWithoutReadingReminderData() async {
    let service = AppleRemindersService()
    guard !service.hasFullAccess else { return }

    #expect(service.reminderLists().isEmpty)
    #expect(service.defaultReminderListID() == nil)
    do {
      _ = try await service.fetchIncompleteReminders(in: ["missing"])
      Issue.record("Expected an access-denied failure")
    } catch AppleRemindersServiceError.accessDenied {
      // Expected: the test runner has no Reminders permission.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}

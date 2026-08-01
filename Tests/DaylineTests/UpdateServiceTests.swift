import Testing
@testable import Dayline

@MainActor
struct UpdateServiceTests {
  @Test func defaultMockUpdaterRemainsUnavailable() {
    let service = UpdateService(isMock: true, mockVersion: "9.9.9")

    #expect(!service.isUpdaterAvailable)
    #expect(!service.canCheckForUpdates)
    #expect(service.availableVersion == "9.9.9")
  }

  @Test func enabledInjectedUpdaterInvokesConfiguredCheckAction() {
    var invocationCount = 0
    let service = UpdateService(canCheckForUpdates: true) {
      invocationCount += 1
    }

    #expect(service.isUpdaterAvailable)
    service.checkForUpdates()
    #expect(invocationCount == 1)
  }

  @Test func disabledInjectedUpdaterDoesNotInvokeConfiguredCheckAction() {
    var invocationCount = 0
    let service = UpdateService(canCheckForUpdates: false) {
      invocationCount += 1
    }

    #expect(service.isUpdaterAvailable)
    service.checkForUpdates()
    #expect(invocationCount == 0)
  }
}

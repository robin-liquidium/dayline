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

  @Test func enabledInjectedUpdaterActivatesThenChecksOnNextMainLoopTurn() async {
    var actions: [String] = []
    var service: UpdateService?

    await withCheckedContinuation { continuation in
      service = UpdateService(
        canCheckForUpdates: true,
        activateApplicationAction: {
          actions.append("activate")
        },
        checkForUpdatesAction: {
          actions.append("check")
          continuation.resume()
        }
      )

      #expect(service?.isUpdaterAvailable == true)
      service?.checkForUpdates()
      #expect(actions.isEmpty)
    }

    #expect(actions == ["activate", "check"])
    _ = service
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

  @Test func finishingSessionClearsReminderWithoutPendingInstall() {
    let service = UpdateService(isMock: true, mockVersion: "9.9.9")

    service.standardUserDriverWillFinishUpdateSession()

    #expect(service.availableVersion == nil)
  }

  @Test func finishingSessionKeepsReminderForPendingInstallOnQuit() {
    let service = UpdateService(isMock: true)

    service.recordPendingInstallOnQuit(version: "9.9.9")
    service.standardUserDriverWillFinishUpdateSession()

    #expect(service.availableVersion == "9.9.9")
  }

  @Test func canceledPendingInstallNoLongerKeepsReminder() {
    let service = UpdateService(isMock: true)
    service.recordPendingInstallOnQuit(version: "9.9.9")

    service.clearPendingInstallOnQuit(version: "9.9.9")
    service.standardUserDriverWillFinishUpdateSession()

    #expect(service.availableVersion == nil)
  }

  @Test func cancelingAnotherVersionDoesNotClearPendingInstall() {
    let service = UpdateService(isMock: true)
    service.recordPendingInstallOnQuit(version: "9.9.9")

    service.clearPendingInstallOnQuit(version: "9.9.8")
    service.standardUserDriverWillFinishUpdateSession()

    #expect(service.availableVersion == "9.9.9")
  }
}

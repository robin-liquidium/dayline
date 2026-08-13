import Dispatch
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

  @Test(.timeLimit(.minutes(1)))
  func enabledInjectedUpdaterActivatesThenChecksOnNextMainLoopTurn() async {
    var actions: [String] = []
    let (checkEvents, checkEventContinuation) = AsyncStream<Void>.makeStream()
    let service = UpdateService(
      canCheckForUpdates: true,
      activateApplicationAction: {
        actions.append("activate")
      },
      checkForUpdatesAction: {
        actions.append("check")
        checkEventContinuation.yield()
      }
    )

    #expect(service.isUpdaterAvailable)
    service.checkForUpdates()
    #expect(actions.isEmpty)

    let receivedCheck = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        var iterator = checkEvents.makeAsyncIterator()
        return await iterator.next() != nil
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(1))
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      checkEventContinuation.finish()
      return result
    }

    #expect(receivedCheck)
    #expect(actions == ["activate", "check"])
  }

  @Test(.timeLimit(.minutes(1)))
  func disabledInjectedUpdaterDoesNotInvokeConfiguredCheckAction() async {
    var invocationCount = 0
    let service = UpdateService(canCheckForUpdates: false) {
      invocationCount += 1
    }

    #expect(service.isUpdaterAvailable)
    service.checkForUpdates()
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
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

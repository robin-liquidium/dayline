import Combine
import Foundation
@preconcurrency import Sparkle

/// Owns Sparkle's updater and exposes the small amount of state Dayline's UI needs.
@MainActor
final class UpdateService: NSObject, ObservableObject {
  /// Version currently offered to the user, or `nil` when Dayline is current.
  @Published private(set) var availableVersion: String?

  /// Whether Sparkle downloads updates in the background and installs them on quit.
  @Published private(set) var automaticallyInstallsUpdates = true

  /// Whether Sparkle can currently begin or focus a user-initiated update check.
  @Published private(set) var canCheckForUpdates = false

  /// Whether this app bundle includes the configuration required to run Sparkle.
  var isUpdaterAvailable: Bool {
    updaterController != nil
  }

  private let isMock: Bool
  private var updaterController: SPUStandardUpdaterController?
  private var automaticallyDownloadsObservation: NSKeyValueObservation?
  private var canCheckForUpdatesObservation: NSKeyValueObservation?
  private var immediateInstallationHandler: (() -> Void)?

  /// Creates either the production Sparkle updater or the isolated mock used for UI testing.
  init(isMock: Bool, mockVersion: String? = nil) {
    self.isMock = isMock
    availableVersion = mockVersion
    super.init()

    guard
      !isMock,
      Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String,
      Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
    else {
      return
    }

    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: self
    )
    updaterController = controller
    automaticallyInstallsUpdates = controller.updater.automaticallyDownloadsUpdates
    canCheckForUpdates = controller.updater.canCheckForUpdates
    automaticallyDownloadsObservation = controller.updater.observe(
      \.automaticallyDownloadsUpdates,
      options: [.new]
    ) { [weak self] _, change in
      guard let isEnabled = change.newValue else {
        return
      }
      Task { @MainActor [weak self] in
        self?.automaticallyInstallsUpdates = isEnabled
      }
    }
    canCheckForUpdatesObservation = controller.updater.observe(
      \.canCheckForUpdates,
      options: [.new]
    ) { [weak self] _, change in
      guard let canCheck = change.newValue else {
        return
      }
      Task { @MainActor [weak self] in
        self?.canCheckForUpdates = canCheck
      }
    }
  }

  /// Persists the user's automatic-install preference in Sparkle's own defaults domain.
  func setAutomaticallyInstallsUpdates(_ isEnabled: Bool) {
    automaticallyInstallsUpdates = isEnabled
    updaterController?.updater.automaticallyDownloadsUpdates = isEnabled
  }

  /// Installs a staged update immediately, or brings Sparkle's native update UI forward.
  func performUpdate() {
    if let immediateInstallationHandler {
      immediateInstallationHandler()
    } else if !isMock {
      updaterController?.updater.checkForUpdates()
    }
  }

  /// Runs a user-initiated update check, letting Sparkle present its standard UI.
  func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
  }
}

extension UpdateService: @preconcurrency SPUStandardUserDriverDelegate {
  /// Dayline uses its menu-bar footer as the non-intrusive scheduled update reminder.
  var supportsGentleScheduledUpdateReminders: Bool {
    true
  }

  /// Scheduled checks update the footer instead of interrupting whichever app is active.
  func standardUserDriverShouldHandleShowingScheduledUpdate(
    _ update: SUAppcastItem,
    andInImmediateFocus immediateFocus: Bool
  ) -> Bool {
    false
  }

  /// Records the update Sparkle found when Dayline is responsible for the reminder UI.
  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    guard !handleShowingUpdate else {
      return
    }
    availableVersion = update.displayVersionString
  }

  /// Removes a reminder after Sparkle finishes a dismissed, skipped, or failed session.
  func standardUserDriverWillFinishUpdateSession() {
    guard immediateInstallationHandler == nil else {
      return
    }
    availableVersion = nil
  }
}

extension UpdateService: SPUUpdaterDelegate {
  /// Retains Sparkle's supported install-and-relaunch operation once a download is staged.
  func updater(
    _ updater: SPUUpdater,
    willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
  ) -> Bool {
    availableVersion = item.displayVersionString
    immediateInstallationHandler = immediateInstallHandler
    return true
  }
}

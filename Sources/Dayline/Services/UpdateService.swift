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
    updaterController != nil || injectedCheckForUpdatesAction != nil
  }

  private var updaterController: SPUStandardUpdaterController?
  private var injectedCheckForUpdatesAction: (() -> Void)?
  private var automaticallyDownloadsObservation: NSKeyValueObservation?
  private var canCheckForUpdatesObservation: NSKeyValueObservation?
  private var pendingInstallOnQuitVersion: String?

  /// Creates either the production Sparkle updater or the isolated mock used for UI testing.
  init(isMock: Bool, mockVersion: String? = nil) {
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

  /// Creates an isolated updater action for unit tests without starting Sparkle.
  init(canCheckForUpdates: Bool, checkForUpdatesAction: @escaping () -> Void) {
    self.canCheckForUpdates = canCheckForUpdates
    injectedCheckForUpdatesAction = checkForUpdatesAction
    super.init()
  }

  /// Persists the user's automatic-install preference in Sparkle's own defaults domain.
  func setAutomaticallyInstallsUpdates(_ isEnabled: Bool) {
    automaticallyInstallsUpdates = isEnabled
    updaterController?.updater.automaticallyDownloadsUpdates = isEnabled
  }

  /// Runs a user-initiated update check, letting Sparkle present its standard UI.
  func checkForUpdates() {
    guard canCheckForUpdates else {
      return
    }
    if let injectedCheckForUpdatesAction {
      injectedCheckForUpdatesAction()
      return
    }
    updaterController?.checkForUpdates(nil)
  }

  /// Keeps the footer reminder for an update Sparkle has staged to install on quit.
  func recordPendingInstallOnQuit(version: String) {
    pendingInstallOnQuitVersion = version
    availableVersion = version
  }

  /// Removes staged state when Sparkle cancels that installation after a user choice.
  func clearPendingInstallOnQuit(version: String) {
    guard pendingInstallOnQuitVersion == version else {
      return
    }
    pendingInstallOnQuitVersion = nil
    availableVersion = nil
  }
}

extension UpdateService: SPUUpdaterDelegate {
  /// Keeps Dayline's reminder visible while leaving installation and relaunch UI to Sparkle.
  func updater(
    _ updater: SPUUpdater,
    willInstallUpdateOnQuit item: SUAppcastItem,
    immediateInstallationBlock _: @escaping () -> Void
  ) -> Bool {
    recordPendingInstallOnQuit(version: item.displayVersionString)
    return false
  }

  func updater(
    _: SPUUpdater,
    userDidMake choice: SPUUserUpdateChoice,
    forUpdate item: SUAppcastItem,
    state _: SPUUserUpdateState
  ) {
    guard choice == .skip else {
      return
    }
    clearPendingInstallOnQuit(version: item.displayVersionString)
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

  /// Finishes footer state by keeping only an update still staged to install on quit.
  func standardUserDriverWillFinishUpdateSession() {
    availableVersion = pendingInstallOnQuitVersion
  }
}

import Foundation
import ServiceManagement

/// Errors produced while changing Dayline's login item registration.
enum LaunchAtLoginServiceError: LocalizedError {
  /// macOS has the item registered, but the user still needs to approve it.
  case requiresApproval

  /// Human-readable recovery text for the settings form.
  var errorDescription: String? {
    switch self {
    case .requiresApproval:
      "Approve Dayline in System Settings > General > Login Items."
    }
  }
}

/// Reads and updates Dayline's macOS launch-at-login registration.
struct LaunchAtLoginService {
  /// Whether macOS currently reports Dayline as an enabled login item.
  var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Current macOS login item status for Dayline.
  var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  /// Enables or disables Dayline as a login item.
  func setEnabled(_ isEnabled: Bool) throws {
    if isEnabled {
      guard status != .enabled else {
        return
      }
      guard status != .requiresApproval else {
        throw LaunchAtLoginServiceError.requiresApproval
      }
      try SMAppService.mainApp.register()
      guard status != .requiresApproval else {
        throw LaunchAtLoginServiceError.requiresApproval
      }
    } else {
      guard status != .notRegistered else {
        return
      }
      try SMAppService.mainApp.unregister()
    }
  }
}

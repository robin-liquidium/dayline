import AppKit

/// Brings the SwiftUI Settings scene forward for the menu-bar accessory app.
enum SettingsWindowPresenter {
  /// Activates the app and orders the Settings window to the front after SwiftUI creates it.
  static func bringSettingsToFront() {
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      orderSettingsWindowFront()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.activate(ignoringOtherApps: true)
      orderSettingsWindowFront()
    }
  }

  /// Finds the settings window SwiftUI created and makes it key/frontmost.
  private static func orderSettingsWindowFront() {
    let settingsWindow = NSApp.windows.first { window in
      window.title == "General" || window.identifier?.rawValue.contains("Settings") == true
    }

    settingsWindow?.makeKeyAndOrderFront(nil)
    settingsWindow?.orderFrontRegardless()
  }
}

import AppKit
import SwiftUI

/// Handles process-level macOS behavior for the menu-bar-only app.
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Configures the app as an accessory process so it intentionally has no Dock icon.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

/// The application entry point that owns the shared status store and scenes.
@main
struct StatusWidgetApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store = StatusStore()

  /// Declares the menu bar extra and native settings window.
  var body: some Scene {
    MenuBarExtra {
      StatusMenuView()
        .environmentObject(store)
    } label: {
      Label("Today", systemImage: store.menuBarSystemImage)
        .accessibilityLabel("StatusWidget")
        .accessibilityIdentifier("status.menuBarItem")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environmentObject(store)
    }
  }
}

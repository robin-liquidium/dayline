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
struct DaylineApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store = StatusStore()

  /// Declares the menu bar extra, editor windows, and native settings window.
  var body: some Scene {
    MenuBarExtra {
      StatusMenuView()
        .environmentObject(store)
    } label: {
      if let menuBarEventText = store.menuBarEventText {
        Text(menuBarEventText)
          .lineLimit(1)
          .accessibilityLabel(store.menuBarAccessibilityLabel)
          .accessibilityIdentifier("dayline.menuBarItem")
      } else {
        Label("Today", systemImage: store.menuBarSystemImage)
          .accessibilityLabel(store.menuBarAccessibilityLabel)
          .accessibilityIdentifier("dayline.menuBarItem")
      }
    }
    .menuBarExtraStyle(.window)

    WindowGroup("Note", for: NoteEditorRequest.self) { $request in
      NoteEditorView(request: request ?? .new)
        .environmentObject(store)
    }
    .defaultSize(width: 500, height: 420)

    Window("New Linear Issue", id: "linearIssueCreator") {
      LinearIssueEditorView()
        .environmentObject(store)
    }
    .defaultSize(width: 620, height: 600)

    Settings {
      SettingsView()
        .environmentObject(store)
    }
  }
}

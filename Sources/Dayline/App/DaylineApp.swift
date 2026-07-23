import AppKit
import SwiftUI

/// Handles process-level macOS behavior for the menu-bar-only app.
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Configures the app as an accessory process so it intentionally has no Dock icon.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    DockIconVisibilityController.shared.start()
  }

  /// Forwards OAuth redirect URLs from the system browser back into the auth flow.
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      _ = BrowserOAuthCoordinator.shared.handleOpenURL(url)
    }
  }
}

/// The application entry point that owns the shared status store and scenes.
@main
struct DaylineApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store: StatusStore
  @StateObject private var updateService: UpdateService
  private let appDisplayName: String

  init() {
    let isMock = ProcessInfo.processInfo.arguments.contains("--mock")
    let mockData = isMock ? MockData.make() : nil
    _store = StateObject(wrappedValue: StatusStore(mockData: mockData))
    _updateService = StateObject(wrappedValue: UpdateService(
      isMock: isMock,
      mockVersion: mockData?.availableUpdateVersion
    ))
    appDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Dayline"
  }

  /// Declares the menu bar extra, editor windows, and native settings window.
  var body: some Scene {
    MenuBarExtra {
      StatusMenuView()
        .environmentObject(store)
        .environmentObject(updateService)
    } label: {
      MenuBarLabelView()
        .environmentObject(store)
    }
    .menuBarExtraStyle(.window)

    WindowGroup("Note", for: NoteEditorRequest.self) { $request in
      NoteEditorView(request: request ?? .new)
        .environmentObject(store)
    }
    .defaultSize(width: 500, height: 420)
    // OAuth redirects use the dayline:// scheme; do not let them open editor windows.
    .handlesExternalEvents(matching: [])

    Window("New Linear Issue", id: "linearIssueCreator") {
      LinearIssueEditorView()
        .environmentObject(store)
    }
    .defaultSize(width: 620, height: 600)
    .handlesExternalEvents(matching: [])

    Window("\(appDisplayName) Settings", id: "settings") {
      SettingsView()
        .environmentObject(store)
        .environmentObject(updateService)
    }
    .defaultSize(width: 800, height: 720)
    .windowResizability(.contentMinSize)
    .handlesExternalEvents(matching: [])
  }
}

/// Always-mounted menu bar label that also handles app-level window requests.
private struct MenuBarLabelView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Group {
      if let menuBarEventText = store.menuBarEventText {
        Text(menuBarEventText)
          .lineLimit(1)
      } else {
        Label("Today", systemImage: store.menuBarSystemImage)
      }
    }
    .accessibilityLabel(store.menuBarAccessibilityLabel)
    .accessibilityIdentifier("dayline.menuBarItem")
    .onChange(of: store.settingsPresentationRequestID) {
      openWindow(id: "settings")
      SettingsWindowPresenter.bringSettingsToFront()
    }
    .onChange(of: store.noteCreationRequestID) {
      openWindow(value: NoteEditorRequest.new)
      NoteEditorWindowPresenter.bringNoteWindowToFront()
    }
    .onChange(of: store.linearIssueCreationRequestID) {
      openWindow(id: "linearIssueCreator")
      LinearIssueEditorWindowPresenter.bringIssueWindowToFront()
    }
    .onChange(of: store.meetingAlertEvent, initial: true) {
      if let event = store.meetingAlertEvent {
        MeetingAlertWindowController.shared.show(
          event: event,
          onJoin: { store.joinMeetingAlert() },
          onDismiss: { store.dismissMeetingAlert() }
        )
      } else {
        MeetingAlertWindowController.shared.dismiss()
      }
    }
  }
}

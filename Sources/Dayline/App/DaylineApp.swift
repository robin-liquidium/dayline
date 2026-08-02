import AppKit
import SwiftUI

/// Handles process-level macOS behavior for the menu-bar-only app.
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Configures the app as an accessory process so it intentionally has no Dock icon.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    DockIconVisibilityController.shared.start()
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    DaylineDiagnostics.record("App launched version \(version) build \(build)", category: .lifecycle)
  }

  func applicationWillTerminate(_ notification: Notification) {
    DaylineDiagnostics.record("App will terminate normally", category: .lifecycle)
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
    let arguments = ProcessInfo.processInfo.arguments
    let isMockBundle = Bundle.main.bundleIdentifier == "build.local.DaylineMock"
    let isMock = arguments.contains("--mock") || isMockBundle
    if isMock,
       arguments.contains("--ui-testing"),
       let bundleIdentifier = Bundle.main.bundleIdentifier,
       isMockBundle {
      UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
    }
    let mockIssueSources = arguments
      .first(where: { $0.hasPrefix("--mock-issue-providers=") })
      .map { argument in
        Set(argument
          .split(separator: "=", maxSplits: 1)
          .last?
          .split(separator: ",")
          .compactMap { IssueSource(rawValue: String($0)) } ?? [])
      }
      ?? Set(IssueSource.allCases)
    let mockData = isMock ? MockData.make(issueSources: mockIssueSources) : nil
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
    .commands {
      NoteFormattingCommands()
    }

    Window("New Linear Issue", id: "linearIssueCreator") {
      LinearIssueEditorView()
        .environmentObject(store)
    }
    .defaultSize(width: 620, height: 600)
    .handlesExternalEvents(matching: [])

    Window("New GitHub Issue", id: "githubIssueCreator") {
      GitHubIssueEditorView()
        .environmentObject(store)
    }
    .defaultSize(width: 620, height: 520)
    .handlesExternalEvents(matching: [])

    Window("New Apple Reminder", id: "appleReminderCreator") {
      AppleReminderEditorView()
        .environmentObject(store)
    }
    .defaultSize(width: 580, height: 540)
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
    .onChange(of: store.githubIssueCreationRequestID) {
      openWindow(id: "githubIssueCreator")
      GitHubIssueEditorWindowPresenter.bringIssueWindowToFront()
    }
    .onChange(of: store.appleReminderCreationRequestID) {
      openWindow(id: "appleReminderCreator")
      AppleReminderEditorWindowPresenter.bringReminderWindowToFront()
    }
    .onChange(of: store.meetingAlertEvent, initial: true) {
      if let event = store.meetingAlertEvent {
        MeetingAlertWindowController.shared.show(
          event: event,
          snoozeMinutes: store.meetingAlertSnoozeMinutes,
          onJoin: { store.joinMeetingAlert() },
          onSnooze: { store.snoozeMeetingAlert() },
          onDismiss: { store.dismissMeetingAlert() }
        )
      } else {
        MeetingAlertWindowController.shared.dismiss()
      }
    }
  }
}

import AppKit
import SwiftUI

/// Presents a borderless full-screen meeting alert above all other content,
/// including other apps' full-screen Spaces.
@MainActor
final class MeetingAlertWindowController {
  static let shared = MeetingAlertWindowController()

  private var panel: AlertPanel?

  private init() {}

  /// A non-activating panel can sit on top of another app's full-screen Space.
  /// Activating Dayline instead would make macOS switch away to a Space where
  /// Dayline has windows, so the alert never appeared over full-screen apps.
  private final class AlertPanel: NSPanel {
    /// Borderless panels reject key status by default; the alert needs it for Esc/Return.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
  }

  /// Shows the alert for a meeting, updating the content in place when already visible.
  func show(
    event: CalendarEventItem,
    snoozeMinutes: Int,
    onJoin: @escaping () -> Void,
    onSnooze: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    guard let screen = Self.activeScreen else { return }
    let rootView = MeetingAlertView(
      event: event,
      snoozeMinutes: snoozeMinutes,
      onJoin: onJoin,
      onSnooze: onSnooze,
      onDismiss: onDismiss
    )

    let alertPanel: AlertPanel
    if let panel, let hostingView = panel.contentView as? NSHostingView<MeetingAlertView> {
      hostingView.rootView = rootView
      alertPanel = panel
    } else {
      alertPanel = AlertPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
      )
      alertPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      alertPanel.hidesOnDeactivate = false
      alertPanel.isReleasedWhenClosed = false
      alertPanel.isOpaque = false
      alertPanel.backgroundColor = .clear
      alertPanel.hasShadow = false
      alertPanel.contentView = NSHostingView(rootView: rootView)
      panel = alertPanel
    }

    // Set last: NSPanel's floating-panel defaults would otherwise lower it.
    alertPanel.level = .screenSaver
    alertPanel.setFrame(screen.frame, display: true)
    alertPanel.orderFrontRegardless()
    alertPanel.makeKey()
    DaylineDiagnostics.record("Meeting alert window appeared", category: .lifecycle)
  }

  /// Hides the alert while retaining its SwiftUI hierarchy for safe reuse.
  func dismiss() {
    guard let panel, panel.isVisible else {
      return
    }
    panel.orderOut(nil)
    DaylineDiagnostics.record("Meeting alert window disappeared", category: .lifecycle)
  }

  /// Display with keyboard focus, where the user is working.
  private static var activeScreen: NSScreen? {
    NSScreen.main ?? NSScreen.screens.first
  }
}

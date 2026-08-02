import AppKit
import SwiftUI

/// Presents a borderless full-screen meeting alert above all other content.
@MainActor
final class MeetingAlertWindowController {
  static let shared = MeetingAlertWindowController()

  private var window: NSWindow?

  private init() {}

  /// Borderless windows reject key status by default; the alert needs it for Esc/Return.
  private final class AlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
  }

  /// Shows the alert for a meeting, updating the content in place when already visible.
  func show(
    event: CalendarEventItem,
    snoozeMinutes: Int,
    onJoin: @escaping () -> Void,
    onSnooze: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let rootView = MeetingAlertView(
      event: event,
      snoozeMinutes: snoozeMinutes,
      onJoin: onJoin,
      onSnooze: onSnooze,
      onDismiss: onDismiss
    )

    if let window, let hostingView = window.contentView as? NSHostingView<MeetingAlertView> {
      hostingView.rootView = rootView
      window.setFrame(screen.frame, display: true)
      window.makeKeyAndOrderFront(nil)
      NSApp.activate()
      DaylineDiagnostics.record("Meeting alert window appeared", category: .lifecycle)
      return
    }

    let alertWindow = AlertWindow(
      contentRect: screen.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    alertWindow.level = .screenSaver
    alertWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    alertWindow.isOpaque = false
    alertWindow.backgroundColor = .clear
    alertWindow.hasShadow = false
    alertWindow.contentView = NSHostingView(rootView: rootView)
    alertWindow.makeKeyAndOrderFront(nil)
    NSApp.activate()
    window = alertWindow
    DaylineDiagnostics.record("Meeting alert window appeared", category: .lifecycle)
  }

  /// Hides the alert while retaining its SwiftUI hierarchy for safe reuse.
  func dismiss() {
    guard let window, window.isVisible else {
      return
    }
    window.orderOut(nil)
    DaylineDiagnostics.record("Meeting alert window disappeared", category: .lifecycle)
  }
}

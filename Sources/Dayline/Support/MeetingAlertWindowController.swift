import AppKit
import SwiftUI

/// Presents a borderless full-screen meeting alert above all other content.
final class MeetingAlertWindowController {
  static let shared = MeetingAlertWindowController()

  private var window: NSWindow?

  private init() {}

  /// Borderless windows reject key status by default; the alert needs it for Esc/Return.
  private final class AlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
  }

  /// Shows the alert for a meeting, updating the content in place when already visible.
  func show(event: CalendarEventItem, onJoin: @escaping () -> Void, onDismiss: @escaping () -> Void) {
    let rootView = MeetingAlertView(event: event, onJoin: onJoin, onDismiss: onDismiss)

    if let window, let hostingView = window.contentView as? NSHostingView<MeetingAlertView> {
      hostingView.rootView = rootView
      return
    }

    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
    NSApp.activate(ignoringOtherApps: true)
    window = alertWindow
  }

  /// Closes the alert window if it is visible.
  func dismiss() {
    window?.close()
    window = nil
  }
}

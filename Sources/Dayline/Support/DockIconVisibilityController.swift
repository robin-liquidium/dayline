import AppKit

/// Shows the app in the Dock and Cmd+Tab switcher while any Dayline window is open,
/// and returns to menu-bar-only accessory mode once the last window closes.
final class DockIconVisibilityController {
  static let shared = DockIconVisibilityController()

  private var openWindows = Set<NSWindow>()

  private init() {}

  /// Starts observing window lifecycle notifications for the lifetime of the app.
  func start() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: nil
    )
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, Self.isDaylineWindow(window) else { return }
    openWindows.insert(window)
    updateActivationPolicy()
  }

  @objc private func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if openWindows.remove(window) != nil {
      updateActivationPolicy()
    }
  }

  private func updateActivationPolicy() {
    NSApp.setActivationPolicy(openWindows.isEmpty ? .accessory : .regular)
  }

  /// Matches the same window titles the window presenters use to find SwiftUI scenes.
  private static func isDaylineWindow(_ window: NSWindow) -> Bool {
    if ["Note", "New Note", "New Linear Issue", "General"].contains(window.title) {
      return true
    }
    if window.title.hasSuffix("Settings") {
      return true
    }
    return window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
  }
}

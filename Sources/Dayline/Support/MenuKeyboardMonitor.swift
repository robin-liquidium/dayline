import AppKit
import Combine

/// Captures menu-window shortcuts without forcing SwiftUI's root view into the text-input focus system.
@MainActor
final class MenuKeyboardMonitor: ObservableObject {
  private var monitor: Any?
  private weak var window: NSWindow?
  private var onKeyPress: ((String) -> Bool)?

  /// Whether the key monitor is currently installed; exposed for tests.
  var isMonitoring: Bool {
    monitor != nil
  }

  /// Starts one local key monitor while the menu-bar window is visible.
  func start(in window: NSWindow, onKeyPress: @escaping (String) -> Bool) {
    self.window = window
    self.onKeyPress = onKeyPress
    installMonitorIfNeeded()
  }

  /// Reinstalls the monitor for the previously reported window.
  ///
  /// SwiftUI reuses the cached menu panel across opens, so the window reader
  /// does not re-fire; without this the monitor is never restarted after the
  /// first dismissal and menu shortcuts stay dead until the app relaunches.
  func resume() {
    guard window != nil, onKeyPress != nil else {
      return
    }
    installMonitorIfNeeded()
  }

  private func installMonitorIfNeeded() {
    guard monitor == nil else {
      return
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self,
            Self.shouldHandleKeyDown(
              menuWindow: self.window,
              modifierFlags: event.modifierFlags,
              isEditingText: Self.isEditingText
            ),
            let characters = event.charactersIgnoringModifiers,
            self.onKeyPress?(characters) == true else {
        return event
      }
      return nil
    }
    DaylineDiagnostics.record("Menu keyboard monitor started", category: .menuBar)
  }

  /// Removes the monitor as soon as the menu-bar window is dismissed.
  func stop() {
    guard let monitor else {
      return
    }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
    DaylineDiagnostics.record("Menu keyboard monitor stopped", category: .menuBar)
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  /// Reasserts key status on the menu window.
  ///
  /// MenuBarExtra can recreate its panel while a stale, hidden panel keeps key
  /// status, which routes key events away from the visible menu.
  func makeWindowKeyIfVisible() {
    guard let window, window.isVisible, NSApp.keyWindow !== window else {
      return
    }
    window.makeKey()
  }

  /// Decides whether a key event should be treated as a menu shortcut.
  ///
  /// Gating on event-window identity breaks when a stale panel is key, so this
  /// only requires the menu window to be visible; the monitor is installed
  /// exclusively while the menu is open.
  static func shouldHandleKeyDown(
    menuWindow: NSWindow?,
    modifierFlags: NSEvent.ModifierFlags,
    isEditingText: Bool
  ) -> Bool {
    guard let menuWindow, menuWindow.isVisible else {
      return false
    }
    let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
    guard modifierFlags.intersection(disallowedModifiers).isEmpty else {
      return false
    }
    return !isEditingText
  }

  private static var isEditingText: Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else {
      return false
    }
    return responder is NSTextView || responder is NSTextField
  }
}

import AppKit
import Combine

/// Captures menu-window shortcuts without forcing SwiftUI's root view into the text-input focus system.
@MainActor
final class MenuKeyboardMonitor: ObservableObject {
  private var monitor: Any?
  private weak var window: NSWindow?
  private var onKeyPress: ((String) -> Bool)?

  /// Starts one local key monitor while the menu-bar window is visible.
  func start(in window: NSWindow, onKeyPress: @escaping (String) -> Bool) {
    self.window = window
    self.onKeyPress = onKeyPress
    guard monitor == nil else {
      return
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
      guard let self,
            event.window === self.window,
            event.modifierFlags.intersection(disallowedModifiers).isEmpty,
            !Self.isEditingText,
            let characters = event.charactersIgnoringModifiers,
            self.onKeyPress?(characters) == true else {
        return event
      }
      return nil
    }
  }

  /// Removes the monitor as soon as the menu-bar window is dismissed.
  func stop() {
    guard let monitor else {
      return
    }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
    window = nil
    onKeyPress = nil
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  private static var isEditingText: Bool {
    guard let responder = NSApp.keyWindow?.firstResponder else {
      return false
    }
    return responder is NSTextView || responder is NSTextField
  }
}

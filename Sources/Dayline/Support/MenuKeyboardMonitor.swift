import AppKit
import Combine

/// Captures menu-window shortcuts without forcing SwiftUI's root view into the text-input focus system.
@MainActor
final class MenuKeyboardMonitor: ObservableObject {
  private var monitor: Any?

  /// Starts one local key monitor while the menu-bar window is visible.
  func start(onKeyPress: @escaping (String) -> Bool) {
    guard monitor == nil else {
      return
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .function]
      guard event.modifierFlags.intersection(disallowedModifiers).isEmpty,
            !Self.isEditingText,
            let characters = event.charactersIgnoringModifiers,
            onKeyPress(characters) else {
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

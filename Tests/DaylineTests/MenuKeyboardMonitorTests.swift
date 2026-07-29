import AppKit
import Testing
@testable import Dayline

@MainActor
struct MenuKeyboardMonitorTests {
  private func makeWindow(visible: Bool) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    if visible {
      window.orderFront(nil)
    }
    return window
  }

  @Test func handlesPlainKeyWhenMenuWindowIsVisible() {
    let window = makeWindow(visible: true)
    defer { window.orderOut(nil) }

    #expect(window.isVisible)
    #expect(
      MenuKeyboardMonitor.shouldHandleKeyDown(
        menuWindow: window,
        modifierFlags: [],
        isEditingText: false
      )
    )
  }

  @Test func ignoresKeyWhenMenuWindowIsHidden() {
    let window = makeWindow(visible: false)

    #expect(!window.isVisible)
    #expect(
      !MenuKeyboardMonitor.shouldHandleKeyDown(
        menuWindow: window,
        modifierFlags: [],
        isEditingText: false
      )
    )
  }

  @Test func ignoresKeyWhenMenuWindowIsGone() {
    #expect(
      !MenuKeyboardMonitor.shouldHandleKeyDown(
        menuWindow: nil,
        modifierFlags: [],
        isEditingText: false
      )
    )
  }

  @Test func ignoresKeyWithDisallowedModifiers() {
    let window = makeWindow(visible: true)
    defer { window.orderOut(nil) }

    for flags: NSEvent.ModifierFlags in [.command, .control, .option, .function, [.command, .shift]] {
      #expect(
        !MenuKeyboardMonitor.shouldHandleKeyDown(
          menuWindow: window,
          modifierFlags: flags,
          isEditingText: false
        )
      )
    }
  }

  @Test func allowsShiftForUppercaseShortcuts() {
    let window = makeWindow(visible: true)
    defer { window.orderOut(nil) }

    #expect(
      MenuKeyboardMonitor.shouldHandleKeyDown(
        menuWindow: window,
        modifierFlags: [.shift],
        isEditingText: false
      )
    )
  }

  @Test func ignoresKeyWhileEditingText() {
    let window = makeWindow(visible: true)
    defer { window.orderOut(nil) }

    #expect(
      !MenuKeyboardMonitor.shouldHandleKeyDown(
        menuWindow: window,
        modifierFlags: [],
        isEditingText: true
      )
    )
  }
}

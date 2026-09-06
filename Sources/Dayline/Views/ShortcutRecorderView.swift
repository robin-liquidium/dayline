import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: View {
  let shortcut: GlobalShortcut
  let defaultShortcut: GlobalShortcut
  let accessibilityLabel: String
  let onRecord: (GlobalShortcut) -> Void

  @State private var isRecording = false

  var body: some View {
    HStack(spacing: 8) {
      Button {
        isRecording.toggle()
      } label: {
        Text(isRecording ? "Type shortcut…" : shortcut.displayString)
          .monospaced()
          .frame(minWidth: 120)
      }
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(isRecording ? "Recording" : shortcut.displayString)
      .accessibilityHint(isRecording ? "Type the new shortcut, or press Escape to cancel" : "Record a new shortcut")
      .help(isRecording ? "Press Escape to cancel" : "Click to record a shortcut")
      .background {
        ShortcutCaptureField(isRecording: isRecording, onKeyDown: handleKeyDown)
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
      }

      if isRecording {
        Button("Cancel") { isRecording = false }
      } else if shortcut != defaultShortcut {
        Button("Reset") { onRecord(defaultShortcut) }
      }
    }
    .onDisappear { isRecording = false }
  }

  private func handleKeyDown(_ event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
    } else if let recorded = GlobalShortcut(event: event) {
      isRecording = false
      onRecord(recorded)
    }
  }
}

// AppKit captures physical key codes and consumes Command shortcuts before menus do.
private struct ShortcutCaptureField: NSViewRepresentable {
  let isRecording: Bool
  let onKeyDown: (NSEvent) -> Void

  func makeNSView(context: Context) -> ShortcutCaptureNSView {
    ShortcutCaptureNSView()
  }

  func updateNSView(_ view: ShortcutCaptureNSView, context: Context) {
    view.onKeyDown = onKeyDown
    view.isRecording = isRecording
  }
}

final class ShortcutCaptureNSView: NSView {
  var onKeyDown: ((NSEvent) -> Void)?
  var isRecording = false {
    didSet {
      guard oldValue != isRecording else { return }
      updateFirstResponder()
    }
  }

  override var acceptsFirstResponder: Bool { isRecording }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateFirstResponder()
  }

  private func updateFirstResponder() {
    if isRecording {
      window?.makeFirstResponder(self)
    } else if window?.firstResponder === self {
      window?.makeFirstResponder(nil)
    }
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }
    onKeyDown?(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else { return super.performKeyEquivalent(with: event) }
    keyDown(with: event)
    return true
  }
}

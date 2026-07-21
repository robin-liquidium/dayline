import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Settings control that displays a global shortcut and records a replacement.
struct ShortcutRecorderView: View {
  /// The currently persisted shortcut.
  let shortcut: GlobalShortcut

  /// The factory default used by the Reset action.
  let defaultShortcut: GlobalShortcut

  /// VoiceOver label identifying which shortcut value is displayed.
  let accessibilityLabel: String

  /// Called with a newly recorded shortcut.
  let onRecord: (GlobalShortcut) -> Void

  @State private var isRecording = false

  var body: some View {
    HStack(spacing: 8) {
      ShortcutCaptureField(
        text: isRecording ? "Type shortcut..." : shortcut.displayString,
        isRecording: isRecording,
        onKeyDown: handleKeyDown
      )
      .frame(width: 150, height: 22)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityLabel)
      .accessibilityValue(isRecording ? "Recording" : shortcut.displayString)
      .accessibilityHint(isRecording ? "Type the new shortcut" : "Select Record to change this shortcut")

      if isRecording {
        Button("Cancel") {
          isRecording = false
        }
      } else {
        Button("Record") {
          isRecording = true
        }
      }

      if !isRecording, shortcut != defaultShortcut {
        Button("Reset") {
          onRecord(defaultShortcut)
        }
      }
    }
  }

  /// Handles a captured key event while recording.
  private func handleKeyDown(_ event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) {
      isRecording = false
      return
    }
    guard let recorded = GlobalShortcut(event: event) else {
      return
    }
    isRecording = false
    onRecord(recorded)
  }
}

/// SwiftUI bridge for the first-responder capture field.
private struct ShortcutCaptureField: NSViewRepresentable {
  let text: String
  let isRecording: Bool
  let onKeyDown: (NSEvent) -> Void

  func makeNSView(context: Context) -> ShortcutCaptureNSView {
    let view = ShortcutCaptureNSView()
    view.onKeyDown = onKeyDown
    return view
  }

  func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
    nsView.displayText = text
    nsView.isRecording = isRecording
    nsView.onKeyDown = onKeyDown
    if isRecording {
      DispatchQueue.main.async {
        nsView.window?.makeFirstResponder(nsView)
      }
    }
  }
}

/// Bordered field that captures key events while recording a shortcut.
final class ShortcutCaptureNSView: NSView {
  var displayText = "" {
    didSet { needsDisplay = true }
  }

  var isRecording = false {
    didSet { needsDisplay = true }
  }

  var onKeyDown: ((NSEvent) -> Void)?

  override var acceptsFirstResponder: Bool {
    true
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 150, height: 22)
  }

  override func keyDown(with event: NSEvent) {
    onKeyDown?(event)
  }

  /// Swallows command-key equivalents while recording so menu shortcuts do not fire.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if isRecording {
      keyDown(with: event)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    let bezelRect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let bezel = NSBezierPath(roundedRect: bezelRect, xRadius: 5, yRadius: 5)
    NSColor.controlBackgroundColor.setFill()
    bezel.fill()
    (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
    bezel.lineWidth = isRecording ? 2 : 1
    bezel.stroke()

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
      .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
    ]
    let attributedText = NSAttributedString(string: displayText, attributes: attributes)
    let textSize = attributedText.size()
    attributedText.draw(at: NSPoint(
      x: (bounds.width - textSize.width) / 2,
      y: (bounds.height - textSize.height) / 2
    ))
  }
}

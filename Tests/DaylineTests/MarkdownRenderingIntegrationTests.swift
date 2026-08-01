import AppKit
@testable import Dayline
import MarkdownEngine
import SwiftUI
import Testing

@MainActor
struct MarkdownRenderingIntegrationTests {
  @Test func noteEditorUsesProductionFontAndBottomSafeArea() throws {
    let store = StatusStore(mockData: MockData.make())
    let editor = NoteEditorView(request: .existing("mock-note-1"))
      .environmentObject(store)
      .frame(width: 500, height: 420)
    let hostingView = NSHostingView(rootView: editor)
    hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 420)

    let textView = try waitForTextView(in: hostingView) {
      $0.textStorage?.string.hasPrefix("Landing page ideas") == true
    }
    let font = try #require(textView.font)
    #expect(font.familyName == NoteEditorAppearance.bodyFont.familyName)
    #expect(font.pointSize == NoteEditorAppearance.bodyFont.pointSize)

    let configuration = NoteFormattingBridge().configuration
    #expect(configuration.safeAreaInsets.bottom == 58)
  }

  @Test func complexMarkdownUsesEngineRenderedSemanticsWithoutLosingUnicode() throws {
    let source = """
    Plain *italic words* and **bold words** remain visible.

    * First bullet with *nested emphasis*
    * Second bullet keeps emoji 🚀 and café.
    """
    let configuration = NoteFormattingBridge().configuration
    #expect(configuration.lists.helpersEnabled)
    #expect(!configuration.lists.autoClosePairsEnabled)

    let editor = NativeTextViewWrapper(
      text: .constant(source),
      configuration: configuration,
      fontName: NoteEditorAppearance.bodyFont.fontName,
      fontSize: NoteEditorAppearance.bodyFont.pointSize,
      documentId: "markdown-rendering-integration"
    )
    let hostingView = NSHostingView(rootView: editor.frame(width: 700, height: 400))
    hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
    hostingView.layoutSubtreeIfNeeded()

    let textView = try waitForTextView(in: hostingView) {
      $0.textStorage?.string == source
    }
    let rendered = try #require(textView.textStorage)
    #expect(rendered.string == source)
    #expect(rendered.string.contains("🚀 and café"))

    let sourceNSString = source as NSString
    let bodyFont = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(bodyFont.pointSize == NSFont.systemFontSize)
    #expect(bodyFont.familyName == NoteEditorAppearance.bodyFont.familyName)

    let italicContent = sourceNSString.range(of: "italic words")
    let italicFont = try #require(rendered.attribute(.font, at: italicContent.location, effectiveRange: nil) as? NSFont)
    #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))

    let boldContent = sourceNSString.range(of: "bold words")
    let boldFont = try #require(rendered.attribute(.font, at: boldContent.location, effectiveRange: nil) as? NSFont)
    #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

    let italicMarker = sourceNSString.range(of: "*italic words*")
    let hiddenMarkerFont = try #require(rendered.attribute(.font, at: italicMarker.location, effectiveRange: nil) as? NSFont)
    #expect(hiddenMarkerFont.pointSize == configuration.markers.hiddenMarkerFontSize)

    let firstBullet = sourceNSString.range(of: "* First bullet")
    #expect(rendered.attribute(
      NSAttributedString.Key("BulletListMarker"),
      at: firstBullet.location,
      effectiveRange: nil
    ) as? Bool == true)
    let bulletStyle = try #require(
      rendered.attribute(.paragraphStyle, at: firstBullet.location + 2, effectiveRange: nil) as? NSParagraphStyle
    )
    #expect(bulletStyle.firstLineHeadIndent > 0)
    #expect(bulletStyle.headIndent > bulletStyle.firstLineHeadIndent)
  }

  private func waitForTextView(
    in hostingView: NSView,
    condition: (NSTextView) -> Bool
  ) throws -> NSTextView {
    let deadline = Date().addingTimeInterval(2)
    var matchingTextView: NSTextView?
    repeat {
      hostingView.layoutSubtreeIfNeeded()
      if let textView = findTextView(in: hostingView), condition(textView) {
        matchingTextView = textView
        break
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    } while Date() < deadline
    return try #require(matchingTextView)
  }

  private func findTextView(in view: NSView) -> NSTextView? {
    if let textView = view as? NSTextView {
      return textView
    }
    for subview in view.subviews {
      if let textView = findTextView(in: subview) {
        return textView
      }
    }
    return nil
  }
}

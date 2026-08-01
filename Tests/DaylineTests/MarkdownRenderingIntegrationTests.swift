import AppKit
import MarkdownEngine
import SwiftUI
import Testing

@MainActor
struct MarkdownRenderingIntegrationTests {
  @Test func complexMarkdownUsesEngineRenderedSemanticsWithoutLosingUnicode() throws {
    let source = """
    Plain *italic words* and **bold words** remain visible.

    * First bullet with *nested emphasis*
    * Second bullet keeps emoji 🚀 and café.
    """
    let configuration = MarkdownEditorConfiguration.default
    let editor = NativeTextViewWrapper(
      text: .constant(source),
      configuration: configuration,
      documentId: "markdown-rendering-integration"
    )
    let hostingView = NSHostingView(rootView: editor.frame(width: 700, height: 400))
    hostingView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
    hostingView.layoutSubtreeIfNeeded()

    let deadline = Date().addingTimeInterval(2)
    var foundTextView: NSTextView?
    repeat {
      hostingView.layoutSubtreeIfNeeded()
      foundTextView = findTextView(in: hostingView)
      if foundTextView?.textStorage?.string == source { break }
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    } while Date() < deadline

    let textView = try #require(foundTextView)
    let rendered = try #require(textView.textStorage)
    #expect(rendered.string == source)
    #expect(rendered.string.contains("🚀 and café"))

    let sourceNSString = source as NSString
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

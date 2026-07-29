import AppKit
import Testing
@testable import Dayline

struct MarkdownHighlighterTests {
  @MainActor
  private func highlightedTextView(for source: String) -> NSTextView {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    textView.string = source
    MarkdownHighlighter.highlight(textView: textView)
    return textView
  }

  @MainActor
  private func fontTraits(in textView: NSTextView, substring: String) -> NSFontTraitMask {
    let nsSource = textView.string as NSString
    let range = nsSource.range(of: substring)
    #expect(range.location != NSNotFound)
    let font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    #expect(font != nil)
    return font.map { NSFontManager.shared.traits(of: $0) } ?? []
  }

  @MainActor
  @Test func headingGetsBoldLargerFont() {
    let textView = highlightedTextView(for: "# Big title\n\nbody text")
    let traits = fontTraits(in: textView, substring: "Big title")
    #expect(traits.contains(.boldFontMask))

    let bodyTraits = fontTraits(in: textView, substring: "body text")
    #expect(!bodyTraits.contains(.boldFontMask))
  }

  @MainActor
  @Test func strongAndEmphasisGetTraits() {
    let textView = highlightedTextView(for: "plain **bold** and *italic* done")
    #expect(fontTraits(in: textView, substring: "**bold**").contains(.boldFontMask))
    #expect(fontTraits(in: textView, substring: "*italic*").contains(.italicFontMask))
    let plainTraits = fontTraits(in: textView, substring: "plain")
    #expect(!plainTraits.contains(.boldFontMask))
    #expect(!plainTraits.contains(.italicFontMask))
  }

  @MainActor
  @Test func inlineCodeGetsMonospaceAndBackground() {
    let textView = highlightedTextView(for: "use `print(x)` here")
    let nsSource = textView.string as NSString
    let range = nsSource.range(of: "`print(x)`")
    let font = textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    #expect(font?.isFixedPitch == true)
    let background = textView.textStorage?.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
    #expect(background != nil)
  }

  @MainActor
  @Test func linkGetsUnderlineAndAccentColor() {
    let textView = highlightedTextView(for: "see [docs](https://example.com) today")
    let nsSource = textView.string as NSString
    let range = nsSource.range(of: "[docs](https://example.com)")
    let underline = textView.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)
    let color = textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    #expect(color == .controlAccentColor)
  }

  @MainActor
  @Test func unicodeBeforeMarkupKeepsOffsetsAligned() {
    let textView = highlightedTextView(for: "emoji 😀 café\n\n**bold move**")
    let traits = fontTraits(in: textView, substring: "**bold move**")
    #expect(traits.contains(.boldFontMask))

    let plainTraits = fontTraits(in: textView, substring: "café")
    #expect(!plainTraits.contains(.boldFontMask))
  }

  @MainActor
  @Test func blockQuoteGetsSecondaryColor() {
    let textView = highlightedTextView(for: "text\n\n> quoted line")
    let nsSource = textView.string as NSString
    let range = nsSource.range(of: "quoted line")
    let color = textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    #expect(color == .secondaryLabelColor)
  }
}

import AppKit
import Markdown
import SwiftUI

/// AppKit text editor that highlights markdown structure live while typing.
struct MarkdownTextEditor: NSViewRepresentable {
  @Binding var text: String

  /// Accessibility identifier forwarded to the hosted text view.
  var accessibilityIdentifier: String?

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false

    let textView = scrollView.documentView as! NSTextView
    textView.font = MarkdownHighlighter.baseFont
    textView.typingAttributes = MarkdownHighlighter.baseAttributes
    textView.drawsBackground = false
    textView.isRichText = true
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.textContainerInset = NSSize(width: 4, height: 6)
    textView.delegate = context.coordinator
    textView.string = text
    if let accessibilityIdentifier {
      textView.setAccessibilityIdentifier(accessibilityIdentifier)
    }
    context.coordinator.textView = textView
    context.coordinator.applyHighlighting()
    return scrollView
  }

  func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView, textView.string != text else {
      return
    }
    let selectedRanges = textView.selectedRanges
    textView.string = text
    textView.selectedRanges = selectedRanges
    context.coordinator.applyHighlighting()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    weak var textView: NSTextView?

    init(text: Binding<String>) {
      _text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else {
        return
      }
      text = textView.string
      applyHighlighting()
    }

    /// Reapplies markdown highlighting, skipping IME composition to avoid disruption.
    func applyHighlighting() {
      guard let textView, !textView.hasMarkedText() else {
        return
      }
      MarkdownHighlighter.highlight(textView: textView)
    }
  }
}

/// Applies swift-markdown structure as text attributes on an editor's storage.
enum MarkdownHighlighter {
  static let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

  static var baseAttributes: [NSAttributedString.Key: Any] {
    [
      .font: baseFont,
      .foregroundColor: NSColor.textColor
    ]
  }

  /// Re-styles the entire contents of the text view from its markdown structure.
  static func highlight(textView: NSTextView) {
    guard let storage = textView.textStorage else {
      return
    }
    let source = textView.string
    let lineStarts = Self.lineStartOffsets(in: source)
    let fullRange = NSRange(location: 0, length: (source as NSString).length)

    storage.beginEditing()
    storage.setAttributes(baseAttributes, range: fullRange)

    let document = Document(parsing: source)
    var walker = HighlightWalker(source: source, lineStarts: lineStarts) { range, attributes in
      guard let range, range.location != NSNotFound, NSMaxRange(range) <= fullRange.length else {
        return
      }
      storage.addAttributes(attributes, range: range)
    }
    walker.visit(document)
    storage.endEditing()
  }

  /// UTF-16 offsets for the start of each 1-indexed source line.
  private static func lineStartOffsets(in source: String) -> [Int] {
    var starts = [0]
    let nsSource = source as NSString
    for index in 0..<nsSource.length {
      if nsSource.character(at: index) == 0x0A {
        starts.append(index + 1)
      }
    }
    return starts
  }

  /// Converts a markdown source location (1-indexed line/column) to a UTF-16 offset.
  private static func offset(for location: SourceLocation, lineStarts: [Int], upperBound: Int) -> Int? {
    let lineIndex = location.line - 1
    guard lineStarts.indices.contains(lineIndex) else {
      return nil
    }
    let offset = lineStarts[lineIndex] + location.column - 1
    return offset <= upperBound ? offset : nil
  }

  /// NSRange for a markup node, or nil when its source span is unknown.
  private static func nsRange(of markup: Markup, lineStarts: [Int], upperBound: Int) -> NSRange? {
    guard let range = markup.range,
          let start = offset(for: range.lowerBound, lineStarts: lineStarts, upperBound: upperBound),
          let end = offset(for: range.upperBound, lineStarts: lineStarts, upperBound: upperBound),
          end >= start else {
      return nil
    }
    return NSRange(location: start, length: end - start)
  }

  /// Font with bold and italic traits applied on top of the base font.
  private static func font(bold: Bool = false, italic: Bool = false, size: CGFloat = NSFont.systemFontSize, design: NSFontDescriptor.SystemDesign = .default) -> NSFont {
    let base = NSFont.systemFont(ofSize: size)
    let designed = base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    var traits: NSFontTraitMask = []
    if bold { traits.insert(.boldFontMask) }
    if italic { traits.insert(.italicFontMask) }
    return NSFontManager.shared.convert(designed, toHaveTrait: traits)
  }

  /// Walks the markdown tree applying attributes per node type.
  private struct HighlightWalker: MarkupWalker {
    let source: String
    let lineStarts: [Int]
    let apply: (NSRange?, [NSAttributedString.Key: Any]) -> Void

    private var upperBound: Int {
      (source as NSString).length
    }

    private func range(of markup: Markup) -> NSRange? {
      MarkdownHighlighter.nsRange(of: markup, lineStarts: lineStarts, upperBound: upperBound)
    }

    mutating func visitHeading(_ heading: Heading) {
      let level = min(heading.level, 3)
      let size = [NSFont.systemFontSize + 6, NSFont.systemFontSize + 3, NSFont.systemFontSize + 1][level - 1]
      apply(range(of: heading), [.font: MarkdownHighlighter.font(bold: true, size: size)])
      descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
      apply(range(of: strong), [.font: MarkdownHighlighter.font(bold: true)])
      descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
      apply(range(of: emphasis), [.font: MarkdownHighlighter.font(italic: true)])
      descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
      apply(range(of: strikethrough), [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
      descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
      apply(range(of: inlineCode), [
        .font: MarkdownHighlighter.font(design: .monospaced),
        .backgroundColor: NSColor.quaternaryLabelColor
      ])
      descendInto(inlineCode)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
      apply(range(of: codeBlock), [
        .font: MarkdownHighlighter.font(design: .monospaced),
        .backgroundColor: NSColor.quaternaryLabelColor
      ])
      descendInto(codeBlock)
    }

    mutating func visitLink(_ link: Markdown.Link) {
      apply(range(of: link), [
        .foregroundColor: NSColor.controlAccentColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue
      ])
      descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
      apply(range(of: blockQuote), [.foregroundColor: NSColor.secondaryLabelColor])
      descendInto(blockQuote)
    }
  }
}

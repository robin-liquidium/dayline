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
    guard let textView = nsView.documentView as? NSTextView else {
      return
    }
    let coordinator = context.coordinator
    if text == coordinator.lastPublishedText {
      return
    }
    coordinator.lastPublishedText = text
    guard textView.string != text else {
      return
    }
    let selectedRanges = textView.selectedRanges
    textView.string = text
    textView.selectedRanges = Self.clampedSelectionRanges(
      selectedRanges,
      textLength: (text as NSString).length
    )
    coordinator.applyHighlighting()
  }

  /// Keeps external text replacement from restoring selections past the new end.
  static func clampedSelectionRanges(_ ranges: [NSValue], textLength: Int) -> [NSValue] {
    ranges.map { value in
      let range = value.rangeValue
      let location = min(range.location, textLength)
      let length = min(range.length, textLength - location)
      return NSValue(range: NSRange(location: location, length: length))
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String

    /// Last text published to the binding; distinguishes view-originated
    /// updates from external ones so fast typing is never clobbered.
    var lastPublishedText = ""

    weak var textView: NSTextView?

    init(text: Binding<String>) {
      _text = text
      lastPublishedText = text.wrappedValue
    }

    func textDidChange(_ notification: Notification) {
      guard let textView else {
        return
      }
      lastPublishedText = textView.string
      text = lastPublishedText
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

  /// Attributes that collapse markdown delimiters out of view once formatted.
  static var hiddenAttributes: [NSAttributedString.Key: Any] {
    [
      .font: NSFont.systemFont(ofSize: 0.1),
      .foregroundColor: NSColor.clear
    ]
  }

  /// Re-styles the entire contents of the text view from its markdown structure.
  static func highlight(textView: NSTextView) {
    guard let storage = textView.textStorage else {
      return
    }
    let source = textView.string
    let lineStarts = Self.utf8LineStartOffsets(in: source)
    let fullRange = NSRange(location: 0, length: (source as NSString).length)

    storage.beginEditing()
    storage.setAttributes(baseAttributes, range: fullRange)

    let document = Document(parsing: source)
    var walker = HighlightWalker(source: source, lineStarts: lineStarts, storage: storage) { range, attributes in
      guard let range, range.location != NSNotFound, NSMaxRange(range) <= fullRange.length else {
        return
      }
      storage.addAttributes(attributes, range: range)
    }
    walker.visit(document)
    storage.endEditing()
  }

  /// UTF-8 byte offsets for the start of each 1-indexed source line.
  private static func utf8LineStartOffsets(in source: String) -> [Int] {
    var starts = [0]
    for (index, byte) in source.utf8.enumerated() {
      if byte == 0x0A {
        starts.append(index + 1)
      }
    }
    return starts
  }

  /// Converts swift-markdown's 1-based UTF-8 byte location to an AppKit UTF-16 offset.
  private static func offset(
    for location: SourceLocation,
    in source: String,
    lineStarts: [Int]
  ) -> Int? {
    let lineIndex = location.line - 1
    guard lineStarts.indices.contains(lineIndex) else {
      return nil
    }
    let byteOffset = lineStarts[lineIndex] + location.column - 1
    guard byteOffset >= 0, byteOffset <= source.utf8.count else {
      return nil
    }
    let utf8Index = source.utf8.index(source.utf8.startIndex, offsetBy: byteOffset)
    guard let stringIndex = String.Index(utf8Index, within: source),
          let utf16Index = stringIndex.samePosition(in: source.utf16) else {
      return nil
    }
    return source.utf16.distance(from: source.utf16.startIndex, to: utf16Index)
  }

  /// NSRange for a markup node, or nil when its source span is unknown.
  private static func nsRange(of markup: Markup, source: String, lineStarts: [Int]) -> NSRange? {
    guard let range = markup.range,
          let start = offset(for: range.lowerBound, in: source, lineStarts: lineStarts),
          let end = offset(for: range.upperBound, in: source, lineStarts: lineStarts),
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
    let storage: NSTextStorage
    let apply: (NSRange?, [NSAttributedString.Key: Any]) -> Void

    private func range(of markup: Markup) -> NSRange? {
      MarkdownHighlighter.nsRange(of: markup, source: source, lineStarts: lineStarts)
    }

    private func hide(_ range: NSRange) {
      apply(range, MarkdownHighlighter.hiddenAttributes)
    }

    /// Adds font traits while preserving traits and sizes applied by parent nodes.
    private func applyFont(
      to range: NSRange?,
      bold: Bool = false,
      italic: Bool = false,
      size: CGFloat? = nil
    ) {
      guard let range else { return }
      var segments: [(NSRange, NSFont)] = []
      storage.enumerateAttribute(.font, in: range) { value, segment, _ in
        segments.append((segment, value as? NSFont ?? MarkdownHighlighter.baseFont))
      }
      for (segment, existingFont) in segments {
        let pointSize = size ?? existingFont.pointSize
        let resized = NSFont(descriptor: existingFont.fontDescriptor, size: pointSize) ?? existingFont
        var traits = NSFontManager.shared.traits(of: resized)
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let merged = NSFontManager.shared.convert(resized, toHaveTrait: traits)
        apply(segment, [.font: merged])
      }
    }

    /// Hides the delimiter text before the first and after the last child node.
    private func hidePadding(of markup: Markup) {
      guard let nodeRange = range(of: markup), markup.childCount > 0,
            let first = markup.child(at: 0), let firstRange = range(of: first),
            let last = markup.child(at: markup.childCount - 1), let lastRange = range(of: last) else {
        return
      }
      if firstRange.location > nodeRange.location {
        hide(NSRange(location: nodeRange.location, length: firstRange.location - nodeRange.location))
      }
      let nodeEnd = NSMaxRange(nodeRange), lastEnd = NSMaxRange(lastRange)
      if nodeEnd > lastEnd {
        hide(NSRange(location: lastEnd, length: nodeEnd - lastEnd))
      }
    }

    mutating func visitHeading(_ heading: Heading) {
      let level = min(heading.level, 3)
      let size = [NSFont.systemFontSize + 6, NSFont.systemFontSize + 3, NSFont.systemFontSize + 1][level - 1]
      applyFont(to: range(of: heading), bold: true, size: size)
      hidePadding(of: heading)
      descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
      applyFont(to: range(of: strong), bold: true)
      hidePadding(of: strong)
      descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
      applyFont(to: range(of: emphasis), italic: true)
      hidePadding(of: emphasis)
      descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
      apply(range(of: strikethrough), [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
      hidePadding(of: strikethrough)
      descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
      apply(range(of: inlineCode), [
        .font: MarkdownHighlighter.font(design: .monospaced),
        .backgroundColor: NSColor.quaternaryLabelColor
      ])
      if let nodeRange = range(of: inlineCode) {
        let markerLength = (nodeRange.length - (inlineCode.code as NSString).length) / 2
        if markerLength > 0 {
          hide(NSRange(location: nodeRange.location, length: markerLength))
          hide(NSRange(location: NSMaxRange(nodeRange) - markerLength, length: markerLength))
        }
      }
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
      hidePadding(of: link)
      descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
      apply(range(of: blockQuote), [.foregroundColor: NSColor.secondaryLabelColor])
      descendInto(blockQuote)
    }
  }
}

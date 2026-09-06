import AppKit
import MarkdownEngine

/// Shared typography, with tighter spacing for issue previews than editable notes.
enum DaylineMarkdownStyle {
  static func configuration(compact: Bool) -> MarkdownEditorConfiguration {
    var configuration = MarkdownEditorConfiguration.default
    configuration.headings = HeadingStyle(
      fontMultipliers: compact
        ? [1.45, 1.3, 1.15, 1.05, 1, 1]
        : [1.75, 1.45, 1.2, 1.1, 1, 1],
      topSpacingEm: compact
        ? [0.4, 0.35, 0.3, 0.25, 0.2, 0.2]
        : [0.55, 0.45, 0.35, 0.3, 0.25, 0.25]
    )
    configuration.paragraph = ParagraphStyle(
      spacingFactor: compact ? 0.12 : 0.18,
      lineHeightExtraSpacing: 2
    )
    // The engine also applies this indent to top-level list markers.
    configuration.lists.indentPerLevel = compact ? 10 : 12
    configuration.lists.extraLineHeight = 1
    configuration.lists.autoClosePairsEnabled = false
    configuration.blockquote.extraLineHeight = 2
    configuration.codeBlock = CodeBlockStyle(
      fontSizeScale: 0.95,
      paragraphSpacing: compact ? 4 : 6,
      horizontalIndent: compact ? 8 : 12
    )
    configuration.inlineCode.fontSizeScale = 0.95
    configuration.link.activeLinkAlpha = 1
    configuration.services.syntaxHighlighter = DaylineCodeBlockStyle()
    configuration.extensions = [StrikethroughExtension()]
    if compact {
      configuration.heightBehavior = .fitsContent
      configuration.spellChecking = SpellCheckingPolicy(
        continuousSpellChecking: false,
        grammarChecking: false,
        automaticSpellingCorrection: false
      )
    } else {
      configuration.textInsets = TextInsets(horizontal: 4, vertical: 8)
    }
    return configuration
  }
}

/// The engine supplies code-block appearance through its syntax-highlighter service.
private struct DaylineCodeBlockStyle: SyntaxHighlighter {
  func codeFont(size: CGFloat) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  func backgroundColor() -> NSColor {
    .quaternaryLabelColor
  }

  func highlight(code: String, language: String?) -> NSAttributedString? {
    nil
  }

  var appearanceDidChangeNotification: Notification.Name? { nil }
}

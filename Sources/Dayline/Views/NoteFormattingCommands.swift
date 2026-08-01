import MarkdownEngine
import SwiftUI

/// Markdown transformations exposed in the native Format menu.
enum NoteFormattingAction {
  case bold
  case italic
  case strikethrough
  case inlineCode
  case link
  case unorderedList
  case orderedList
  case blockquote
  case heading(Int)

  var diagnosticName: String {
    switch self {
    case .bold: "bold"
    case .italic: "italic"
    case .strikethrough: "strikethrough"
    case .inlineCode: "inline code"
    case .link: "link"
    case .unorderedList: "unordered list"
    case .orderedList: "ordered list"
    case .blockquote: "blockquote"
    case .heading(let level): "heading \(level)"
    }
  }
}

/// Formatting closure published by the active note editor scene.
struct NoteFormattingActions {
  let perform: (NoteFormattingAction) -> Void
}

private struct NoteFormattingActionsKey: FocusedValueKey {
  typealias Value = NoteFormattingActions
}

extension FocusedValues {
  var noteFormattingActions: NoteFormattingActions? {
    get { self[NoteFormattingActionsKey.self] }
    set { self[NoteFormattingActionsKey.self] = newValue }
  }
}

/// Native macOS formatting menu whose shortcuts follow the focused note window.
struct NoteFormattingCommands: Commands {
  @FocusedValue(\.noteFormattingActions) private var actions

  var body: some Commands {
    CommandMenu("Format") {
      Button("Bold") { perform(.bold) }
        .keyboardShortcut("b", modifiers: .command)
        .disabled(actions == nil)
      Button("Italic") { perform(.italic) }
        .keyboardShortcut("i", modifiers: .command)
        .disabled(actions == nil)
      Button("Strikethrough") { perform(.strikethrough) }
        .keyboardShortcut("x", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Button("Inline Code") { perform(.inlineCode) }
        .keyboardShortcut("`", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Button("Link") { perform(.link) }
        .keyboardShortcut("k", modifiers: .command)
        .disabled(actions == nil)

      Divider()

      Button("Bulleted List") { perform(.unorderedList) }
        .keyboardShortcut("8", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Button("Numbered List") { perform(.orderedList) }
        .keyboardShortcut("7", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Button("Block Quote") { perform(.blockquote) }
        .keyboardShortcut("9", modifiers: [.command, .shift])
        .disabled(actions == nil)

      Divider()

      Button("Heading 1") { perform(.heading(1)) }
        .keyboardShortcut("1", modifiers: [.command, .option])
        .disabled(actions == nil)
      Button("Heading 2") { perform(.heading(2)) }
        .keyboardShortcut("2", modifiers: [.command, .option])
        .disabled(actions == nil)
      Button("Heading 3") { perform(.heading(3)) }
        .keyboardShortcut("3", modifiers: [.command, .option])
        .disabled(actions == nil)
    }
  }

  private func perform(_ action: NoteFormattingAction) {
    actions?.perform(action)
  }
}

/// Unique notification bus connecting one note window to one engine instance.
final class NoteFormattingBridge {
  private let identifier = UUID().uuidString

  private lazy var bold = notification("bold")
  private lazy var italic = notification("italic")
  private lazy var strikethrough = notification("strikethrough")
  private lazy var inlineCode = notification("inlineCode")
  private lazy var link = notification("link")
  private lazy var unorderedList = notification("unorderedList")
  private lazy var orderedList = notification("orderedList")
  private lazy var blockquote = notification("blockquote")
  private lazy var heading = notification("heading")

  lazy var configuration: MarkdownEditorConfiguration = {
    var configuration = MarkdownEditorConfiguration.default
    configuration.services.bus = MarkdownEditorBus(
      applyBoldRequest: bold,
      applyItalicRequest: italic,
      applyHeadingRequest: heading,
      applyStrikethroughRequest: strikethrough,
      applyInlineCodeRequest: inlineCode,
      applyBlockquoteRequest: blockquote,
      applyUnorderedListRequest: unorderedList,
      applyOrderedListRequest: orderedList,
      applyLinkRequest: link
    )
    configuration.lists.autoClosePairsEnabled = false
    configuration.safeAreaInsets.bottom = 58
    configuration.extensions = [StrikethroughExtension()]
    return configuration
  }()

  func perform(_ action: NoteFormattingAction) {
    let name: Notification.Name
    var userInfo: [AnyHashable: Any]?

    switch action {
    case .bold: name = bold
    case .italic: name = italic
    case .strikethrough: name = strikethrough
    case .inlineCode: name = inlineCode
    case .link: return
    case .unorderedList: name = unorderedList
    case .orderedList: name = orderedList
    case .blockquote: name = blockquote
    case .heading(let level):
      name = heading
      userInfo = ["level": level]
    }

    NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    DaylineDiagnostics.record("Note formatting command requested: \(action.diagnosticName)", category: .interaction)
  }

  /// Sends the URL payload required by MarkdownEngine's `applyLinkRequest` contract.
  func performLink(url: String) {
    guard !url.isEmpty else { return }
    NotificationCenter.default.post(name: link, object: nil, userInfo: ["url": url])
    DaylineDiagnostics.record("Note formatting command requested: link", category: .interaction)
  }

  private func notification(_ action: String) -> Notification.Name {
    Notification.Name("Dayline.NoteFormatting.\(identifier).\(action)")
  }
}

import AppKit
import MarkdownEngine
import SwiftUI

/// Native visual defaults shared by the note editor and its rendering tests.
enum NoteEditorAppearance {
  static let bodyFont = NSFont.systemFont(ofSize: 14)
}

/// Stock SwiftUI window for creating notes and editing note text locally.
struct NoteEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  /// Window request that seeds the editor.
  let request: NoteEditorRequest

  @StateObject private var draft = NoteEditorDraft()
  @State private var linkURL = ""
  @State private var isShowingLinkPrompt = false

  var body: some View {
    VStack(spacing: 0) {
      NativeTextViewWrapper(
        text: $draft.text,
        configuration: draft.markdownConfiguration,
        fontName: NoteEditorAppearance.bodyFont.fontName,
        fontSize: NoteEditorAppearance.bodyFont.pointSize,
        documentId: existingNoteID ?? draft.editorDocumentID
      )
        .accessibilityIdentifier("noteEditor.text")
        .padding(.horizontal, 8)
        .padding(.top, 4)

      HStack(alignment: .bottom, spacing: 12) {
        if let errorMessage = draft.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(errorMessage)
            .accessibilityIdentifier("noteEditor.error")
        }

        Spacer()

        GlassEffectContainer(spacing: 8) {
          HStack(spacing: 8) {
            Button("Cancel") {
              dismiss()
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("noteEditor.cancel")

            Button("Save", action: save)
              .buttonStyle(.glassProminent)
              .buttonBorderShape(.capsule)
              .keyboardShortcut(.defaultAction)
              .disabled(!canSave)
              .accessibilityIdentifier("noteEditor.save")
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 12)
    }
    .frame(minWidth: 440, minHeight: 320)
    .navigationTitle(request.isExisting ? "Note" : "New Note")
    .background {
      WindowLevelConfigurator(keepOnTop: store.notesKeepOnTop)
    }
    .focusedSceneValue(
      \.noteFormattingActions,
      NoteFormattingActions(perform: performFormatting)
    )
    .alert("Insert Link", isPresented: $isShowingLinkPrompt) {
      TextField("URL", text: $linkURL)
      Button("Cancel", role: .cancel) {
        linkURL = ""
      }
      Button("Insert") {
        draft.formatting.performLink(url: linkURL.trimmingCharacters(in: .whitespacesAndNewlines))
        linkURL = ""
      }
      .disabled(linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } message: {
      Text("Enter the destination URL for the selected text.")
    }
    .onAppear(perform: loadInitialNoteIfNeeded)
  }

  private func performFormatting(_ action: NoteFormattingAction) {
    if case .link = action {
      isShowingLinkPrompt = true
    } else {
      draft.formatting.perform(action)
    }
  }

  /// Whether the current editor contents can be saved locally.
  private var canSave: Bool {
    !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Seeds the editor from the cached note for existing-note windows.
  private func loadInitialNoteIfNeeded() {
    guard !draft.hasLoadedInitialNote else {
      return
    }
    draft.hasLoadedInitialNote = true

    guard case .existing(let noteID) = request else {
      return
    }

    guard let note = store.localNote(withID: noteID) else {
      draft.errorMessage = "Note was not found."
      return
    }

    draft.text = note.text
  }

  /// Saves the editor contents as a local note.
  private func save() {
    guard canSave else {
      return
    }

    draft.errorMessage = nil

    do {
      try store.saveLocalNote(id: existingNoteID, text: draft.text)
      dismiss()
    } catch {
      draft.errorMessage = error.localizedDescription.compactLine(limit: 140)
    }
  }

  /// Existing note identifier when this editor is updating a local note.
  private var existingNoteID: LocalNoteItem.ID? {
    guard case .existing(let noteID) = request else {
      return nil
    }
    return noteID
  }
}

/// Applies the keep-on-top preference to the hosting window.
private struct WindowLevelConfigurator: NSViewRepresentable {
  let keepOnTop: Bool

  func makeNSView(context: Context) -> WindowLevelConfiguratorView {
    WindowLevelConfiguratorView(keepOnTop: keepOnTop)
  }

  func updateNSView(_ nsView: WindowLevelConfiguratorView, context: Context) {
    nsView.apply(keepOnTop: keepOnTop)
  }
}

private final class WindowLevelConfiguratorView: NSView {
  private var keepOnTop: Bool

  init(keepOnTop: Bool) {
    self.keepOnTop = keepOnTop
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    apply(keepOnTop: keepOnTop)
  }

  /// Sets the window level from the preference, defaulting back to normal.
  func apply(keepOnTop: Bool) {
    self.keepOnTop = keepOnTop
    window?.level = keepOnTop ? .floating : .normal
  }
}

/// Observable draft state for the note editor window.
private final class NoteEditorDraft: ObservableObject {
  /// Stable identity used to isolate undo history and formatting commands.
  let editorDocumentID = UUID().uuidString

  /// Per-editor formatting bridge so shortcuts only affect the active note window.
  let formatting = NoteFormattingBridge()

  /// Markdown engine defaults plus Dayline's formatting command bridge.
  lazy var markdownConfiguration: MarkdownEditorConfiguration = {
    var configuration = formatting.configuration
    if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
      configuration.spellChecking = SpellCheckingPolicy(
        continuousSpellChecking: false,
        grammarChecking: false,
        automaticSpellingCorrection: false
      )
    }
    return configuration
  }()

  /// Editable note body.
  @Published var text = ""

  /// Compact save/load error text.
  @Published var errorMessage: String?

  /// Whether the initial cached note has been copied into this draft.
  @Published var hasLoadedInitialNote = false
}

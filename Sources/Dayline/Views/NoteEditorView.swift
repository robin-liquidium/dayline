import SwiftUI

/// Stock SwiftUI window for creating notes and editing note text locally.
struct NoteEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  /// Window request that seeds the editor.
  let request: NoteEditorRequest

  @StateObject private var draft = NoteEditorDraft()

  /// Builds the note editor window content.
  var body: some View {
    VStack(spacing: 0) {
      TextEditor(text: $draft.text)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .accessibilityIdentifier("noteEditor.text")

      if let errorMessage = draft.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("noteEditor.error")
      }

      Divider()

      HStack {
        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("noteEditor.cancel")

        Button(saveButtonTitle) {
          Task { await save() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSave)
        .accessibilityIdentifier("noteEditor.save")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .frame(minWidth: 440, minHeight: 320)
    .navigationTitle(request.isExisting ? "Note" : "New Note")
    .onAppear(perform: loadInitialNoteIfNeeded)
  }

  /// Title for the primary save action.
  private var saveButtonTitle: String {
    if draft.isSaving {
      return "Saving..."
    }
    return "Save"
  }

  /// Whether the current editor contents can be saved locally.
  private var canSave: Bool {
    !draft.isSaving && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
  private func save() async {
    guard canSave else {
      return
    }

    draft.isSaving = true
    draft.errorMessage = nil

    do {
      _ = try store.saveLocalNote(id: existingNoteID, text: draft.text)
      dismiss()
    } catch {
      draft.errorMessage = error.localizedDescription.compactLine(limit: 140)
    }

    draft.isSaving = false
  }

  /// Existing note identifier when this editor is updating a local note.
  private var existingNoteID: LocalNoteItem.ID? {
    guard case .existing(let noteID) = request else {
      return nil
    }
    return noteID
  }
}

/// Observable draft state for the note editor window.
private final class NoteEditorDraft: ObservableObject {
  /// Editable note body.
  @Published var text = ""

  /// Compact save/load error text.
  @Published var errorMessage: String?

  /// Whether a save command is currently in flight.
  @Published var isSaving = false

  /// Whether the initial cached note has been copied into this draft.
  @Published var hasLoadedInitialNote = false
}

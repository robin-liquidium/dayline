import SwiftUI

/// Local note display settings for the menu.
struct NotesSettingsTab: View {
  @Environment(StatusStore.self) private var store

  var body: some View {
    Form {
      Section {
        Toggle("Show Notes tab in menu", isOn: showsNotesSectionBinding)
          .accessibilityIdentifier("settings.showsNotesSection")

        Picker("Sort notes by", selection: localNoteSortOrderBinding) {
          ForEach(LocalNoteSortOrder.allCases) { order in
            Text(order.label).tag(order)
          }
        }
        .disabled(!store.showsNotesSection)
        .accessibilityIdentifier("settings.localNoteSortOrder")
      } header: {
        Label("Menu", systemImage: "list.bullet")
      } footer: {
        Text("Notes appear as a tab next to your issues. Scroll the list to see all of them.")
      }

      Section {
        Toggle("Keep note windows on top", isOn: notesKeepOnTopBinding)
          .accessibilityIdentifier("settings.notesKeepOnTop")
      } header: {
        Label("Window", systemImage: "macwindow")
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Binding that persists whether the notes section appears in the menu.
  private var showsNotesSectionBinding: Binding<Bool> {
    Binding(
      get: { store.showsNotesSection },
      set: { store.setShowsNotesSection($0) }
    )
  }

  /// Binding that persists whether note windows float above other windows.
  private var notesKeepOnTopBinding: Binding<Bool> {
    Binding(
      get: { store.notesKeepOnTop },
      set: { store.setNotesKeepOnTop($0) }
    )
  }

  /// Binding that forwards local note ordering changes to the store.
  private var localNoteSortOrderBinding: Binding<LocalNoteSortOrder> {
    Binding(
      get: { store.localNoteSortOrder },
      set: { store.setLocalNoteSortOrder($0) }
    )
  }
}

import SwiftUI

/// Local note display settings for the menu.
struct NotesSettingsTab: View {
  @EnvironmentObject private var store: StatusStore

  /// Supported default note counts.
  private let defaultNoteCountOptions = [3, 5, 10, 15]

  var body: some View {
    Form {
      Section {
        Toggle("Show notes in menu", isOn: showsNotesSectionBinding)
          .accessibilityIdentifier("settings.showsNotesSection")

        Picker("Notes shown", selection: defaultNoteCountBinding) {
          ForEach(defaultNoteCountPickerOptions, id: \.self) { count in
            Text(count == 1 ? "1 note" : "\(count) notes").tag(count)
          }
        }
        .disabled(!store.showsNotesSection)
        .accessibilityIdentifier("settings.defaultNoteCount")

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
        Text("The menu initially shows this many notes. Expand it to see more.")
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

  /// Binding that forwards default note count changes to the store.
  private var defaultNoteCountBinding: Binding<Int> {
    Binding(
      get: { store.defaultVisibleNoteCount },
      set: { store.setDefaultVisibleNoteCount($0) }
    )
  }

  /// Note count choices plus any existing custom stored value.
  private var defaultNoteCountPickerOptions: [Int] {
    Array(Set(defaultNoteCountOptions + [store.defaultVisibleNoteCount])).sorted()
  }

  /// Binding that forwards local note ordering changes to the store.
  private var localNoteSortOrderBinding: Binding<LocalNoteSortOrder> {
    Binding(
      get: { store.localNoteSortOrder },
      set: { store.setLocalNoteSortOrder($0) }
    )
  }
}

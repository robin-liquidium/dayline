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
            Text("\(count)").tag(count)
          }
        }
        .accessibilityIdentifier("settings.defaultNoteCount")

        Picker("Notes sort", selection: localNoteSortOrderBinding) {
          ForEach(LocalNoteSortOrder.allCases) { order in
            Text(order.label).tag(order)
          }
        }
        .accessibilityIdentifier("settings.localNoteSortOrder")
      } header: {
        Label("Menu", systemImage: "list.bullet")
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

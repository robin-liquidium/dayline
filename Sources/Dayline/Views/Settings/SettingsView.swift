import SwiftUI

/// Native settings window with a System Settings-style sidebar and cross-tab search.
struct SettingsView: View {
  @EnvironmentObject private var store: StatusStore
  @State private var selectedTab: SettingsTab? = .general
  @State private var searchText = ""

  private var trimmedQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isSearching: Bool {
    !trimmedQuery.isEmpty
  }

  private var searchResults: [SettingsSearchItem] {
    SettingsSearchCatalog.items.filter { $0.matches(trimmedQuery) }
  }

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedTab) {
        ForEach(SettingsTab.allCases) { tab in
          Label(tab.title, systemImage: tab.systemImage)
            .tag(tab)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    } detail: {
      if isSearching {
        searchResultsView
      } else {
        tabContent(for: selectedTab ?? .general)
      }
    }
    .searchable(text: $searchText, placement: .sidebar, prompt: "Search Settings")
    .frame(
      minWidth: 720,
      idealWidth: 800,
      maxWidth: .infinity,
      minHeight: 560,
      idealHeight: 720,
      maxHeight: .infinity
    )
    .accessibilityIdentifier("settings.form")
    .onAppear {
      // Keep the search field from stealing focus when the window opens.
      DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .general:
      GeneralSettingsTab()
    case .accounts:
      AccountsSettingsTab()
    case .calendar:
      CalendarSettingsTab()
    case .issues:
      IssuesSettingsTab()
    case .notes:
      NotesSettingsTab()
    case .shortcuts:
      ShortcutsSettingsTab()
    }
  }

  @ViewBuilder
  private var searchResultsView: some View {
    if searchResults.isEmpty {
      ContentUnavailableView.search(text: trimmedQuery)
    } else {
      List {
        ForEach(SettingsTab.allCases) { tab in
          let matches = searchResults.filter { $0.tab == tab }
          if !matches.isEmpty {
            Section(tab.title) {
              ForEach(matches) { item in
                Button {
                  selectedTab = item.tab
                  searchText = ""
                } label: {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                    Text(item.section)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.search.result.\(item.id)")
              }
            }
          }
        }
      }
      .accessibilityIdentifier("settings.search.results")
    }
  }
}

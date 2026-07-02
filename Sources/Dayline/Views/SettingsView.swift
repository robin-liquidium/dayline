import SwiftUI

/// Native settings view for refresh cadence and menu behavior.
struct SettingsView: View {
  @EnvironmentObject private var store: StatusStore

  /// Supported refresh cadence choices in minutes.
  private let cadenceOptions = [5, 10, 15, 30, 60]

  /// Supported single-key copy shortcut choices.
  private let copyHotkeyOptions = ["c", "l", "k", "y"]

  /// Builds the settings form.
  var body: some View {
    Form {
      Picker("Refresh", selection: cadenceBinding) {
        ForEach(cadenceOptions, id: \.self) { minutes in
          Text(label(for: minutes)).tag(minutes)
        }
      }
      .accessibilityIdentifier("settings.refreshCadence")

      Picker("Copy issue link", selection: copyHotkeyBinding) {
        ForEach(copyHotkeyOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }
      .accessibilityIdentifier("settings.copyIssueHotkey")

      Picker("Linear issues", selection: linearIssueOrderBinding) {
        ForEach(LinearIssueOrder.allCases) { order in
          Text(order.label).tag(order)
        }
      }
      .accessibilityIdentifier("settings.linearIssueOrder")
    }
    .formStyle(.columns)
    .padding(28)
    .frame(minWidth: 460)
    .accessibilityIdentifier("settings.form")
  }

  /// Binding that forwards settings changes to the store.
  private var cadenceBinding: Binding<Int> {
    Binding(
      get: { store.refreshIntervalMinutes },
      set: { store.setRefreshInterval(minutes: $0) }
    )
  }

  /// Binding that forwards copy hotkey changes to the store.
  private var copyHotkeyBinding: Binding<String> {
    Binding(
      get: { store.copyIssueHotkey },
      set: { store.setCopyIssueHotkey($0) }
    )
  }

  /// Binding that forwards Linear ordering changes to the store.
  private var linearIssueOrderBinding: Binding<LinearIssueOrder> {
    Binding(
      get: { store.linearIssueOrder },
      set: { store.setLinearIssueOrder($0) }
    )
  }

  /// Returns the menu label for a cadence option.
  private func label(for minutes: Int) -> String {
    minutes == 60 ? "Every hour" : "Every \(minutes) minutes"
  }
}

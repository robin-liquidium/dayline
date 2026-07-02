import SwiftUI

/// Native settings view for refresh cadence and menu behavior.
struct SettingsView: View {
  @EnvironmentObject private var store: StatusStore

  /// Supported refresh cadence choices in minutes.
  private let cadenceOptions = [5, 10, 15, 30, 60]

  /// Supported pre-meeting menu bar title lead choices in minutes.
  private let menuBarLeadTimeOptions = [0, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

  /// Supported post-start menu bar title grace choices in minutes.
  private let menuBarPostStartGraceOptions = [0, 1, 2, 5, 10, 15, 20, 25, 30]

  /// Supported single-key copy shortcut choices.
  private let copyHotkeyOptions = ["c", "l", "k", "y"]

  /// Supported single-key status picker shortcut choices.
  private let statusPickerHotkeyOptions = ["s", "w", "d", "u"]

  /// Supported single-key priority picker shortcut choices.
  private let priorityPickerHotkeyOptions = ["p", "r", "i", "o"]

  /// Builds the settings form.
  var body: some View {
    Form {
      Picker("Refresh", selection: cadenceBinding) {
        ForEach(cadenceOptions, id: \.self) { minutes in
          Text(label(for: minutes)).tag(minutes)
        }
      }
      .accessibilityIdentifier("settings.refreshCadence")

      Picker("Show event title before event start", selection: menuBarLeadTimeBinding) {
        ForEach(menuBarLeadTimePickerOptions, id: \.self) { minutes in
          Text(minutesLabel(for: minutes)).tag(minutes)
        }
      }
      .accessibilityIdentifier("settings.menuBarEventLeadTime")

      Picker("Show event title after event start", selection: menuBarPostStartGraceBinding) {
        ForEach(menuBarPostStartGracePickerOptions, id: \.self) { minutes in
          Text(minutesLabel(for: minutes)).tag(minutes)
        }
      }
      .accessibilityIdentifier("settings.menuBarEventPostStartGrace")

      Picker("Copy issue link", selection: copyHotkeyBinding) {
        ForEach(copyHotkeyOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }
      .accessibilityIdentifier("settings.copyIssueHotkey")

      Picker("Change issue status", selection: statusPickerHotkeyBinding) {
        ForEach(statusPickerHotkeyPickerOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }
      .accessibilityIdentifier("settings.statusPickerHotkey")

      Picker("Change issue priority", selection: priorityPickerHotkeyBinding) {
        ForEach(priorityPickerHotkeyPickerOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }
      .accessibilityIdentifier("settings.priorityPickerHotkey")

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

  /// Binding that forwards menu bar pre-meeting window changes to the store.
  private var menuBarLeadTimeBinding: Binding<Int> {
    Binding(
      get: { store.menuBarEventLeadTimeMinutes },
      set: { store.setMenuBarEventLeadTime(minutes: $0) }
    )
  }

  /// Binding that forwards menu bar post-start window changes to the store.
  private var menuBarPostStartGraceBinding: Binding<Int> {
    Binding(
      get: { store.menuBarEventPostStartGraceMinutes },
      set: { store.setMenuBarEventPostStartGrace(minutes: $0) }
    )
  }

  /// Lead time choices plus any existing custom stored value.
  private var menuBarLeadTimePickerOptions: [Int] {
    Array(Set(menuBarLeadTimeOptions + [store.menuBarEventLeadTimeMinutes])).sorted()
  }

  /// Post-start choices plus any existing custom stored value.
  private var menuBarPostStartGracePickerOptions: [Int] {
    Array(Set(menuBarPostStartGraceOptions + [store.menuBarEventPostStartGraceMinutes])).sorted()
  }

  /// Binding that forwards copy hotkey changes to the store.
  private var copyHotkeyBinding: Binding<String> {
    Binding(
      get: { store.copyIssueHotkey },
      set: { store.setCopyIssueHotkey($0) }
    )
  }

  /// Binding that forwards status picker hotkey changes to the store.
  private var statusPickerHotkeyBinding: Binding<String> {
    Binding(
      get: { store.statusPickerHotkey },
      set: { store.setStatusPickerHotkey($0) }
    )
  }

  /// Binding that forwards priority picker hotkey changes to the store.
  private var priorityPickerHotkeyBinding: Binding<String> {
    Binding(
      get: { store.priorityPickerHotkey },
      set: { store.setPriorityPickerHotkey($0) }
    )
  }

  /// Status picker choices plus any existing custom stored value.
  private var statusPickerHotkeyPickerOptions: [String] {
    pickerOptions(statusPickerHotkeyOptions, including: store.statusPickerHotkey)
  }

  /// Priority picker choices plus any existing custom stored value.
  private var priorityPickerHotkeyPickerOptions: [String] {
    pickerOptions(priorityPickerHotkeyOptions, including: store.priorityPickerHotkey)
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

  /// Returns a compact label for a minute-based menu bar title setting.
  private func minutesLabel(for minutes: Int) -> String {
    minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }

  /// Preserves curated picker order while keeping an existing custom value visible.
  private func pickerOptions(_ options: [String], including currentValue: String) -> [String] {
    options.contains(currentValue) ? options : options + [currentValue]
  }
}

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

  /// Supported default note counts.
  private let defaultNoteCountOptions = [3, 5, 10, 15]

  /// Supported single-key copy shortcut choices.
  private let copyHotkeyOptions = ["c", "l", "k", "y"]

  /// Supported single-key status picker shortcut choices.
  private let statusPickerHotkeyOptions = ["s", "w", "d", "u"]

  /// Supported single-key priority picker shortcut choices.
  private let priorityPickerHotkeyOptions = ["p", "r", "i", "o"]

  /// Width used for the right-aligned setting labels.
  private let labelColumnWidth: CGFloat = 150

  /// Width used for popup controls in the value column.
  private let controlColumnWidth: CGFloat = 330

  /// Builds the settings form.
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      checkboxRow {
        Toggle("Launch at login", isOn: launchAtLoginBinding)
          .accessibilityIdentifier("settings.launchAtLogin")
      }

      if let launchAtLoginError = store.launchAtLoginError {
        valueColumnRow {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("settings.launchAtLoginError")
        }
      }

      settingsPicker("Refresh:", selection: cadenceBinding, accessibilityIdentifier: "settings.refreshCadence") {
        ForEach(cadenceOptions, id: \.self) { minutes in
          Text(label(for: minutes)).tag(minutes)
        }
      }

      settingsPicker("Show title before:", selection: menuBarLeadTimeBinding, accessibilityIdentifier: "settings.menuBarEventLeadTime") {
        ForEach(menuBarLeadTimePickerOptions, id: \.self) { minutes in
          Text(minutesLabel(for: minutes)).tag(minutes)
        }
      }

      settingsPicker("Show title after:", selection: menuBarPostStartGraceBinding, accessibilityIdentifier: "settings.menuBarEventPostStartGrace") {
        ForEach(menuBarPostStartGracePickerOptions, id: \.self) { minutes in
          Text(minutesLabel(for: minutes)).tag(minutes)
        }
      }

      Divider()
        .padding(.vertical, 2)

      settingsPicker("Copy issue link:", selection: copyHotkeyBinding, accessibilityIdentifier: "settings.copyIssueHotkey") {
        ForEach(copyHotkeyOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }

      settingsPicker("Change status:", selection: statusPickerHotkeyBinding, accessibilityIdentifier: "settings.statusPickerHotkey") {
        ForEach(statusPickerHotkeyPickerOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }

      settingsPicker("Change priority:", selection: priorityPickerHotkeyBinding, accessibilityIdentifier: "settings.priorityPickerHotkey") {
        ForEach(priorityPickerHotkeyPickerOptions, id: \.self) { hotkey in
          Text(hotkey.uppercased()).tag(hotkey)
        }
      }

      settingsPicker("Linear issues:", selection: linearIssueOrderBinding, accessibilityIdentifier: "settings.linearIssueOrder") {
        ForEach(LinearIssueOrder.allCases) { order in
          Text(order.label).tag(order)
        }
      }

      settingsPicker("Notes shown:", selection: defaultNoteCountBinding, accessibilityIdentifier: "settings.defaultNoteCount") {
        ForEach(defaultNoteCountPickerOptions, id: \.self) { count in
          Text("\(count)").tag(count)
        }
      }

      settingsPicker("Notes sort:", selection: localNoteSortOrderBinding, accessibilityIdentifier: "settings.localNoteSortOrder") {
        ForEach(LocalNoteSortOrder.allCases) { order in
          Text(order.label).tag(order)
        }
      }
    }
    .padding(.horizontal, 34)
    .padding(.vertical, 28)
    .frame(width: 600)
    .accessibilityIdentifier("settings.form")
    .onAppear {
      store.refreshLaunchAtLoginStatus()
    }
  }

  /// Builds one right-labeled popup row with a native macOS settings alignment.
  private func settingsPicker<SelectionValue: Hashable, Content: View>(
    _ title: String,
    selection: Binding<SelectionValue>,
    accessibilityIdentifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      settingLabel(title)

      Picker(title, selection: selection) {
        content()
      }
      .labelsHidden()
      .frame(width: controlColumnWidth, alignment: .leading)
      .accessibilityIdentifier(accessibilityIdentifier)
    }
  }

  /// Aligns a checkbox row to the value column used by popup controls.
  private func checkboxRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    valueColumnRow {
      content()
        .frame(width: controlColumnWidth, alignment: .leading)
    }
  }

  /// Places content in the value column without a visible label.
  private func valueColumnRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Spacer()
        .frame(width: labelColumnWidth)

      content()
    }
  }

  /// Produces a compact right-aligned macOS settings label.
  private func settingLabel(_ title: String) -> some View {
    Text(title)
      .frame(width: labelColumnWidth, alignment: .trailing)
      .foregroundStyle(.primary)
  }

  /// Binding that forwards launch-at-login changes to the store.
  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { store.launchAtLoginEnabled },
      set: { store.setLaunchAtLoginEnabled($0) }
    )
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

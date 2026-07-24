import SwiftUI

/// Hover hotkeys and global keyboard shortcut settings.
struct ShortcutsSettingsTab: View {
  @EnvironmentObject private var store: StatusStore
  @State private var globalShortcutError: String?

  /// Supported single-key copy shortcut choices.
  private let copyHotkeyOptions = ["c", "l", "k", "y"]

  /// Supported single-key status picker shortcut choices.
  private let statusPickerHotkeyOptions = ["s", "w", "d", "u"]

  /// Supported single-key priority picker shortcut choices.
  private let priorityPickerHotkeyOptions = ["p", "r", "i", "o"]

  /// Supported single-key due date picker shortcut choices.
  private let dueDatePickerHotkeyOptions = ["d", "e", "t", "x"]
  private let labelPickerHotkeyOptions = ["l", "f", "g", "b"]
  private let assigneePickerHotkeyOptions = ["a", "q", "v", "z"]

  var body: some View {
    Form {
      Section {
        Picker("Copy issue/meeting link", selection: copyHotkeyBinding) {
          ForEach(copyHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.copyIssueHotkey")

        Picker("Issue copy target", selection: linearCopyStyleBinding) {
          ForEach(LinearCopyStyle.allCases) { style in
            Text(style.label).tag(style)
          }
        }
        .accessibilityIdentifier("settings.linearCopyStyle")

        Picker("Change status", selection: statusPickerHotkeyBinding) {
          ForEach(statusPickerHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.statusPickerHotkey")

        Picker("Change priority", selection: priorityPickerHotkeyBinding) {
          ForEach(priorityPickerHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.priorityPickerHotkey")

        Picker("Change due date", selection: dueDatePickerHotkeyBinding) {
          ForEach(dueDatePickerHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.dueDatePickerHotkey")

        Picker("Change labels", selection: labelPickerHotkeyBinding) {
          ForEach(labelPickerHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.labelPickerHotkey")

        Picker("Change assignees", selection: assigneePickerHotkeyBinding) {
          ForEach(assigneePickerHotkeyPickerOptions, id: \.self) { hotkey in
            Text(hotkey.uppercased()).tag(hotkey)
          }
        }
        .accessibilityIdentifier("settings.assigneePickerHotkey")
      } header: {
        Label("Hover Shortcuts", systemImage: "cursorarrow.rays")
      } footer: {
        Text("Press the key while hovering an issue in the menu.")
      }

      Section {
        LabeledContent("New note") {
          ShortcutRecorderView(
            shortcut: store.newNoteShortcut,
            defaultShortcut: .newNoteDefault,
            accessibilityLabel: "New note shortcut"
          ) { candidate in
            recordNewNoteShortcut(candidate)
          }
        }
        .accessibilityIdentifier("settings.newNoteShortcut")

        LabeledContent("New Linear issue") {
          ShortcutRecorderView(
            shortcut: store.newLinearIssueShortcut,
            defaultShortcut: .newLinearIssueDefault,
            accessibilityLabel: "New Linear issue shortcut"
          ) { candidate in
            recordNewLinearIssueShortcut(candidate)
          }
        }
        .accessibilityIdentifier("settings.newLinearIssueShortcut")

        LabeledContent("New GitHub issue") {
          ShortcutRecorderView(
            shortcut: store.newGitHubIssueShortcut,
            defaultShortcut: .newGitHubIssueDefault,
            accessibilityLabel: "New GitHub issue shortcut"
          ) { candidate in
            recordNewGitHubIssueShortcut(candidate)
          }
        }
        .accessibilityIdentifier("settings.newGitHubIssueShortcut")

        LabeledContent("Open Google Calendar") {
          ShortcutRecorderView(
            shortcut: store.openGoogleCalendarShortcut,
            defaultShortcut: .openGoogleCalendarDefault,
            accessibilityLabel: "Open Google Calendar shortcut"
          ) { candidate in
            recordOpenGoogleCalendarShortcut(candidate)
          }
        }
        .accessibilityIdentifier("settings.openGoogleCalendarShortcut")
      } header: {
        Label("Global Shortcuts", systemImage: "globe")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Global shortcuts work from anywhere, even when Dayline is in the background.")
          if let error = globalShortcutError ?? store.globalShortcutError {
            Text(error)
              .accessibilityIdentifier("settings.globalShortcutError")
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Binding that forwards copy hotkey changes to the store.
  private var copyHotkeyBinding: Binding<String> {
    Binding(
      get: { store.copyIssueHotkey },
      set: { store.setCopyIssueHotkey($0) }
    )
  }

  /// Binding that forwards the copy-target choice to the store.
  private var linearCopyStyleBinding: Binding<LinearCopyStyle> {
    Binding(
      get: { store.linearCopyStyle },
      set: { store.setLinearCopyStyle($0) }
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

  /// Binding that forwards due date picker hotkey changes to the store.
  private var dueDatePickerHotkeyBinding: Binding<String> {
    Binding(
      get: { store.dueDatePickerHotkey },
      set: { store.setDueDatePickerHotkey($0) }
    )
  }

  private var labelPickerHotkeyBinding: Binding<String> {
    Binding(get: { store.labelPickerHotkey }, set: { store.setLabelPickerHotkey($0) })
  }

  private var assigneePickerHotkeyBinding: Binding<String> {
    Binding(get: { store.assigneePickerHotkey }, set: { store.setAssigneePickerHotkey($0) })
  }

  /// Persists a recorded new-note shortcut unless it collides with another global shortcut.
  private func recordNewNoteShortcut(_ candidate: GlobalShortcut) {
    recordShortcut(candidate, excluding: store.newNoteShortcut) { store.setNewNoteShortcut($0) }
  }

  /// Persists a recorded new-issue shortcut unless it collides with another global shortcut.
  private func recordNewLinearIssueShortcut(_ candidate: GlobalShortcut) {
    recordShortcut(candidate, excluding: store.newLinearIssueShortcut) { store.setNewLinearIssueShortcut($0) }
  }

  /// Persists the Google Calendar shortcut unless it collides with another global shortcut.
  private func recordOpenGoogleCalendarShortcut(_ candidate: GlobalShortcut) {
    recordShortcut(candidate, excluding: store.openGoogleCalendarShortcut) { store.setOpenGoogleCalendarShortcut($0) }
  }

  /// Persists the GitHub issue shortcut unless it collides with another global shortcut.
  private func recordNewGitHubIssueShortcut(_ candidate: GlobalShortcut) {
    recordShortcut(candidate, excluding: store.newGitHubIssueShortcut) { store.setNewGitHubIssueShortcut($0) }
  }

  /// Rejects candidates already bound to another global shortcut, otherwise persists via `apply`.
  private func recordShortcut(
    _ candidate: GlobalShortcut,
    excluding current: GlobalShortcut,
    apply: (GlobalShortcut) -> Bool
  ) {
    let others = [
      store.newNoteShortcut,
      store.newLinearIssueShortcut,
      store.openGoogleCalendarShortcut,
      store.newGitHubIssueShortcut
    ].filter { $0 != current }
    guard !others.contains(candidate) else {
      globalShortcutError = "\(candidate.displayString) is already used by another global shortcut."
      return
    }
    globalShortcutError = nil
    _ = apply(candidate)
  }

  /// Status picker choices plus any existing custom stored value.
  private var statusPickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      statusPickerHotkeyOptions,
      currentValue: store.statusPickerHotkey,
      usedValues: [store.copyIssueHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey, store.labelPickerHotkey, store.assigneePickerHotkey]
    )
  }

  /// Priority picker choices plus any existing custom stored value.
  private var priorityPickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      priorityPickerHotkeyOptions,
      currentValue: store.priorityPickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.dueDatePickerHotkey, store.labelPickerHotkey, store.assigneePickerHotkey]
    )
  }

  /// Due date picker choices plus any existing custom stored value.
  private var dueDatePickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      dueDatePickerHotkeyOptions,
      currentValue: store.dueDatePickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.priorityPickerHotkey, store.labelPickerHotkey, store.assigneePickerHotkey]
    )
  }

  /// Copy shortcut choices that are not already assigned to another hover action.
  private var copyHotkeyPickerOptions: [String] {
    availablePickerOptions(
      copyHotkeyOptions,
      currentValue: store.copyIssueHotkey,
      usedValues: [store.statusPickerHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey, store.labelPickerHotkey, store.assigneePickerHotkey]
    )
  }

  private var labelPickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      labelPickerHotkeyOptions,
      currentValue: store.labelPickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey, store.assigneePickerHotkey]
    )
  }

  private var assigneePickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      assigneePickerHotkeyOptions,
      currentValue: store.assigneePickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey, store.labelPickerHotkey]
    )
  }

  /// Preserves curated picker order while keeping an existing custom value visible.
  private func pickerOptions(_ options: [String], including currentValue: String) -> [String] {
    options.contains(currentValue) ? options : options + [currentValue]
  }

  /// Keeps the current value visible while excluding keys assigned to other hover actions.
  private func availablePickerOptions(
    _ options: [String],
    currentValue: String,
    usedValues: [String]
  ) -> [String] {
    pickerOptions(options, including: currentValue).filter {
      $0 == currentValue || !usedValues.contains($0)
    }
  }
}

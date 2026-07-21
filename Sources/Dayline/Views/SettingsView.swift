import SwiftUI

/// Native settings view for refresh cadence and menu behavior.
struct SettingsView: View {
  @EnvironmentObject private var store: StatusStore
  @EnvironmentObject private var updateService: UpdateService
  @State private var isShowingFeedback = false
  @State private var linearCreateTeams: [LinearTeamOption] = []
  @State private var linearCreateProjects: [LinearProjectOption] = []
  @State private var linearCreateLabels: [LinearLabelOption] = []
  @State private var isLoadingLinearCreateDefaults = false
  @State private var linearCreateDefaultsError: String?
  @State private var globalShortcutError: String?

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

  /// Supported single-key due date picker shortcut choices.
  private let dueDatePickerHotkeyOptions = ["d", "e", "t", "x"]

  /// Builds the settings form.
  var body: some View {
    Form {
      Section {
        accountsSection
      } header: {
        Label("Accounts", systemImage: "person.crop.circle")
      }

      Section {
        Toggle("Launch at login", isOn: launchAtLoginBinding)
          .accessibilityIdentifier("settings.launchAtLogin")

        Toggle("Install updates automatically", isOn: automaticUpdatesBinding)
          .accessibilityIdentifier("settings.automaticUpdates")

        Picker("Refresh", selection: cadenceBinding) {
          ForEach(cadenceOptions, id: \.self) { minutes in
            Text(label(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.refreshCadence")
      } header: {
        Label("General", systemImage: "gearshape")
      } footer: {
        if let launchAtLoginError = store.launchAtLoginError {
          Text(launchAtLoginError)
            .accessibilityIdentifier("settings.launchAtLoginError")
        }
      }

      Section {
        Picker("Show title before", selection: menuBarLeadTimeBinding) {
          ForEach(menuBarLeadTimePickerOptions, id: \.self) { minutes in
            Text(minutesLabel(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.menuBarEventLeadTime")

        Picker("Show title after", selection: menuBarPostStartGraceBinding) {
          ForEach(menuBarPostStartGracePickerOptions, id: \.self) { minutes in
            Text(minutesLabel(for: minutes)).tag(minutes)
          }
        }
        .accessibilityIdentifier("settings.menuBarEventPostStartGrace")
      } header: {
        Label("Menu Bar", systemImage: "menubar.rectangle")
      }

      Section {
        Toggle("Show calendar names", isOn: showsCalendarSourceNamesBinding)
          .accessibilityIdentifier("settings.showsCalendarSourceNames")
      } header: {
        Label("Calendar", systemImage: "calendar")
      }

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
      } header: {
        Label("Shortcuts", systemImage: "keyboard")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("Press the key while hovering an issue in the menu. New note and new issue shortcuts work from anywhere.")
          if let error = globalShortcutError ?? store.globalShortcutError {
            Text(error)
              .accessibilityIdentifier("settings.globalShortcutError")
          }
        }
      }

      Section {
        Picker("Default team", selection: linearCreateDefaultTeamBinding) {
          if linearCreateTeams.isEmpty {
            Text(isLoadingLinearCreateDefaults ? "Loading..." : "Unavailable")
              .tag(store.linearIssueCreateDefaultTeamID)
          } else {
            ForEach(linearCreateTeams) { team in
              Text(team.label).tag(team.id)
            }
          }
        }
        .disabled(linearCreateTeams.isEmpty)
        .accessibilityIdentifier("settings.linearCreateDefaultTeam")

        LabeledContent("Default status") {
          ColoredMenuPicker(
            selection: linearCreateDefaultStateBinding,
            items: linearCreateDefaultStatusOptions.map { state in
              ColoredMenuPickerItem(
                tag: state.id,
                title: state.name,
                symbolName: statusIcon(for: state),
                color: statusColor(for: state)
              )
            },
            isEnabled: !linearCreateDefaultStatusOptions.isEmpty
          )
        }
        .accessibilityIdentifier("settings.linearCreateDefaultStatus")

        LabeledContent("Default priority") {
          ColoredMenuPicker(
            selection: linearCreateDefaultPriorityTagBinding,
            items: LinearPriorityOption.allCases.map { priority in
              ColoredMenuPickerItem(
                tag: String(priority.value),
                title: priority.label,
                symbolName: priorityStyle(for: priority).systemImage,
                color: priorityStyle(for: priority).color
              )
            }
          )
        }
        .accessibilityIdentifier("settings.linearCreateDefaultPriority")

        Picker("Default project", selection: linearCreateDefaultProjectBinding) {
          Text("None").tag("")
          ForEach(linearCreateProjects) { project in
            Text(project.label).tag(project.id)
          }
        }
        .accessibilityIdentifier("settings.linearCreateDefaultProject")

        LabeledContent("Default label") {
          ColoredMenuPicker(
            selection: linearCreateDefaultLabelBinding,
            items: [ColoredMenuPickerItem(tag: "", title: "None", symbolName: nil, color: .secondary)]
              + linearCreateLabels.map { label in
                ColoredMenuPickerItem(
                  tag: label.id,
                  title: label.label,
                  symbolName: "circle.fill",
                  color: Color(linearHex: label.color)
                )
              }
          )
        }
        .accessibilityIdentifier("settings.linearCreateDefaultLabel")

        Picker("Issue order", selection: linearIssueOrderBinding) {
          ForEach(LinearIssueOrder.allCases) { order in
            Text(order.label).tag(order)
          }
        }
        .accessibilityIdentifier("settings.linearIssueOrder")
      } header: {
        Label("Linear", systemImage: "checklist")
      } footer: {
        if let linearCreateDefaultsError {
          Text(linearCreateDefaultsError)
            .accessibilityIdentifier("settings.linearCreateDefaultsError")
        }
      }

      Section {
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
        Label("Notes", systemImage: "note.text")
      }

      Section {
        Button("Submit Feedback...") {
          isShowingFeedback = true
        }
        .accessibilityIdentifier("settings.submitFeedback")
      } header: {
        Label("Feedback", systemImage: "text.bubble")
      } footer: {
        Text("Feedback is submitted anonymously as a public GitHub issue.")
      }
    }
    .formStyle(.grouped)
    .frame(
      minWidth: 560,
      idealWidth: 600,
      maxWidth: .infinity,
      minHeight: 640,
      idealHeight: 860,
      maxHeight: .infinity
    )
    .accessibilityIdentifier("settings.form")
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackView()
    }
    .onAppear {
      store.refreshLaunchAtLoginStatus()
    }
    .task(id: isLinearConnected) {
      guard isLinearConnected else {
        linearCreateTeams = []
        linearCreateProjects = []
        linearCreateLabels = []
        linearCreateDefaultsError = nil
        return
      }
      await loadLinearCreateDefaults()
    }
  }

  /// Whether Linear is ready for authenticated settings requests.
  private var isLinearConnected: Bool {
    store.connectionStatuses.first(where: { $0.provider == .linear })?.isConnected == true
  }

  /// Connected-account rows for Google and Linear.
  @ViewBuilder
  private var accountsSection: some View {
    if store.googleAccounts.isEmpty {
      Text("No Google accounts linked")
        .foregroundStyle(.secondary)
    } else {
      ForEach(store.googleAccounts) { status in
        GoogleAccountSettingsRow(status: status)
      }
    }

    Button {
      Task { await store.addGoogleAccount() }
    } label: {
      Label("Add Google Account", systemImage: "plus")
    }
    .disabled(!store.canAddGoogleAccount || !AuthProvider.google.isConfigured)
    .accessibilityIdentifier("settings.account.google.add")

    if store.isGoogleAuthorizationInProgress {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Finish sign-in in your browser.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else if let error = store.googleAuthorizationError {
      Text(error)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("settings.account.google.error")
    }

    if let linearStatus = store.connectionStatuses.first(where: { $0.provider == .linear }) {
      accountRow(linearStatus)
    }
  }

  /// Builds one account connection row with a connect/disconnect action.
  private func accountRow(_ status: ConnectionStatus) -> some View {
    HStack(spacing: 12) {
      Text(status.provider.title)

      Spacer(minLength: 0)

      Text(accountStateLabel(status))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      if status.state == .checking || status.state == .connecting {
        ProgressView()
          .controlSize(.small)
      } else if status.isConnected {
        Button("Disconnect") {
          Task { await store.disconnect(status.provider) }
        }
      } else {
        Button("Connect") {
          Task { await store.connect(status.provider) }
        }
        .disabled(!status.provider.isConfigured)
      }
    }
    .accessibilityIdentifier("settings.account.\(status.provider.id)")
  }

  /// Compact state label for one account row.
  private func accountStateLabel(_ status: ConnectionStatus) -> String {
    switch status.state {
    case .checking:
      "Checking..."
    case .disconnected:
      status.detail ?? "Not connected"
    case .connecting:
      status.detail ?? "Connecting..."
    case .connected:
      if let accountLabel = status.accountLabel, !accountLabel.isEmpty {
        accountLabel
      } else {
        "Connected"
      }
    }
  }

  /// Binding that forwards launch-at-login changes to the store.
  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { store.launchAtLoginEnabled },
      set: { store.setLaunchAtLoginEnabled($0) }
    )
  }

  /// Binding that persists the automatic-update preference.
  private var automaticUpdatesBinding: Binding<Bool> {
    Binding(
      get: { updateService.automaticallyInstallsUpdates },
      set: { updateService.setAutomaticallyInstallsUpdates($0) }
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

  /// Binding that persists whether event rows show source calendar names.
  private var showsCalendarSourceNamesBinding: Binding<Bool> {
    Binding(
      get: { store.showsCalendarSourceNames },
      set: { store.setShowsCalendarSourceNames($0) }
    )
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

  /// Persists a recorded new-note shortcut unless it collides with the issue shortcut.
  private func recordNewNoteShortcut(_ candidate: GlobalShortcut) {
    guard candidate != store.newLinearIssueShortcut else {
      globalShortcutError = "\(candidate.displayString) is already used for new Linear issues."
      return
    }
    globalShortcutError = nil
    _ = store.setNewNoteShortcut(candidate)
  }

  /// Persists a recorded new-issue shortcut unless it collides with the note shortcut.
  private func recordNewLinearIssueShortcut(_ candidate: GlobalShortcut) {
    guard candidate != store.newNoteShortcut else {
      globalShortcutError = "\(candidate.displayString) is already used for new notes."
      return
    }
    globalShortcutError = nil
    _ = store.setNewLinearIssueShortcut(candidate)
  }

  /// Status picker choices plus any existing custom stored value.
  private var statusPickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      statusPickerHotkeyOptions,
      currentValue: store.statusPickerHotkey,
      usedValues: [store.copyIssueHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey]
    )
  }

  /// Priority picker choices plus any existing custom stored value.
  private var priorityPickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      priorityPickerHotkeyOptions,
      currentValue: store.priorityPickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.dueDatePickerHotkey]
    )
  }

  /// Due date picker choices plus any existing custom stored value.
  private var dueDatePickerHotkeyPickerOptions: [String] {
    availablePickerOptions(
      dueDatePickerHotkeyOptions,
      currentValue: store.dueDatePickerHotkey,
      usedValues: [store.copyIssueHotkey, store.statusPickerHotkey, store.priorityPickerHotkey]
    )
  }

  /// Copy shortcut choices that are not already assigned to another hover action.
  private var copyHotkeyPickerOptions: [String] {
    availablePickerOptions(
      copyHotkeyOptions,
      currentValue: store.copyIssueHotkey,
      usedValues: [store.statusPickerHotkey, store.priorityPickerHotkey, store.dueDatePickerHotkey]
    )
  }

  /// Binding that forwards Linear ordering changes to the store.
  private var linearIssueOrderBinding: Binding<LinearIssueOrder> {
    Binding(
      get: { store.linearIssueOrder },
      set: { store.setLinearIssueOrder($0) }
    )
  }

  /// Status choices belonging to the currently configured default team.
  private var linearCreateDefaultStatusOptions: [LinearWorkflowState] {
    linearCreateTeams.first { $0.id == store.linearIssueCreateDefaultTeamID }?.states ?? []
  }

  /// Binding that persists the default team and repairs team-scoped selections.
  private var linearCreateDefaultTeamBinding: Binding<String> {
    Binding(
      get: { store.linearIssueCreateDefaultTeamID },
      set: { teamID in
        store.setLinearIssueCreateDefaultTeamID(teamID)
        guard let team = linearCreateTeams.first(where: { $0.id == teamID }) else { return }
        let state = team.states.first(where: { $0.type == "unstarted" }) ?? team.states.first
        store.setLinearIssueCreateDefaultStateID(state?.id ?? "")
        Task { await loadLinearCreateLabels() }
      }
    )
  }

  /// Binding that persists the default status for newly created Linear issues.
  private var linearCreateDefaultStateBinding: Binding<String> {
    Binding(
      get: { store.linearIssueCreateDefaultStateID },
      set: { store.setLinearIssueCreateDefaultStateID($0) }
    )
  }

  /// Binding that persists the default priority as a menu tag string.
  private var linearCreateDefaultPriorityTagBinding: Binding<String> {
    Binding(
      get: { String(store.linearIssueCreateDefaultPriority) },
      set: { store.setLinearIssueCreateDefaultPriority(Int($0) ?? 0) }
    )
  }

  /// Binding that persists the default project for newly created Linear issues.
  private var linearCreateDefaultProjectBinding: Binding<String> {
    Binding(
      get: { store.linearIssueCreateDefaultProjectID },
      set: { store.setLinearIssueCreateDefaultProjectID($0) }
    )
  }

  /// Binding that persists the default label for newly created Linear issues.
  private var linearCreateDefaultLabelBinding: Binding<String> {
    Binding(
      get: { store.linearIssueCreateDefaultLabelID },
      set: { store.setLinearIssueCreateDefaultLabelID($0) }
    )
  }

  /// Loads Linear's team-scoped defaults and repairs stale saved IDs.
  private func loadLinearCreateDefaults() async {
    guard linearCreateTeams.isEmpty, !isLoadingLinearCreateDefaults else { return }
    isLoadingLinearCreateDefaults = true
    defer { isLoadingLinearCreateDefaults = false }

    do {
      linearCreateTeams = try await store.linearIssueCreateTeamOptions()
      guard let team = linearCreateTeams.first(where: {
        $0.id == store.linearIssueCreateDefaultTeamID
      }) ?? linearCreateTeams.first else {
        linearCreateDefaultsError = "No Linear teams are available."
        return
      }

      if store.linearIssueCreateDefaultTeamID != team.id {
        store.setLinearIssueCreateDefaultTeamID(team.id)
      }

      if !team.states.contains(where: { $0.id == store.linearIssueCreateDefaultStateID }) {
        let state = team.states.first(where: { $0.type == "unstarted" }) ?? team.states.first
        store.setLinearIssueCreateDefaultStateID(state?.id ?? "")
      }

      if !LinearPriorityOption.allCases.contains(where: {
        $0.value == store.linearIssueCreateDefaultPriority
      }) {
        store.setLinearIssueCreateDefaultPriority(0)
      }
      linearCreateDefaultsError = nil
    } catch {
      linearCreateDefaultsError = error.localizedDescription.compactLine(limit: 160)
    }

    do {
      linearCreateProjects = try await store.linearIssueCreateProjectOptions()
      if !store.linearIssueCreateDefaultProjectID.isEmpty,
         !linearCreateProjects.contains(where: { $0.id == store.linearIssueCreateDefaultProjectID }) {
        store.setLinearIssueCreateDefaultProjectID("")
      }
    } catch {
      linearCreateDefaultsError = linearCreateDefaultsError
        ?? error.localizedDescription.compactLine(limit: 160)
    }

    await loadLinearCreateLabels()
  }

  /// Loads the labels of the configured default team and repairs a stale selection.
  private func loadLinearCreateLabels() async {
    let teamID = store.linearIssueCreateDefaultTeamID
    guard !teamID.isEmpty else {
      linearCreateLabels = []
      return
    }

    do {
      let labels = try await store.linearIssueCreateLabelOptions(teamID: teamID)
      guard store.linearIssueCreateDefaultTeamID == teamID else { return }
      linearCreateLabels = labels
      if !store.linearIssueCreateDefaultLabelID.isEmpty,
         !linearCreateLabels.contains(where: { $0.id == store.linearIssueCreateDefaultLabelID }) {
        store.setLinearIssueCreateDefaultLabelID("")
      }
    } catch {
      guard store.linearIssueCreateDefaultTeamID == teamID else { return }
      linearCreateLabels = []
      linearCreateDefaultsError = linearCreateDefaultsError
        ?? error.localizedDescription.compactLine(limit: 160)
    }
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

  /// Returns a semantic symbol for a workflow state.
  private func statusIcon(for state: LinearWorkflowState) -> String {
    switch state.type {
    case "completed":
      "checkmark.circle.fill"
    case "started":
      "play.circle.fill"
    case "canceled":
      "xmark.circle.fill"
    case "backlog":
      "ellipsis.circle"
    default:
      "circle"
    }
  }

  /// Returns a semantic color for a workflow state.
  private func statusColor(for state: LinearWorkflowState) -> Color {
    switch state.type {
    case "completed":
      .blue
    case "started":
      .yellow
    case "canceled":
      .red
    default:
      .secondary
    }
  }

  /// Visual style for a Linear priority option.
  private func priorityStyle(for priority: LinearPriorityOption) -> (systemImage: String, color: Color) {
    switch priority.value {
    case 1:
      ("exclamationmark.square.fill", .orange)
    case 2:
      ("arrow.up.circle.fill", .orange)
    case 3:
      ("equal.circle.fill", .yellow)
    case 4:
      ("arrow.down.circle.fill", .secondary)
    default:
      ("ellipsis.circle", .secondary)
    }
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

/// One linked Google account with an inline calendar picker.
private struct GoogleAccountSettingsRow: View {
  @EnvironmentObject private var store: StatusStore
  @State private var isExpanded = false

  let status: GoogleAccountStatus

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 7) {
        if status.account.calendars.isEmpty {
          Text("Calendars will appear after this account connects.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(status.account.calendars) { calendar in
            Toggle(isOn: calendarBinding(calendar)) {
              HStack(spacing: 6) {
                Text(calendar.name)
                  .lineLimit(1)
                if calendar.isPrimary {
                  Text("Primary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier(
              "settings.account.google.\(status.id.uuidString).calendar.\(calendar.id)"
            )
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 6)
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(status.account.label)
            .lineLimit(1)
            .accessibilityIdentifier("settings.account.google.\(status.id.uuidString)")

          if let detail = status.detail, !detail.isEmpty {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          } else {
            Text(calendarCountLabel)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        accountAction

        Button("Disconnect", role: .destructive) {
          Task { await store.disconnectGoogleAccount(status.id) }
        }
        .disabled(store.isGoogleAuthorizationInProgress || status.state == .connecting)
        .accessibilityIdentifier("settings.account.google.\(status.id.uuidString).disconnect")
      }
    }
  }

  @ViewBuilder
  private var accountAction: some View {
    switch status.state {
    case .checking, .connecting:
      ProgressView()
        .controlSize(.small)
    case .disconnected:
      Button("Reconnect") {
        Task { await store.reconnectGoogleAccount(status.id) }
      }
      .disabled(store.isGoogleAuthorizationInProgress)
      .accessibilityIdentifier("settings.account.google.\(status.id.uuidString).reconnect")
    case .connected:
      EmptyView()
    }
  }

  private var calendarCountLabel: String {
    let enabledCount = status.account.calendars.filter(\.isEnabled).count
    let totalCount = status.account.calendars.count
    return "\(enabledCount) of \(totalCount) calendars enabled"
  }

  private func calendarBinding(_ calendar: GoogleCalendarSource) -> Binding<Bool> {
    Binding(
      get: { calendar.isEnabled },
      set: {
        store.setGoogleCalendarEnabled(
          accountID: status.id,
          calendarID: calendar.id,
          isEnabled: $0
        )
      }
    )
  }
}

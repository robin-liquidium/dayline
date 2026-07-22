import SwiftUI

/// Stock SwiftUI window for creating a Linear issue through the API.
struct LinearIssueEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  @StateObject private var draft = LinearIssueDraft()
  @State private var isDueDatePickerPresented = false

  /// Builds the Linear issue creator window content.
  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Title", text: titleBinding, prompt: Text("Issue title"))
            .accessibilityIdentifier("linearEditor.title")

          Picker("Team", selection: teamBinding) {
            Text("Select team").tag("")
            ForEach(draft.teams) { team in
              Text(defaultAnnotatedLabel(team.label, isDefault: team.id == store.linearIssueCreateDefaultTeamID))
                .tag(team.id)
            }
          }
          .accessibilityIdentifier("linearEditor.team")

          LabeledContent("Status") {
            ColoredMenuPicker(
              selection: stateBinding,
              items: statusOptions.map { state in
                ColoredMenuPickerItem(
                  tag: state.id,
                  title: defaultAnnotatedLabel(
                    state.name,
                    isDefault: state.id == store.linearIssueCreateDefaultStateID
                      && draft.issue.team == store.linearIssueCreateDefaultTeamID
                  ),
                  symbolName: statusIcon(for: state),
                  color: statusColor(for: state)
                )
              },
              isEnabled: !statusOptions.isEmpty
            )
          }
          .accessibilityIdentifier("linearEditor.status")

          LabeledContent("Priority") {
            ColoredMenuPicker(
              selection: priorityTagBinding,
              items: createPriorityOptions.map { priority in
                ColoredMenuPickerItem(
                  tag: String(priority.value),
                  title: defaultAnnotatedLabel(
                    priority.label,
                    isDefault: priority.value == store.linearIssueCreateDefaultPriority
                  ),
                  symbolName: priorityStyle(for: priority).systemImage,
                  color: priorityStyle(for: priority).color
                )
              }
            )
          }
          .accessibilityIdentifier("linearEditor.priority")

          Picker("Assignee", selection: assigneeBinding) {
            Text("Me (self)").tag("self")
            Text("No assignee").tag("")
            ForEach(draft.assignees) { assignee in
              Text(assignee.label).tag(assignee.id)
            }
          }
          .accessibilityIdentifier("linearEditor.assignee")

          LabeledContent("Due") {
            dueDateControls
          }
        } header: {
          Label("Issue", systemImage: "square.and.pencil")
        }

        Section {
          TextEditor(text: descriptionBinding)
            .font(.body)
            .frame(minHeight: 110)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("linearEditor.description")
        } header: {
          Label("Description", systemImage: "text.alignleft")
        }

        Section {
          Picker("Estimate", selection: estimateBinding) {
            Text("None").tag(-1)
            ForEach(estimateOptions) { option in
              Text(option.label).tag(option.value)
            }
          }
          .disabled(estimateOptions.isEmpty)
          .accessibilityIdentifier("linearEditor.estimate")

          Picker("Project", selection: projectBinding) {
            Text("None").tag("")
            ForEach(projectOptions) { project in
              Text(defaultAnnotatedLabel(
                project.label,
                isDefault: project.id == store.linearIssueCreateDefaultProjectID
              ))
              .tag(project.id)
            }
          }
          .accessibilityIdentifier("linearEditor.project")

          Picker("Milestone", selection: milestoneBinding) {
            Text("None").tag("")
            ForEach(draft.milestones) { milestone in
              Text(milestone.label).tag(milestone.id)
            }
          }
          .disabled(draft.issue.project.isEmpty)
          .accessibilityIdentifier("linearEditor.milestone")

          Picker("Cycle", selection: cycleBinding) {
            Text("None").tag("")
            ForEach(draft.cycles) { cycle in
              Text(cycle.label).tag(cycle.id)
            }
          }
          .accessibilityIdentifier("linearEditor.cycle")

          LabeledContent("Label") {
            ColoredMenuPicker(
              selection: labelBinding,
              items: [ColoredMenuPickerItem(tag: "", title: "None", symbolName: nil, color: .secondary)]
                + draft.labels.map { label in
                  ColoredMenuPickerItem(
                    tag: label.id,
                    title: defaultAnnotatedLabel(
                      label.label,
                      isDefault: label.id == store.linearIssueCreateDefaultLabelID
                    ),
                    symbolName: "circle.fill",
                    color: Color(linearHex: label.color)
                  )
                }
            )
          }
          .accessibilityIdentifier("linearEditor.labels")

          TextField("Parent", text: parentBinding, prompt: Text("TEAM-123"))
            .accessibilityIdentifier("linearEditor.parent")
        } header: {
          Label("Advanced", systemImage: "slider.horizontal.3")
        }
        .accessibilityIdentifier("linearEditor.advanced")
      }
      .formStyle(.grouped)

      if let errorMessage = draft.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
          .padding(.bottom, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("linearEditor.error")
      }

      Divider()

      HStack {
        if draft.isLoadingOptions {
          ProgressView()
            .controlSize(.small)
            .accessibilityIdentifier("linearEditor.loading")
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("linearEditor.cancel")

        Button(saveButtonTitle) {
          Task { await createIssue() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .accessibilityIdentifier("linearEditor.create")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(minWidth: 560, idealWidth: 600, minHeight: 640, idealHeight: 780)
    .task {
      await loadOptionsIfNeeded()
    }
    .onChange(of: draft.issue.team) { _, _ in
      pruneStateSelection()
      pruneProjectSelection()
      pruneEstimateSelection()
      Task { await loadTeamExtras() }
    }
    .onChange(of: draft.issue.project) { _, _ in
      Task { await loadMilestones() }
    }
  }

  /// Due date controls for the due row.
  @ViewBuilder
  private var dueDateControls: some View {
    if draft.issue.dueDate != nil {
      HStack(spacing: 6) {
        Button {
          isDueDatePickerPresented.toggle()
        } label: {
          if let dueDate = draft.issue.dueDate {
            Text(dueDate, format: .dateTime.year().month().day())
          }
        }
        .accessibilityIdentifier("linearEditor.dueDate")
        .popover(isPresented: $isDueDatePickerPresented, arrowEdge: .bottom) {
          GraphicalDatePicker(selection: dueDateBinding)
            .padding(8)
            .accessibilityIdentifier("linearEditor.dueDate.calendar")
        }

        Button {
          isDueDatePickerPresented = false
          draft.issue.dueDate = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Remove due date")
        .accessibilityLabel("Remove due date")
        .accessibilityIdentifier("linearEditor.dueDate.remove")
      }
    } else {
      Button {
        draft.issue.dueDate = Calendar.current.startOfDay(for: Date())
        isDueDatePickerPresented = true
      } label: {
        Label("Add due date", systemImage: "calendar")
      }
      .accessibilityIdentifier("linearEditor.dueDate.add")
    }
  }

  /// Title for the primary create action.
  private var saveButtonTitle: String {
    draft.isCreating ? "Creating..." : "Create"
  }

  /// Whether the current draft can create a Linear issue.
  private var canCreate: Bool {
    !draft.isCreating
      && !draft.issue.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !draft.issue.team.isEmpty
  }

  /// Workflow states for the selected team.
  private var statusOptions: [LinearWorkflowState] {
    selectedTeam?.states ?? []
  }

  /// Selected Linear team option.
  private var selectedTeam: LinearTeamOption? {
    draft.teams.first { $0.id == draft.issue.team }
  }

  /// Projects available for the selected team.
  private var projectOptions: [LinearProjectOption] {
    draft.projects.filter { $0.teamIDs.isEmpty || $0.teamIDs.contains(draft.issue.team) }
  }

  /// Estimate options for the selected team's estimation scale.
  private var estimateOptions: [LinearEstimateOption] {
    selectedTeam?.estimateOptions ?? []
  }

  /// Priority choices accepted by `linear issue create`.
  private var createPriorityOptions: [LinearPriorityOption] {
    LinearPriorityOption.allCases
  }

  /// Creates the issue and closes the window when Linear accepts it.
  private func createIssue() async {
    guard canCreate else {
      return
    }

    draft.isCreating = true
    draft.errorMessage = nil

    do {
      try await store.createLinearIssue(draft: draft.issue)
      dismiss()
    } catch {
      draft.errorMessage = error.localizedDescription.compactLine(limit: 160)
    }

    draft.isCreating = false
  }

  /// Loads team/project/user options once per editor lifetime.
  private func loadOptionsIfNeeded() async {
    guard !draft.hasLoadedOptions else {
      return
    }

    draft.hasLoadedOptions = true
    draft.isLoadingOptions = true
    defer { draft.isLoadingOptions = false }

    var optionLoadError: String?

    do {
      draft.teams = try await store.linearIssueCreateTeamOptions()
      let defaultTeam = draft.teams.first { $0.id == store.linearIssueCreateDefaultTeamID }
        ?? draft.teams.first
      if let defaultTeam, store.linearIssueCreateDefaultTeamID != defaultTeam.id {
        store.setLinearIssueCreateDefaultTeamID(defaultTeam.id)
      }
      draft.issue.team = defaultTeam?.id ?? ""
      let state = defaultState(for: defaultTeam)
      if let state, store.linearIssueCreateDefaultStateID != state.id {
        store.setLinearIssueCreateDefaultStateID(state.id)
      }
      draft.issue.state = state?.id ?? ""
      let hasValidPriority = LinearPriorityOption.allCases.contains {
        $0.value == store.linearIssueCreateDefaultPriority
      }
      if !hasValidPriority {
        store.setLinearIssueCreateDefaultPriority(0)
      }
      draft.issue.priority = hasValidPriority ? store.linearIssueCreateDefaultPriority : 0
    } catch {
      optionLoadError = error.localizedDescription.compactLine(limit: 160)
    }

    do {
      draft.assignees = try await store.linearIssueCreateAssigneeOptions()
    } catch {
      optionLoadError = optionLoadError ?? error.localizedDescription.compactLine(limit: 160)
    }

    do {
      draft.projects = try await store.linearIssueCreateProjectOptions()
      if projectOptions.contains(where: { $0.id == store.linearIssueCreateDefaultProjectID }) {
        draft.issue.project = store.linearIssueCreateDefaultProjectID
      }
    } catch {
      optionLoadError = optionLoadError ?? error.localizedDescription.compactLine(limit: 160)
    }

    draft.errorMessage = optionLoadError

    await loadTeamExtras()
    if draft.labels.contains(where: { $0.id == store.linearIssueCreateDefaultLabelID }) {
      draft.issue.label = store.linearIssueCreateDefaultLabelID
    }
    await loadMilestones()

  }

  /// Loads cycles and labels for the selected team and prunes stale selections.
  private func loadTeamExtras() async {
    let teamID = draft.issue.team
    guard !teamID.isEmpty else {
      draft.cycles = []
      draft.labels = []
      draft.issue.cycle = ""
      draft.issue.label = ""
      return
    }

    do {
      let cycles = try await store.linearIssueCreateCycleOptions(teamID: teamID)
      let labels = try await store.linearIssueCreateLabelOptions(teamID: teamID)
      guard draft.issue.team == teamID else { return }
      draft.cycles = cycles
      draft.labels = labels
      if !draft.cycles.contains(where: { $0.id == draft.issue.cycle }) {
        draft.issue.cycle = ""
      }
      if !draft.labels.contains(where: { $0.id == draft.issue.label }) {
        draft.issue.label = ""
      }
    } catch {
      guard draft.issue.team == teamID else { return }
      draft.cycles = []
      draft.labels = []
      draft.issue.cycle = ""
      draft.issue.label = ""
      draft.errorMessage = draft.errorMessage ?? error.localizedDescription.compactLine(limit: 160)
    }
  }

  /// Loads milestones for the selected project and prunes a stale selection.
  private func loadMilestones() async {
    let projectID = draft.issue.project
    guard !projectID.isEmpty else {
      draft.milestones = []
      draft.issue.milestone = ""
      return
    }

    do {
      let milestones = try await store.linearIssueCreateMilestoneOptions(projectID: projectID)
      guard draft.issue.project == projectID else { return }
      draft.milestones = milestones
      if !draft.milestones.contains(where: { $0.id == draft.issue.milestone }) {
        draft.issue.milestone = ""
      }
    } catch {
      guard draft.issue.project == projectID else { return }
      draft.milestones = []
      draft.issue.milestone = ""
      draft.errorMessage = draft.errorMessage ?? error.localizedDescription.compactLine(limit: 160)
    }
  }

  /// Selects a sensible status when the current choice is unavailable for the selected team.
  private func pruneStateSelection() {
    if !statusOptions.contains(where: { $0.id == draft.issue.state }) {
      draft.issue.state = defaultState(for: selectedTeam)?.id ?? ""
    }
  }

  /// Clears the selected project when it is unavailable for the selected team.
  private func pruneProjectSelection() {
    if !draft.issue.project.isEmpty,
       !projectOptions.contains(where: { $0.id == draft.issue.project }) {
      draft.issue.project = ""
    }
  }

  /// Clears the selected estimate when it is unavailable for the selected team.
  private func pruneEstimateSelection() {
    if let estimate = draft.issue.estimate,
       !estimateOptions.contains(where: { $0.value == estimate }) {
      draft.issue.estimate = nil
    }
  }

  /// Resolves the configured status for a team, then falls back to its native unstarted state.
  private func defaultState(for team: LinearTeamOption?) -> LinearWorkflowState? {
    guard let team else { return nil }
    if team.id == store.linearIssueCreateDefaultTeamID,
       let configured = team.states.first(where: { $0.id == store.linearIssueCreateDefaultStateID }) {
      return configured
    }
    return team.states.first(where: { $0.type == "unstarted" }) ?? team.states.first
  }

  /// Marks the configured value without replacing its useful human-readable label.
  private func defaultAnnotatedLabel(_ label: String, isDefault: Bool) -> String {
    isDefault ? "\(label) (Default)" : label
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

  /// Binding for the issue title field.
  private var titleBinding: Binding<String> {
    Binding(get: { draft.issue.title }, set: { draft.issue.title = $0 })
  }

  /// Binding for the issue description field.
  private var descriptionBinding: Binding<String> {
    Binding(get: { draft.issue.description }, set: { draft.issue.description = $0 })
  }

  /// Binding for the selected team ID.
  private var teamBinding: Binding<String> {
    Binding(get: { draft.issue.team }, set: { draft.issue.team = $0 })
  }

  /// Binding for the selected state ID.
  private var stateBinding: Binding<String> {
    Binding(get: { draft.issue.state }, set: { draft.issue.state = $0 })
  }

  /// Binding for the selected priority as a menu tag string.
  private var priorityTagBinding: Binding<String> {
    Binding(
      get: { String(draft.issue.priority ?? -1) },
      set: { rawValue in
        let value = Int(rawValue) ?? -1
        draft.issue.priority = value == -1 ? nil : value
      }
    )
  }

  /// Binding for the assignee field.
  private var assigneeBinding: Binding<String> {
    Binding(get: { draft.issue.assignee }, set: { draft.issue.assignee = $0 })
  }

  /// Binding for the due date field.
  private var dueDateBinding: Binding<Date> {
    Binding(
      get: { draft.issue.dueDate ?? Calendar.current.startOfDay(for: Date()) },
      set: { draft.issue.dueDate = $0 }
    )
  }

  /// Binding for the estimate picker.
  private var estimateBinding: Binding<Int> {
    Binding(
      get: { draft.issue.estimate ?? -1 },
      set: { draft.issue.estimate = $0 == -1 ? nil : $0 }
    )
  }

  /// Binding for the project picker.
  private var projectBinding: Binding<String> {
    Binding(get: { draft.issue.project }, set: { draft.issue.project = $0 })
  }

  /// Binding for the cycle picker.
  private var cycleBinding: Binding<String> {
    Binding(get: { draft.issue.cycle }, set: { draft.issue.cycle = $0 })
  }

  /// Binding for the milestone picker.
  private var milestoneBinding: Binding<String> {
    Binding(get: { draft.issue.milestone }, set: { draft.issue.milestone = $0 })
  }

  /// Binding for the parent issue field.
  private var parentBinding: Binding<String> {
    Binding(get: { draft.issue.parent }, set: { draft.issue.parent = $0 })
  }

  /// Binding for the label picker.
  private var labelBinding: Binding<String> {
    Binding(get: { draft.issue.label }, set: { draft.issue.label = $0 })
  }
}

/// Observable draft state for the Linear issue creator window.
private final class LinearIssueDraft: ObservableObject {
  /// Editable issue create draft.
  @Published var issue = LinearIssueCreateDraft()

  /// Team and state options loaded from Linear.
  @Published var teams: [LinearTeamOption] = []

  /// User options loaded from Linear.
  @Published var assignees: [LinearUserOption] = []

  /// Project options loaded from Linear.
  @Published var projects: [LinearProjectOption] = []

  /// Cycle options loaded for the selected team.
  @Published var cycles: [LinearCycleOption] = []

  /// Label options loaded for the selected team.
  @Published var labels: [LinearLabelOption] = []

  /// Milestone options loaded for the selected project.
  @Published var milestones: [LinearMilestoneOption] = []

  /// Compact creation or options-loading error text.
  @Published var errorMessage: String?

  /// Whether a create command is currently in flight.
  @Published var isCreating = false

  /// Whether team/status options are currently loading.
  @Published var isLoadingOptions = false

  /// Whether options have already been requested.
  @Published var hasLoadedOptions = false
}

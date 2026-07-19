import SwiftUI

/// Stock SwiftUI window for creating a Linear issue through the API.
struct LinearIssueEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  @StateObject private var draft = LinearIssueDraft()

  /// Builds the Linear issue creator window content.
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          formRow("Title") {
            TextField("Issue title", text: titleBinding)
              .textFieldStyle(.roundedBorder)
              .accessibilityIdentifier("linearEditor.title")
          }

          formRow("Team") {
            Picker("", selection: teamBinding) {
              Text("Select team").tag("")
              ForEach(draft.teams) { team in
                Text(team.label).tag(team.id)
              }
            }
            .labelsHidden()
            .accessibilityIdentifier("linearEditor.team")
          }

          formRow("Status") {
            Picker("", selection: stateBinding) {
              Text("Default").tag("")
              ForEach(statusOptions) { state in
                Text(state.name).tag(state.id)
              }
            }
            .labelsHidden()
            .disabled(statusOptions.isEmpty)
            .accessibilityIdentifier("linearEditor.status")
          }

          formRow("Priority") {
            Picker("", selection: priorityBinding) {
              Text("Default").tag(-1)
              ForEach(createPriorityOptions) { priority in
                Text(priority.label).tag(priority.value)
              }
            }
            .labelsHidden()
            .accessibilityIdentifier("linearEditor.priority")
          }

          formRow("Assignee") {
            Picker("", selection: assigneeBinding) {
              Text("Me (self)").tag("self")
              Text("No assignee").tag("")
              ForEach(draft.assignees) { assignee in
                Text(assignee.label).tag(assignee.id)
              }
            }
            .labelsHidden()
              .accessibilityIdentifier("linearEditor.assignee")
          }

          formRow("Due") {
            TextField("YYYY-MM-DD", text: dueDateBinding)
              .textFieldStyle(.roundedBorder)
              .accessibilityIdentifier("linearEditor.dueDate")
          }

          formRow("Description") {
            TextEditor(text: descriptionBinding)
              .font(.body)
              .frame(minHeight: 110)
              .scrollContentBackground(.hidden)
              .padding(6)
              .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(Color.primary.opacity(0.04))
              }
              .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .stroke(Color.primary.opacity(0.08))
              }
              .accessibilityIdentifier("linearEditor.description")
          }

          DisclosureGroup("Advanced", isExpanded: $draft.isAdvancedExpanded) {
            VStack(alignment: .leading, spacing: 10) {
              formRow("Estimate") {
                Picker("", selection: estimateBinding) {
                  Text("None").tag(-1)
                  ForEach(1...8, id: \.self) { estimate in
                    Text("\(estimate)").tag(estimate)
                  }
                }
                .labelsHidden()
                .accessibilityIdentifier("linearEditor.estimate")
              }

              formRow("Project") {
                TextField("Project name", text: projectBinding)
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("linearEditor.project")
              }

              formRow("Cycle") {
                TextField("Cycle name, number, or active", text: cycleBinding)
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("linearEditor.cycle")
              }

              formRow("Milestone") {
                TextField("Milestone name", text: milestoneBinding)
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("linearEditor.milestone")
              }

              formRow("Parent") {
                TextField("TEAM-123", text: parentBinding)
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("linearEditor.parent")
              }

              formRow("Labels") {
                TextField("Comma-separated labels", text: labelsBinding)
                  .textFieldStyle(.roundedBorder)
                  .accessibilityIdentifier("linearEditor.labels")
              }

              formRow("") {
                Toggle("Start after creating", isOn: shouldStartBinding)
                  .accessibilityIdentifier("linearEditor.start")
              }
            }
            .padding(.top, 8)
          }
          .accessibilityIdentifier("linearEditor.advanced")

          if let errorMessage = draft.errorMessage {
            Text(errorMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("linearEditor.error")
          }
        }
        .padding(20)
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
    .frame(minWidth: 560, minHeight: 560)
    .task {
      await loadOptionsIfNeeded()
    }
    .onChange(of: draft.issue.team) { _, _ in
      pruneStateSelection()
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

  /// Priority choices accepted by `linear issue create`.
  private var createPriorityOptions: [LinearPriorityOption] {
    LinearPriorityOption.allCases.filter { $0.value >= 1 }
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

  /// Loads team/status options once per editor lifetime.
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
      if draft.issue.team.isEmpty {
        draft.issue.team = draft.teams.first?.id ?? ""
      }
    } catch {
      optionLoadError = error.localizedDescription.compactLine(limit: 160)
    }

    do {
      draft.assignees = try await store.linearIssueCreateAssigneeOptions()
    } catch {
      optionLoadError = optionLoadError ?? error.localizedDescription.compactLine(limit: 160)
    }

    draft.errorMessage = optionLoadError
  }

  /// Clears the selected status when it is not available for the selected team.
  private func pruneStateSelection() {
    guard !draft.issue.state.isEmpty else {
      return
    }
    if !statusOptions.contains(where: { $0.id == draft.issue.state }) {
      draft.issue.state = ""
    }
  }

  /// Builds one native macOS-style settings row.
  private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 92, alignment: .trailing)
        .padding(.top, 5)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
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

  /// Binding for the selected priority.
  private var priorityBinding: Binding<Int> {
    Binding(
      get: { draft.issue.priority ?? -1 },
      set: { draft.issue.priority = $0 == -1 ? nil : $0 }
    )
  }

  /// Binding for the assignee field.
  private var assigneeBinding: Binding<String> {
    Binding(get: { draft.issue.assignee }, set: { draft.issue.assignee = $0 })
  }

  /// Binding for the due date field.
  private var dueDateBinding: Binding<String> {
    Binding(get: { draft.issue.dueDate }, set: { draft.issue.dueDate = $0 })
  }

  /// Binding for the estimate picker.
  private var estimateBinding: Binding<Int> {
    Binding(
      get: { draft.issue.estimate ?? -1 },
      set: { draft.issue.estimate = $0 == -1 ? nil : $0 }
    )
  }

  /// Binding for the project field.
  private var projectBinding: Binding<String> {
    Binding(get: { draft.issue.project }, set: { draft.issue.project = $0 })
  }

  /// Binding for the cycle field.
  private var cycleBinding: Binding<String> {
    Binding(get: { draft.issue.cycle }, set: { draft.issue.cycle = $0 })
  }

  /// Binding for the milestone field.
  private var milestoneBinding: Binding<String> {
    Binding(get: { draft.issue.milestone }, set: { draft.issue.milestone = $0 })
  }

  /// Binding for the parent issue field.
  private var parentBinding: Binding<String> {
    Binding(get: { draft.issue.parent }, set: { draft.issue.parent = $0 })
  }

  /// Binding for the labels field.
  private var labelsBinding: Binding<String> {
    Binding(get: { draft.issue.labels }, set: { draft.issue.labels = $0 })
  }

  /// Binding for the start-after-create toggle.
  private var shouldStartBinding: Binding<Bool> {
    Binding(get: { draft.issue.shouldStart }, set: { draft.issue.shouldStart = $0 })
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

  /// Compact creation or options-loading error text.
  @Published var errorMessage: String?

  /// Whether a create command is currently in flight.
  @Published var isCreating = false

  /// Whether team/status options are currently loading.
  @Published var isLoadingOptions = false

  /// Whether options have already been requested.
  @Published var hasLoadedOptions = false

  /// Whether the advanced field group is visible.
  @Published var isAdvancedExpanded = false
}

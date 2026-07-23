import SwiftUI

/// Linear issue defaults and menu ordering settings.
struct IssuesSettingsTab: View {
  @EnvironmentObject private var store: StatusStore
  @State private var linearCreateTeams: [LinearTeamOption] = []
  @State private var linearCreateProjects: [LinearProjectOption] = []
  @State private var linearCreateLabels: [LinearLabelOption] = []
  @State private var isLoadingLinearCreateDefaults = false
  @State private var linearCreateDefaultsError: String?

  var body: some View {
    Form {
      Section {
        if isLinearConnected {
          linearDefaults
        } else {
          Text("Connect Linear in Accounts to configure new Linear issue defaults.")
            .foregroundStyle(.secondary)
        }
      } header: {
        Label("New Linear Issue Defaults", systemImage: "square.and.pencil")
      } footer: {
        if let linearCreateDefaultsError {
          Text(linearCreateDefaultsError)
            .accessibilityIdentifier("settings.linearCreateDefaultsError")
        }
      }

      Section {
        Toggle("Show issues in menu", isOn: showsLinearSectionBinding)
          .accessibilityIdentifier("settings.showsLinearSection")

        Picker("Linear issue order", selection: linearIssueOrderBinding) {
          ForEach(LinearIssueOrder.allCases) { order in
            Text(order.label).tag(order)
          }
        }
        .accessibilityIdentifier("settings.linearIssueOrder")
      } header: {
        Label("Menu", systemImage: "list.bullet")
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  /// Linear-specific defaults shown when Linear is connected.
  @ViewBuilder
  private var linearDefaults: some View {
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
      ForEach(linearCreateProjectOptions) { project in
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
  }

  /// Binding that persists whether the issues section appears in the menu.
  private var showsLinearSectionBinding: Binding<Bool> {
    Binding(
      get: { store.showsLinearSection },
      set: { store.setShowsLinearSection($0) }
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
        if !store.linearIssueCreateDefaultProjectID.isEmpty,
           !linearCreateProjects.isEmpty,
           !linearCreateProjectOptions.contains(where: { $0.id == store.linearIssueCreateDefaultProjectID }) {
          store.setLinearIssueCreateDefaultProjectID("")
        }
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

  /// Projects available for the configured default team.
  private var linearCreateProjectOptions: [LinearProjectOption] {
    linearCreateProjects.filter {
      $0.teamIDs.isEmpty || $0.teamIDs.contains(store.linearIssueCreateDefaultTeamID)
    }
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
         !linearCreateProjectOptions.contains(where: { $0.id == store.linearIssueCreateDefaultProjectID }) {
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
}

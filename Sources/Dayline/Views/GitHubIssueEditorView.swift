import SwiftUI

/// Stock SwiftUI window for creating a GitHub issue through the API.
struct GitHubIssueEditorView: View {
  @EnvironmentObject private var store: StatusStore
  @Environment(\.dismiss) private var dismiss

  @StateObject private var draft = GitHubIssueDraft()
  @State private var requestedOptionsRepository = ""

  /// Builds the GitHub issue creator window content.
  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          TextField("Title", text: titleBinding, prompt: Text("Issue title"))
            .accessibilityIdentifier("githubEditor.title")

          Picker("Repository", selection: repositoryBinding) {
            Text("Select repository").tag("")
            ForEach(enabledRepositories, id: \.fullName) { repository in
              Text(repository.fullName).tag(repository.fullName)
            }
          }
          .accessibilityIdentifier("githubEditor.repository")

          Picker("Assignee", selection: assigneeBinding) {
            Text("No assignee").tag("")
            if let ownLogin {
              Text("Me (\(ownLogin))").tag(ownLogin)
            }
            ForEach(draft.assignees.filter { $0.login != ownLogin }) { assignee in
              Text(assignee.login).tag(assignee.login)
            }
          }
          .disabled(draft.repository.isEmpty)
          .accessibilityIdentifier("githubEditor.assignee")

          LabeledContent("Label") {
            ColoredMenuPicker(
              selection: labelBinding,
              items: [ColoredMenuPickerItem(tag: "", title: "None", symbolName: nil, color: .secondary)]
                + draft.labels.map { label in
                  ColoredMenuPickerItem(
                    tag: label.name,
                    title: label.name,
                    symbolName: "circle.fill",
                    color: Color(linearHex: label.color)
                  )
              }
            )
          }
          .accessibilityIdentifier("githubEditor.labels")
        } header: {
          Label("Issue", systemImage: "square.and.pencil")
        }

        Section {
          TextEditor(text: bodyBinding)
            .font(.body)
            .frame(minHeight: 110)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("githubEditor.body")
        } header: {
          Label("Description", systemImage: "text.alignleft")
        }
      }
      .formStyle(.grouped)

      if let errorMessage = draft.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 20)
          .padding(.bottom, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("githubEditor.error")
      }

      Divider()

      HStack {
        if draft.isLoadingOptions {
          ProgressView()
            .controlSize(.small)
            .accessibilityIdentifier("githubEditor.loading")
        }

        Spacer()

        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("githubEditor.cancel")

        Button(draft.isCreating ? "Creating..." : "Create") {
          Task { await createIssue() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canCreate)
        .accessibilityIdentifier("githubEditor.create")
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(minWidth: 560, idealWidth: 600, minHeight: 460, idealHeight: 520)
    .task {
      if draft.repository.isEmpty {
        let defaultRepo = store.githubIssueCreateDefaultRepo
        let enabled = enabledRepositories.map(\.fullName)
        let chosen = enabled.contains(defaultRepo) ? defaultRepo : (enabled.first ?? "")
        requestedOptionsRepository = chosen
        draft.repository = chosen
      }
      draft.assignee = ownLogin ?? ""
      await loadRepositoryOptions()
    }
    .onChange(of: draft.repository) { _, _ in
      guard draft.repository != requestedOptionsRepository else { return }
      draft.selectedLabel = ""
      draft.assignee = ""
      draft.assignees = []
      draft.labels = []
      Task { await loadRepositoryOptions() }
    }
  }

  /// Repositories the user enabled for the GitHub issues section.
  private var enabledRepositories: [GitHubRepository] {
    store.githubAccount.repositories.filter(\.isEnabled)
  }

  /// Login of the connected GitHub account, when known.
  private var ownLogin: String? {
    store.connectionStatuses.first(where: { $0.provider == .github })?.accountLabel
  }

  /// Whether the current draft can create a GitHub issue.
  private var canCreate: Bool {
    !draft.isCreating
      && !draft.isLoadingOptions
      && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !draft.repository.isEmpty
  }

  /// Label names currently selected for the new issue.
  private var selectedLabels: [String] {
    draft.selectedLabel.isEmpty ? [] : [draft.selectedLabel]
  }

  /// Binding for the label picker.
  private var labelBinding: Binding<String> {
    Binding(get: { draft.selectedLabel }, set: { draft.selectedLabel = $0 })
  }

  /// Creates the issue and closes the window when GitHub accepts it.
  private func createIssue() async {
    guard canCreate else {
      return
    }

    draft.isCreating = true
    draft.errorMessage = nil

    do {
      try await store.createGitHubIssue(
        repoFullName: draft.repository,
        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
        labels: selectedLabels,
        assignees: draft.assignee.isEmpty ? [] : [draft.assignee]
      )
      dismiss()
    } catch {
      draft.errorMessage = error.localizedDescription.compactLine(limit: 160)
    }

    draft.isCreating = false
  }

  /// Loads assignable collaborators and labels for the selected repository.
  private func loadRepositoryOptions() async {
    let repository = draft.repository
    requestedOptionsRepository = repository
    guard !repository.isEmpty else {
      draft.assignees = []
      draft.labels = []
      return
    }

    draft.isLoadingOptions = true
    defer { if draft.repository == repository { draft.isLoadingOptions = false } }

    do {
      let assignees = try await store.githubIssueCreateAssigneeOptions(repoFullName: repository)
      guard draft.repository == repository else { return }
      draft.assignees = assignees
      if !draft.assignee.isEmpty, !assignees.contains(where: { $0.login == draft.assignee }) {
        draft.assignee = ""
      }
    } catch {
      guard draft.repository == repository else { return }
      draft.assignees = []
      draft.errorMessage = error.localizedDescription.compactLine(limit: 160)
    }

    do {
      let labels = try await store.githubIssueCreateLabelOptions(repoFullName: repository)
      guard draft.repository == repository else { return }
      draft.labels = labels
      if !draft.selectedLabel.isEmpty, !labels.contains(where: { $0.name == draft.selectedLabel }) {
        draft.selectedLabel = ""
      }
    } catch {
      guard draft.repository == repository else { return }
      draft.labels = []
      draft.errorMessage = draft.errorMessage ?? error.localizedDescription.compactLine(limit: 160)
    }
  }

  /// Binding for the issue title field.
  private var titleBinding: Binding<String> {
    Binding(get: { draft.title }, set: { draft.title = $0 })
  }

  /// Binding for the issue body field.
  private var bodyBinding: Binding<String> {
    Binding(get: { draft.body }, set: { draft.body = $0 })
  }

  /// Binding for the selected repository.
  private var repositoryBinding: Binding<String> {
    Binding(get: { draft.repository }, set: { draft.repository = $0 })
  }

  /// Binding for the assignee field.
  private var assigneeBinding: Binding<String> {
    Binding(get: { draft.assignee }, set: { draft.assignee = $0 })
  }
}

/// Observable draft state for the GitHub issue creator window.
private final class GitHubIssueDraft: ObservableObject {
  /// Editable issue title.
  @Published var title = ""

  /// Editable issue description.
  @Published var body = ""

  /// Selected repository in `owner/name` form.
  @Published var repository = ""

  /// Selected assignee login, empty for none.
  @Published var assignee = ""

  /// Assignee options loaded for the selected repository.
  @Published var assignees: [GitHubAssigneeOption] = []

  /// Label options loaded for the selected repository.
  @Published var labels: [GitHubLabelOption] = []

  /// Name of the label selected for the new issue, empty for none.
  @Published var selectedLabel = ""

  /// Compact creation or options-loading error text.
  @Published var errorMessage: String?

  /// Whether a create command is currently in flight.
  @Published var isCreating = false

  /// Whether assignee options are currently loading.
  @Published var isLoadingOptions = false
}

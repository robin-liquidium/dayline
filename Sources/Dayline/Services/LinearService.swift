import Foundation

/// Fetches assigned Linear issues through the Linear CLI GraphQL command.
struct LinearService {
  /// Absolute path to the Linear CLI.
  var linearPath = CLIPaths.linear

  /// Shared shell runner used for process execution.
  var shellClient = ShellClient()

  /// Loads active assigned issues for display in the menu bar.
  func fetchAssignedIssues() async throws -> [LinearIssueItem] {
    let query = """
    query AssignedIssues($first: Int!) {
      viewer {
        assignedIssues(first: $first, filter: { state: { type: { nin: ["completed", "canceled"] } } }) {
          nodes {
            identifier
            title
            priority
            priorityLabel
            dueDate
            url
            state { id name type }
            team {
              states(first: 50) {
                nodes { id name type position }
              }
            }
          }
        }
      }
    }
    """

    let result = try await shellClient.checkedRun(
      linearPath,
      arguments: ["api", query, "--variable", "first=50"]
    )
    let response = try JSONDecoder().decode(LinearAPIResponse.self, from: Data(result.stdout.utf8))
    return response.data.viewer.assignedIssues.nodes
      .map(\.displayItem)
  }

  /// Updates a Linear issue to the selected workflow state.
  func updateIssueStatus(issueID: String, stateID: String) async throws -> LinearIssueItem {
    let mutation = """
    mutation UpdateIssueStatus($id: String!, $stateId: String!) {
      issueUpdate(id: $id, input: { stateId: $stateId }) {
        success
        issue {
          identifier
          title
          priority
          priorityLabel
          dueDate
          url
          state { id name type }
          team {
            states(first: 50) {
              nodes { id name type position }
            }
          }
        }
      }
    }
    """

    let result = try await shellClient.checkedRun(
      linearPath,
      arguments: [
        "api",
        mutation,
        "--variable",
        "id=\(issueID)",
        "--variable",
        "stateId=\(stateID)"
      ]
    )
    let response = try JSONDecoder().decode(LinearUpdateResponse.self, from: Data(result.stdout.utf8))
    guard response.data.issueUpdate.success else {
      throw LinearServiceError.statusUpdateFailed
    }
    return response.data.issueUpdate.issue.displayItem
  }

  /// Updates a Linear issue to the selected priority.
  func updateIssuePriority(issueID: String, priority: Int) async throws -> LinearIssueItem {
    let mutation = """
    mutation UpdateIssuePriority($id: String!, $priority: Int!) {
      issueUpdate(id: $id, input: { priority: $priority }) {
        success
        issue {
          identifier
          title
          priority
          priorityLabel
          dueDate
          url
          state { id name type }
          team {
            states(first: 50) {
              nodes { id name type position }
            }
          }
        }
      }
    }
    """

    let result = try await shellClient.checkedRun(
      linearPath,
      arguments: [
        "api",
        mutation,
        "--variable",
        "id=\(issueID)",
        "--variable",
        "priority=\(priority)"
      ]
    )
    let response = try JSONDecoder().decode(LinearUpdateResponse.self, from: Data(result.stdout.utf8))
    guard response.data.issueUpdate.success else {
      throw LinearServiceError.priorityUpdateFailed
    }
    return response.data.issueUpdate.issue.displayItem
  }

  /// Loads Linear teams and workflow states for the issue creator.
  func fetchTeamOptions() async throws -> [LinearTeamOption] {
    let query = """
    query LinearTeams($first: Int!) {
      teams(first: $first) {
        nodes {
          id
          key
          name
          states(first: 50) {
            nodes { id name type position }
          }
        }
      }
    }
    """

    let result = try await shellClient.checkedRun(
      linearPath,
      arguments: ["api", query, "--variable", "first=50"]
    )
    let response = try JSONDecoder().decode(LinearTeamsResponse.self, from: Data(result.stdout.utf8))
    return response.data.teams.nodes.map(\.displayItem)
  }

  /// Loads active Linear users for the issue creator assignee picker.
  func fetchUserOptions() async throws -> [LinearUserOption] {
    let query = """
    query LinearUsers($first: Int!) {
      users(first: $first) {
        nodes {
          id
          name
          displayName
          active
        }
      }
    }
    """

    let result = try await shellClient.checkedRun(
      linearPath,
      arguments: ["api", query, "--variable", "first=100"]
    )
    let response = try JSONDecoder().decode(LinearUsersResponse.self, from: Data(result.stdout.utf8))
    return response.data.users.nodes
      .map(\.displayItem)
      .filter(\.isActive)
      .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }

  /// Creates a Linear issue using the CLI's non-interactive creation command.
  func createIssue(draft: LinearIssueCreateDraft) async throws {
    var arguments = [
      "issue",
      "create",
      "--no-interactive",
      "--title",
      draft.title
    ]

    let trimmedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedDescription.isEmpty {
      arguments.append(contentsOf: ["--description", trimmedDescription])
    }

    appendFlag("--assignee", draft.assignee, to: &arguments)
    appendFlag("--team", draft.team, to: &arguments)
    appendFlag("--state", draft.state, to: &arguments)
    appendFlag("--due-date", draft.dueDate, to: &arguments)
    appendFlag("--project", draft.project, to: &arguments)
    appendFlag("--cycle", draft.cycle, to: &arguments)
    appendFlag("--milestone", draft.milestone, to: &arguments)
    appendFlag("--parent", draft.parent, to: &arguments)

    if let priority = draft.priority {
      arguments.append(contentsOf: ["--priority", "\(priority)"])
    }

    if let estimate = draft.estimate {
      arguments.append(contentsOf: ["--estimate", "\(estimate)"])
    }

    for label in draft.labels.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !label.isEmpty {
      arguments.append(contentsOf: ["--label", label])
    }

    if draft.shouldStart {
      arguments.append("--start")
    }

    if draft.shouldSkipDefaultTemplate {
      arguments.append("--no-use-default-template")
    }

    _ = try await shellClient.checkedRun(linearPath, arguments: arguments)
  }

  /// Appends a CLI flag only when the value is not blank.
  private func appendFlag(_ flag: String, _ value: String, to arguments: inout [String]) {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedValue.isEmpty {
      arguments.append(contentsOf: [flag, trimmedValue])
    }
  }
}

/// Linear service failure cases.
enum LinearServiceError: LocalizedError {
  /// Linear accepted the mutation but reported failure.
  case statusUpdateFailed

  /// Linear accepted the priority mutation but reported failure.
  case priorityUpdateFailed

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .statusUpdateFailed:
      "Linear did not update the issue status."
    case .priorityUpdateFailed:
      "Linear did not update the issue priority."
    }
  }
}

/// Root GraphQL response shape for the assigned issue query.
private struct LinearAPIResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearData
}

/// Root GraphQL response shape for an issue status mutation.
private struct LinearUpdateResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearUpdateData
}

/// Root GraphQL response shape for team options.
private struct LinearTeamsResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearTeamsData
}

/// Root GraphQL response shape for user options.
private struct LinearUsersResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearUsersData
}

/// Linear team query data payload.
private struct LinearTeamsData: Decodable {
  /// Visible Linear teams.
  let teams: LinearTeamConnection
}

/// Linear user query data payload.
private struct LinearUsersData: Decodable {
  /// Visible Linear users.
  let users: LinearUserConnection
}

/// Linear team connection payload.
private struct LinearTeamConnection: Decodable {
  /// Visible Linear team nodes.
  let nodes: [LinearTeamNode]
}

/// Linear user connection payload.
private struct LinearUserConnection: Decodable {
  /// Visible Linear user nodes.
  let nodes: [LinearUserNode]
}

/// Raw Linear team node returned by GraphQL.
private struct LinearTeamNode: Decodable {
  /// Stable Linear team identifier.
  let id: String

  /// Short Linear team key.
  let key: String

  /// Human-readable team name.
  let name: String

  /// Workflow states for the team.
  let states: LinearWorkflowStateConnection

  /// Converts the raw node into a picker option.
  var displayItem: LinearTeamOption {
    LinearTeamOption(
      id: id,
      key: key,
      name: name,
      states: states.nodes
        .map(\.displayItem)
        .sorted { $0.position < $1.position }
    )
  }
}

/// Raw Linear user node returned by GraphQL.
private struct LinearUserNode: Decodable {
  /// Stable Linear user identifier.
  let id: String

  /// Human-readable profile name.
  let name: String

  /// Linear username.
  let displayName: String?

  /// Whether the user is active.
  let active: Bool

  /// Converts the raw node into a picker option.
  var displayItem: LinearUserOption {
    LinearUserOption(
      id: id,
      name: name,
      displayName: displayName ?? "",
      isActive: active
    )
  }
}

/// Linear GraphQL mutation data payload.
private struct LinearUpdateData: Decodable {
  /// Issue update mutation payload.
  let issueUpdate: LinearIssueUpdate
}

/// Linear issue update mutation payload.
private struct LinearIssueUpdate: Decodable {
  /// Whether Linear applied the update.
  let success: Bool

  /// Updated issue node.
  let issue: LinearIssueNode
}

/// Linear GraphQL data payload.
private struct LinearData: Decodable {
  /// Current authenticated user.
  let viewer: LinearViewer
}

/// Current Linear user payload.
private struct LinearViewer: Decodable {
  /// Assigned issue connection.
  let assignedIssues: LinearAssignedIssues
}

/// Linear assigned issue connection.
private struct LinearAssignedIssues: Decodable {
  /// Assigned issue nodes.
  let nodes: [LinearIssueNode]
}

/// Raw Linear issue node returned by GraphQL.
private struct LinearIssueNode: Decodable {
  /// Linear identifier such as `DEV-123`.
  let identifier: String

  /// Issue title.
  let title: String

  /// Numeric Linear priority.
  let priority: Int

  /// Human-readable priority label.
  let priorityLabel: String

  /// Optional Linear due date in `YYYY-MM-DD` form.
  let dueDate: String?

  /// Browser URL.
  let url: String?

  /// Current workflow state.
  let state: LinearIssueState

  /// Owning Linear team.
  let team: LinearIssueTeam

  /// Converts the GraphQL node into a display item.
  var displayItem: LinearIssueItem {
    LinearIssueItem(
      id: identifier,
      title: title,
      priority: priority,
      priorityLabel: priorityLabel,
      stateName: state.name,
      stateID: state.id,
      stateType: state.type,
      workflowStates: team.states.nodes
        .map(\.displayItem)
        .sorted { $0.position < $1.position },
      dueDate: dueDate,
      url: url.flatMap(URL.init(string:))
    )
  }
}

/// Raw Linear workflow state shape.
private struct LinearIssueState: Decodable {
  /// State identifier.
  let id: String

  /// State display name.
  let name: String

  /// State type, such as `started` or `unstarted`.
  let type: String
}

/// Raw Linear team shape.
private struct LinearIssueTeam: Decodable {
  /// Workflow states connection.
  let states: LinearWorkflowStateConnection
}

/// Raw Linear workflow states connection.
private struct LinearWorkflowStateConnection: Decodable {
  /// Workflow state nodes.
  let nodes: [LinearWorkflowStateNode]
}

/// Raw Linear workflow state node.
private struct LinearWorkflowStateNode: Decodable {
  /// State identifier.
  let id: String

  /// State display name.
  let name: String

  /// State type, such as `started` or `unstarted`.
  let type: String

  /// Workflow position in Linear.
  let position: Double

  /// Converts the GraphQL node into a display state.
  var displayItem: LinearWorkflowState {
    LinearWorkflowState(id: id, name: name, type: type, position: position)
  }
}

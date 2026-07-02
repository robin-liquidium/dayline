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

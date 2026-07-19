import Foundation

/// Fetches and mutates Linear issues through the Linear GraphQL API.
struct LinearService {
  /// OAuth session supplying Linear access tokens.
  var authSession: OAuthSession = .linear

  /// Linear GraphQL endpoint.
  private static let endpoint = URL(string: "https://api.linear.app/graphql")!

  /// Loads the connected Linear account label for Settings.
  func fetchAccountLabel() async throws -> String {
    let query = """
    query ViewerIdentity {
      viewer {
        name
        email
        displayName
      }
    }
    """

    let response = try await graphQL(query, variables: [:], as: LinearViewerIdentityResponse.self)
    let viewer = response.data.viewer
    if let email = viewer.email, !email.isEmpty {
      return email
    }
    if let displayName = viewer.displayName, !displayName.isEmpty {
      return displayName
    }
    return viewer.name
  }

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

    let response = try await graphQL(query, variables: ["first": 50], as: LinearAPIResponse.self)
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

    let response = try await graphQL(mutation, variables: [
      "id": issueID,
      "stateId": stateID
    ], as: LinearUpdateResponse.self)
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

    let response = try await graphQL(mutation, variables: [
      "id": issueID,
      "priority": priority
    ], as: LinearUpdateResponse.self)
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

    let response = try await graphQL(query, variables: ["first": 50], as: LinearTeamsResponse.self)
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

    let response = try await graphQL(query, variables: ["first": 100], as: LinearUsersResponse.self)
    return response.data.users.nodes
      .map(\.displayItem)
      .filter(\.isActive)
      .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }

  /// Creates a Linear issue from a draft, resolving free-text fields to IDs.
  func createIssue(draft: LinearIssueCreateDraft) async throws {
    let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let teamID = draft.team.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !teamID.isEmpty else {
      throw LinearServiceError.missingTeamOrTitle
    }

    var input: [String: Any] = [
      "title": title,
      "teamId": teamID
    ]

    let description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
    if !description.isEmpty {
      input["description"] = description
    }

    let assignee = draft.assignee.trimmingCharacters(in: .whitespacesAndNewlines)
    if assignee == "self" {
      input["assigneeId"] = try await fetchViewerID()
    } else if !assignee.isEmpty {
      input["assigneeId"] = assignee
    }

    var stateID = draft.state.trimmingCharacters(in: .whitespacesAndNewlines)
    if stateID.isEmpty, draft.shouldStart {
      stateID = try await fetchStartedStateID(teamID: teamID) ?? ""
    }
    if !stateID.isEmpty {
      input["stateId"] = stateID
    }

    if let priority = draft.priority {
      input["priority"] = priority
    }

    if let estimate = draft.estimate {
      input["estimate"] = estimate
    }

    let dueDate = draft.dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
    if !dueDate.isEmpty {
      input["dueDate"] = dueDate
    }

    let projectName = draft.project.trimmingCharacters(in: .whitespacesAndNewlines)
    if !projectName.isEmpty {
      let projectID = try await fetchProjectID(named: projectName)
      input["projectId"] = projectID

      let milestoneName = draft.milestone.trimmingCharacters(in: .whitespacesAndNewlines)
      if !milestoneName.isEmpty {
        input["projectMilestoneId"] = try await fetchMilestoneID(projectID: projectID, named: milestoneName)
      }
    }

    let cycle = draft.cycle.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cycle.isEmpty {
      input["cycleId"] = try await fetchCycleID(teamID: teamID, matching: cycle)
    }

    let parent = draft.parent.trimmingCharacters(in: .whitespacesAndNewlines)
    if !parent.isEmpty {
      input["parentId"] = try await fetchIssueID(identifier: parent)
    }

    let labelNames = draft.labels
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    if !labelNames.isEmpty {
      input["labelIds"] = try await fetchLabelIDs(teamID: teamID, names: labelNames)
    }

    let mutation = """
    mutation CreateIssue($input: IssueCreateInput!) {
      issueCreate(input: $input) {
        success
        issue { identifier url }
      }
    }
    """

    let response = try await graphQL(mutation, variables: ["input": input], as: LinearCreateResponse.self)
    guard response.data.issueCreate.success else {
      throw LinearServiceError.createFailed
    }
  }

  /// Performs one GraphQL operation and surfaces provider errors as thrown errors.
  private func graphQL<Response: Decodable>(
    _ query: String,
    variables: [String: Any],
    as type: Response.Type
  ) async throws -> Response {
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "query": query,
      "variables": variables
    ])

    let data = try await authSession.authorizedData(for: request)

    if let envelope = try? JSONDecoder().decode(GraphQLErrorEnvelope.self, from: data),
       let message = envelope.errors?.first?.message {
      throw LinearServiceError.graphQLError(message)
    }

    return try JSONDecoder().decode(Response.self, from: data)
  }

  /// Loads the authenticated user's Linear ID.
  private func fetchViewerID() async throws -> String {
    let response = try await graphQL("query Viewer { viewer { id } }", variables: [:], as: LinearViewerIDResponse.self)
    return response.data.viewer.id
  }

  /// Loads the first started-state ID for a team, used by start-after-create.
  private func fetchStartedStateID(teamID: String) async throws -> String? {
    let query = """
    query TeamStartedStates($id: String!) {
      team(id: $id) {
        states(first: 10, filter: { type: { eq: "started" } }) {
          nodes { id position }
        }
      }
    }
    """

    let response = try await graphQL(query, variables: ["id": teamID], as: LinearTeamStatesResponse.self)
    return response.data.team?.states.nodes
      .sorted { $0.position < $1.position }
      .first?.id
  }

  /// Resolves a project name to its Linear ID.
  private func fetchProjectID(named name: String) async throws -> String {
    let query = """
    query ProjectByName($name: String!) {
      projects(first: 1, filter: { name: { eqIgnoreCase: $name } }) {
        nodes { id }
      }
    }
    """

    let response = try await graphQL(query, variables: ["name": name], as: LinearProjectsResponse.self)
    guard let projectID = response.data.projects.nodes.first?.id else {
      throw LinearServiceError.unresolvedField("No Linear project named \"\(name)\".")
    }
    return projectID
  }

  /// Resolves a milestone name inside a project to its Linear ID.
  private func fetchMilestoneID(projectID: String, named name: String) async throws -> String {
    let query = """
    query ProjectMilestones($id: String!) {
      project(id: $id) {
        projectMilestones(first: 50) {
          nodes { id name }
        }
      }
    }
    """

    let response = try await graphQL(query, variables: ["id": projectID], as: LinearMilestonesResponse.self)
    guard let milestoneID = response.data.project?.projectMilestones.nodes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id else {
      throw LinearServiceError.unresolvedField("No milestone named \"\(name)\" in that project.")
    }
    return milestoneID
  }

  /// Resolves a cycle name, number, or `active` to its Linear ID.
  private func fetchCycleID(teamID: String, matching text: String) async throws -> String {
    let query = """
    query TeamCycles($id: String!) {
      team(id: $id) {
        cycles(first: 50) {
          nodes { id number name startsAt endsAt }
        }
      }
    }
    """

    let response = try await graphQL(query, variables: ["id": teamID], as: LinearCyclesResponse.self)
    let cycles = response.data.team?.cycles.nodes ?? []
    let now = Date()

    let match = cycles.first { cycle in
      if text.lowercased() == "active" {
        return (cycle.startDate...cycle.endDate).contains(now)
      }
      if let number = Int(text) {
        return cycle.number == number
      }
      return cycle.name?.caseInsensitiveCompare(text) == .orderedSame
    }

    guard let cycleID = match?.id else {
      throw LinearServiceError.unresolvedField("No cycle matching \"\(text)\" on that team.")
    }
    return cycleID
  }

  /// Resolves a parent issue identifier such as `DEV-123` to its Linear ID.
  private func fetchIssueID(identifier: String) async throws -> String {
    let query = """
    query ParentIssue($id: String!) {
      issue(id: $id) { id }
    }
    """

    let response = try await graphQL(query, variables: ["id": identifier], as: LinearIssueIDResponse.self)
    guard let issueID = response.data.issue?.id else {
      throw LinearServiceError.unresolvedField("No Linear issue \"\(identifier)\".")
    }
    return issueID
  }

  /// Resolves label names on a team to their Linear IDs.
  private func fetchLabelIDs(teamID: String, names: [String]) async throws -> [String] {
    let query = """
    query TeamLabels($id: String!) {
      team(id: $id) {
        labels(first: 100) {
          nodes { id name }
        }
      }
    }
    """

    let response = try await graphQL(query, variables: ["id": teamID], as: LinearLabelsResponse.self)
    let labels = response.data.team?.labels.nodes ?? []

    return try names.map { name in
      guard let label = labels.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
        throw LinearServiceError.unresolvedField("No label named \"\(name)\" on that team.")
      }
      return label.id
    }
  }
}

/// Linear service failure cases.
enum LinearServiceError: LocalizedError {
  /// Linear accepted the mutation but reported failure.
  case statusUpdateFailed

  /// Linear accepted the priority mutation but reported failure.
  case priorityUpdateFailed

  /// Linear accepted the create mutation but reported failure.
  case createFailed

  /// The draft lacks a title or team selection.
  case missingTeamOrTitle

  /// A free-text draft field could not be resolved to a Linear record.
  case unresolvedField(String)

  /// Linear returned a GraphQL error message.
  case graphQLError(String)

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .statusUpdateFailed:
      "Linear did not update the issue status."
    case .priorityUpdateFailed:
      "Linear did not update the issue priority."
    case .createFailed:
      "Linear did not create the issue."
    case .missingTeamOrTitle:
      "Add a title and pick a team."
    case .unresolvedField(let detail):
      detail
    case .graphQLError(let message):
      message
    }
  }
}

/// GraphQL error envelope checked before decoding operation payloads.
private struct GraphQLErrorEnvelope: Decodable {
  /// GraphQL errors returned by Linear, if any.
  let errors: [GraphQLErrorItem]?
}

/// Root GraphQL response shape for the viewer identity query.
private struct LinearViewerIdentityResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearViewerIdentityData
}

/// Viewer identity query data payload.
private struct LinearViewerIdentityData: Decodable {
  /// Current authenticated user.
  let viewer: LinearViewerIdentity
}

/// Viewer identity fields used for Settings.
private struct LinearViewerIdentity: Decodable {
  /// Human-readable profile name.
  let name: String

  /// Account email when available.
  let email: String?

  /// Linear username when available.
  let displayName: String?
}

/// One GraphQL error entry.
private struct GraphQLErrorItem: Decodable {
  /// Human-readable error message.
  let message: String
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

/// Root GraphQL response shape for the create mutation.
private struct LinearCreateResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearCreateData
}

/// Issue create mutation data payload.
private struct LinearCreateData: Decodable {
  /// Issue create mutation payload.
  let issueCreate: LinearIssueCreate
}

/// Issue create mutation payload.
private struct LinearIssueCreate: Decodable {
  /// Whether Linear created the issue.
  let success: Bool
}

/// Root GraphQL response shape for the viewer ID query.
private struct LinearViewerIDResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearViewerIDData
}

/// Viewer ID query data payload.
private struct LinearViewerIDData: Decodable {
  /// Current authenticated user.
  let viewer: LinearViewerID
}

/// Viewer ID payload.
private struct LinearViewerID: Decodable {
  /// Stable Linear user identifier.
  let id: String
}

/// Root GraphQL response shape for team state lookups.
private struct LinearTeamStatesResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearTeamLookupData
}

/// Root GraphQL response shape for project lookups.
private struct LinearProjectsResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearProjectsData
}

/// Root GraphQL response shape for milestone lookups.
private struct LinearMilestonesResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearMilestonesData
}

/// Root GraphQL response shape for cycle lookups.
private struct LinearCyclesResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearCyclesData
}

/// Root GraphQL response shape for issue ID lookups.
private struct LinearIssueIDResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearIssueIDData
}

/// Root GraphQL response shape for label lookups.
private struct LinearLabelsResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearLabelsData
}

/// Team lookup data payload shared by team-scoped queries.
private struct LinearTeamLookupData: Decodable {
  /// Looked-up team, when found.
  let team: LinearStartedStatesTeam?
}

/// Team payload carrying started workflow states.
private struct LinearStartedStatesTeam: Decodable {
  /// Started workflow states.
  let states: LinearStartedStateConnection
}

/// Started workflow state connection.
private struct LinearStartedStateConnection: Decodable {
  /// Started workflow state nodes.
  let nodes: [LinearStartedStateNode]
}

/// Started workflow state node.
private struct LinearStartedStateNode: Decodable {
  /// State identifier.
  let id: String

  /// Workflow position in Linear.
  let position: Double
}

/// Project lookup data payload.
private struct LinearProjectsData: Decodable {
  /// Matching projects.
  let projects: LinearProjectConnection
}

/// Project connection payload.
private struct LinearProjectConnection: Decodable {
  /// Matching project nodes.
  let nodes: [LinearIDNode]
}

/// Milestone lookup data payload.
private struct LinearMilestonesData: Decodable {
  /// Looked-up project, when found.
  let project: LinearMilestoneProject?
}

/// Project payload carrying milestones.
private struct LinearMilestoneProject: Decodable {
  /// Project milestones.
  let projectMilestones: LinearMilestoneConnection
}

/// Milestone connection payload.
private struct LinearMilestoneConnection: Decodable {
  /// Milestone nodes.
  let nodes: [LinearNamedNode]
}

/// Cycle lookup data payload.
private struct LinearCyclesData: Decodable {
  /// Looked-up team, when found.
  let team: LinearCycleTeam?
}

/// Team payload carrying cycles.
private struct LinearCycleTeam: Decodable {
  /// Team cycles.
  let cycles: LinearCycleConnection
}

/// Cycle connection payload.
private struct LinearCycleConnection: Decodable {
  /// Cycle nodes.
  let nodes: [LinearCycleNode]
}

/// Raw Linear cycle node.
private struct LinearCycleNode: Decodable {
  /// Cycle identifier.
  let id: String

  /// Cycle number within the team.
  let number: Int

  /// Optional cycle name.
  let name: String?

  /// Cycle start timestamp.
  let startsAt: String

  /// Cycle end timestamp.
  let endsAt: String

  /// Parsed cycle start.
  var startDate: Date {
    DateParsers.rfc3339Date(from: startsAt) ?? .distantPast
  }

  /// Parsed cycle end.
  var endDate: Date {
    DateParsers.rfc3339Date(from: endsAt) ?? .distantFuture
  }
}

/// Issue ID lookup data payload.
private struct LinearIssueIDData: Decodable {
  /// Looked-up issue, when found.
  let issue: LinearIDNode?
}

/// Label lookup data payload.
private struct LinearLabelsData: Decodable {
  /// Looked-up team, when found.
  let team: LinearLabelTeam?
}

/// Team payload carrying labels.
private struct LinearLabelTeam: Decodable {
  /// Team labels.
  let labels: LinearLabelConnection
}

/// Label connection payload.
private struct LinearLabelConnection: Decodable {
  /// Label nodes.
  let nodes: [LinearNamedNode]
}

/// Generic node carrying only an identifier.
private struct LinearIDNode: Decodable {
  /// Linear record identifier.
  let id: String
}

/// Generic node carrying an identifier and a name.
private struct LinearNamedNode: Decodable {
  /// Linear record identifier.
  let id: String

  /// Linear record name.
  let name: String
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

import Foundation

/// Fetches and mutates Linear issues through the Linear GraphQL API.
struct LinearService {
  /// OAuth session supplying Linear access tokens.
  var authSession: OAuthSession = .linear

  /// Linear GraphQL endpoint.
  private static let endpoint = URL(string: "https://api.linear.app/graphql")!

  /// Loads the connected Linear account label for Settings.
  func fetchAccountLabel() async throws -> String {
    try await fetchAccountDiscovery().workspaceName
  }

  /// Loads the current workspace, viewer identity, and complete visible team catalog.
  func fetchAccountDiscovery() async throws -> LinearAccountDiscovery {
    let query = """
    query LinearAccountDiscovery($first: Int!, $after: String) {
      viewer { name email displayName }
      organization { name }
      teams(first: $first, after: $after) {
        nodes { id key name }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    var teams: [LinearTeamSelection] = []
    var after: String?
    var workspaceName = "Linear"
    var userLabel = ""
    repeat {
      var variables: [String: Any] = ["first": 100]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearAccountDiscoveryResponse.self)
      workspaceName = response.data.organization.name
      userLabel = response.data.viewer.accountLabel
      teams.append(contentsOf: response.data.teams.nodes.map {
        LinearTeamSelection(id: $0.id, key: $0.key, name: $0.name, isEnabled: true)
      })
      after = response.data.teams.pageInfo.nextCursor
    } while after != nil

    return LinearAccountDiscovery(workspaceName: workspaceName, userLabel: userLabel, teams: teams)
  }

  /// Loads active assigned issues for display in the menu bar.
  func fetchAssignedIssues(enabledTeamIDs: Set<String>?) async throws -> [LinearIssueItem] {
    if let enabledTeamIDs, enabledTeamIDs.isEmpty { return [] }
    let query = """
    query AssignedIssues($first: Int!, $after: String) {
      viewer {
        assignedIssues(first: $first, after: $after, filter: { state: { type: { nin: ["completed", "canceled"] } } }) {
          nodes {
            identifier
            title
            priority
            priorityLabel
            dueDate
            branchName
            url
            state { id name type }
            assignee { id name displayName active }
            labels(first: 100) { nodes { id name color } }
            team {
              id
              states(first: 50) {
                nodes { id name type position }
              }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    var issues: [LinearIssueItem] = []
    var after: String?
    repeat {
      var variables: [String: Any] = ["first": 25]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearAPIResponse.self)
      let connection = response.data.viewer.assignedIssues
      issues.append(contentsOf: connection.nodes.map(\.displayItem).filter { issue in
        enabledTeamIDs?.contains(issue.teamID) ?? true
      })
      after = connection.pageInfo.nextCursor
    } while after != nil
    return issues
  }

  /// Loads every active issue visible to the signed-in user, not only assigned ones.
  func fetchOpenIssues(enabledTeamIDs: Set<String>?) async throws -> [LinearIssueItem] {
    if let enabledTeamIDs, enabledTeamIDs.isEmpty { return [] }
    let query = """
    query OpenIssues($first: Int!, $after: String, $filter: IssueFilter!) {
      issues(first: $first, after: $after, filter: $filter) {
        nodes {
          identifier
          title
          priority
          priorityLabel
          dueDate
          branchName
          url
          state { id name type }
          assignee { id name displayName active }
          labels(first: 100) { nodes { id name color } }
          team {
            id
            states(first: 50) {
              nodes { id name type position }
            }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    var issues: [LinearIssueItem] = []
    var after: String?
    var filter: [String: Any] = ["state": ["type": ["nin": ["completed", "canceled"]]]]
    if let enabledTeamIDs {
      filter["team"] = ["id": ["in": Array(enabledTeamIDs)]]
    }
    repeat {
      var variables: [String: Any] = ["first": 25, "filter": filter]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearIssuesResponse.self)
      let connection = response.data.issues
      issues.append(contentsOf: connection.nodes.map(\.displayItem))
      after = connection.pageInfo.nextCursor
    } while after != nil
    return issues
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
          branchName
          url
          state { id name type }
          assignee { id name displayName active }
          labels(first: 250) { nodes { id name color } }
          team {
            id
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
          branchName
          url
          state { id name type }
          assignee { id name displayName active }
          labels(first: 250) { nodes { id name color } }
          team {
            id
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

  /// Updates or clears a Linear issue due date in `YYYY-MM-DD` form.
  func updateIssueDueDate(issueID: String, dueDate: String?) async throws -> LinearIssueItem {
    let mutation = """
    mutation UpdateIssueDueDate($id: String!, $dueDate: TimelessDate) {
      issueUpdate(id: $id, input: { dueDate: $dueDate }) {
        success
        issue {
          identifier
          title
          priority
          priorityLabel
          dueDate
          branchName
          url
          state { id name type }
          assignee { id name displayName active }
          labels(first: 250) { nodes { id name color } }
          team {
            id
            states(first: 50) {
              nodes { id name type position }
            }
          }
        }
      }
    }
    """

    var variables: [String: Any] = ["id": issueID]
    variables["dueDate"] = dueDate ?? NSNull()
    let response = try await graphQL(mutation, variables: variables, as: LinearUpdateResponse.self)
    guard response.data.issueUpdate.success else {
      throw LinearServiceError.dueDateUpdateFailed
    }
    return response.data.issueUpdate.issue.displayItem
  }

  /// Replaces all labels on one Linear issue.
  func updateIssueLabels(issueID: String, labelIDs: [String]) async throws -> LinearIssueItem {
    try await updateIssueFields(issueID: issueID, input: ["labelIds": labelIDs])
  }

  /// Replaces or clears the singular Linear assignee.
  func updateIssueAssignee(issueID: String, assigneeID: String?) async throws -> LinearIssueItem {
    try await updateIssueFields(issueID: issueID, input: ["assigneeId": assigneeID ?? NSNull()])
  }

  private func updateIssueFields(issueID: String, input: [String: Any]) async throws -> LinearIssueItem {
    let mutation = """
    mutation UpdateIssueFields($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue {
          identifier title priority priorityLabel dueDate branchName url
          state { id name type }
          assignee { id name displayName active }
          labels(first: 250) { nodes { id name color } }
          team { id states(first: 50) { nodes { id name type position } } }
        }
      }
    }
    """
    let response = try await graphQL(
      mutation,
      variables: ["id": issueID, "input": input],
      as: LinearUpdateResponse.self
    )
    guard response.data.issueUpdate.success else { throw LinearServiceError.issueUpdateFailed }
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
          issueEstimationType
          issueEstimationAllowZero
          issueEstimationExtended
          inheritIssueEstimation
          parent {
            issueEstimationType
            issueEstimationAllowZero
            issueEstimationExtended
          }
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
    query LinearUsers($first: Int!, $after: String) {
      users(first: $first, after: $after) {
        nodes {
          id
          name
          displayName
          active
        }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    var users: [LinearUserNode] = []
    var after: String?
    repeat {
      var variables: [String: Any] = ["first": 100]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearUsersResponse.self)
      users.append(contentsOf: response.data.users.nodes)
      after = response.data.users.pageInfo.nextCursor
    } while after != nil
    return users
      .map(\.displayItem)
      .filter(\.isActive)
      .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }

  /// Loads visible Linear projects for the issue creator project picker.
  func fetchProjectOptions() async throws -> [LinearProjectOption] {
    let query = """
    query LinearProjects($first: Int!, $after: String, $filter: ProjectFilter) {
      projects(first: $first, after: $after, filter: $filter) {
        nodes { id name teams(first: 250) { nodes { id } } }
        pageInfo { hasNextPage endCursor }
      }
    }
    """

    var projects: [LinearProjectNode] = []
    var after: String?
    repeat {
      var variables: [String: Any] = [
        "first": 20,
        "filter": ["state": ["nin": ["completed", "canceled"]]]
      ]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearProjectsResponse.self)
      projects.append(contentsOf: response.data.projects.nodes)
      after = response.data.projects.pageInfo.nextCursor
    } while after != nil

    return projects
      .map { LinearProjectOption(id: $0.id, name: $0.name, teamIDs: $0.teams.nodes.map(\.id)) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Loads a team's active and upcoming cycles for the issue creator cycle picker, most recent first.
  func fetchCycleOptions(teamID: String) async throws -> [LinearCycleOption] {
    let query = """
    query TeamCycles($id: String!, $first: Int!, $after: String, $filter: CycleFilter) {
      team(id: $id) {
        cycles(first: $first, after: $after, filter: $filter) {
          nodes { id number name }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    var cycles: [LinearCycleNode] = []
    var after: String?
    repeat {
      var variables: [String: Any] = [
        "id": teamID,
        "first": 50,
        "filter": ["or": [["isActive": ["eq": true]], ["isFuture": ["eq": true]]]]
      ]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearCyclesResponse.self)
      guard let connection = response.data.team?.cycles else { break }
      cycles.append(contentsOf: connection.nodes)
      after = connection.pageInfo.nextCursor
    } while after != nil

    return cycles
      .sorted { $0.number > $1.number }
      .map { LinearCycleOption(id: $0.id, number: $0.number, name: $0.name ?? "") }
  }

  /// Loads a team's issue labels for the issue creator label picker.
  func fetchLabelOptions(teamID: String) async throws -> [LinearLabelOption] {
    let query = """
    query TeamLabels($id: String!, $first: Int!, $after: String) {
      team(id: $id) {
        labels(first: $first, after: $after) {
          nodes { id name color }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    var labels: [LinearLabelNode] = []
    var after: String?
    repeat {
      var variables: [String: Any] = ["id": teamID, "first": 50]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearLabelsResponse.self)
      guard let connection = response.data.team?.labels else { break }
      labels.append(contentsOf: connection.nodes)
      after = connection.pageInfo.nextCursor
    } while after != nil

    return labels
      .map { LinearLabelOption(id: $0.id, name: $0.name, color: $0.color) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// Loads a project's milestones for the issue creator milestone picker.
  func fetchMilestoneOptions(projectID: String) async throws -> [LinearMilestoneOption] {
    let query = """
    query ProjectMilestones($id: String!, $first: Int!, $after: String) {
      project(id: $id) {
        projectMilestones(first: $first, after: $after) {
          nodes { id name }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """

    var milestones: [LinearNamedNode] = []
    var after: String?
    repeat {
      var variables: [String: Any] = ["id": projectID, "first": 50]
      if let after { variables["after"] = after }
      let response = try await graphQL(query, variables: variables, as: LinearMilestonesResponse.self)
      guard let connection = response.data.project?.projectMilestones else { break }
      milestones.append(contentsOf: connection.nodes)
      after = connection.pageInfo.nextCursor
    } while after != nil

    return milestones
      .map { LinearMilestoneOption(id: $0.id, name: $0.name) }
  }

  /// Creates a Linear issue from a draft.
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

    let stateID = draft.state.trimmingCharacters(in: .whitespacesAndNewlines)
    if !stateID.isEmpty {
      input["stateId"] = stateID
    }

    if let priority = draft.priority {
      input["priority"] = priority
    }

    if let estimate = draft.estimate {
      input["estimate"] = estimate
    }

    if let dueDate = draft.formattedDueDate {
      input["dueDate"] = dueDate
    }

    if !draft.project.isEmpty {
      input["projectId"] = draft.project

      if !draft.milestone.isEmpty {
        input["projectMilestoneId"] = draft.milestone
      }
    }

    if !draft.cycle.isEmpty {
      input["cycleId"] = draft.cycle
    }

    let parent = draft.parent.trimmingCharacters(in: .whitespacesAndNewlines)
    if !parent.isEmpty {
      input["parentId"] = try await fetchIssueID(identifier: parent)
    }

    if !draft.label.isEmpty {
      input["labelIds"] = [draft.label]
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
}

/// Linear service failure cases.
enum LinearServiceError: LocalizedError {
  /// Linear accepted the mutation but reported failure.
  case statusUpdateFailed

  /// Linear accepted the priority mutation but reported failure.
  case priorityUpdateFailed

  /// Linear accepted the due date mutation but reported failure.
  case dueDateUpdateFailed

  /// Linear accepted a generic issue mutation but reported failure.
  case issueUpdateFailed

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
    case .dueDateUpdateFailed:
      "Linear did not update the issue due date."
    case .issueUpdateFailed:
      "Linear did not update the issue."
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

/// Viewer identity fields used for Settings.
private struct LinearViewerIdentity: Decodable {
  /// Human-readable profile name.
  let name: String

  /// Account email when available.
  let email: String?

  /// Linear username when available.
  let displayName: String?

  var accountLabel: String {
    if let email, !email.isEmpty { return email }
    if let displayName, !displayName.isEmpty { return displayName }
    return name
  }
}

/// Root response for Linear workspace and team discovery.
private struct LinearAccountDiscoveryResponse: Decodable {
  let data: LinearAccountDiscoveryData
}

private struct LinearAccountDiscoveryData: Decodable {
  let viewer: LinearViewerIdentity
  let organization: LinearOrganizationIdentity
  let teams: LinearAccountTeamConnection
}

private struct LinearOrganizationIdentity: Decodable {
  let name: String
}

private struct LinearAccountTeamConnection: Decodable {
  let nodes: [LinearAccountTeamNode]
  let pageInfo: LinearPageInfo
}

private struct LinearAccountTeamNode: Decodable {
  let id: String
  let key: String
  let name: String
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

/// Root GraphQL response shape for the open issue query.
private struct LinearIssuesResponse: Decodable {
  /// GraphQL data payload.
  let data: LinearIssuesData
}

/// Linear GraphQL data payload for the open issue query.
private struct LinearIssuesData: Decodable {
  /// Open issue connection.
  let issues: LinearAssignedIssues
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

/// Project lookup data payload.
private struct LinearProjectsData: Decodable {
  /// Matching projects.
  let projects: LinearProjectConnection
}

/// Project connection payload.
private struct LinearProjectConnection: Decodable {
  /// Matching project nodes.
  let nodes: [LinearProjectNode]

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
}

/// Raw Linear project node with team associations.
private struct LinearProjectNode: Decodable {
  /// Project identifier.
  let id: String

  /// Project name.
  let name: String

  /// Teams the project belongs to.
  let teams: LinearProjectTeamConnection
}

/// Team connection payload for project lookups.
private struct LinearProjectTeamConnection: Decodable {
  /// Associated team nodes.
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

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
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

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
}

/// Raw Linear cycle node.
private struct LinearCycleNode: Decodable {
  /// Cycle identifier.
  let id: String

  /// Cycle number within the team.
  let number: Int

  /// Optional cycle name.
  let name: String?
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
  let nodes: [LinearLabelNode]

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
}

/// Relay cursor metadata shared by paginated Linear option queries.
private struct LinearPageInfo: Decodable {
  let hasNextPage: Bool
  let endCursor: String?

  /// Cursor to request only when Linear reports another page.
  var nextCursor: String? {
    hasNextPage ? endCursor : nil
  }
}

/// Raw Linear label node.
private struct LinearLabelNode: Decodable {
  /// Label identifier.
  let id: String

  /// Label name.
  let name: String

  /// Label color as a hex string.
  let color: String
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

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
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

  /// Team estimation scale.
  let issueEstimationType: String

  /// Whether the team allows an explicit zero estimate.
  let issueEstimationAllowZero: Bool

  /// Whether the team extends its estimation scale.
  let issueEstimationExtended: Bool

  /// Whether the team inherits estimation settings from its parent team.
  let inheritIssueEstimation: Bool

  /// Parent team estimation settings, present for sub-teams.
  let parent: LinearTeamEstimation?

  /// Converts the raw node into a picker option.
  var displayItem: LinearTeamOption {
    let estimation = (inheritIssueEstimation ? parent : nil) ?? LinearTeamEstimation(
      issueEstimationType: issueEstimationType,
      issueEstimationAllowZero: issueEstimationAllowZero,
      issueEstimationExtended: issueEstimationExtended
    )
    return LinearTeamOption(
      id: id,
      key: key,
      name: name,
      states: states.nodes
        .map(\.displayItem)
        .sorted { $0.position < $1.position },
      issueEstimationType: estimation.issueEstimationType,
      issueEstimationAllowZero: estimation.issueEstimationAllowZero,
      issueEstimationExtended: estimation.issueEstimationExtended
    )
  }
}

/// Estimation settings payload shared by teams and their parents.
private struct LinearTeamEstimation: Decodable {
  /// Team estimation scale.
  let issueEstimationType: String

  /// Whether an explicit zero estimate is allowed.
  let issueEstimationAllowZero: Bool

  /// Whether the estimation scale adds two larger values.
  let issueEstimationExtended: Bool
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

  /// Cursor metadata for the next page.
  let pageInfo: LinearPageInfo
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

  /// Suggested git branch name.
  let branchName: String?

  /// Browser URL.
  let url: String?

  /// Current workflow state.
  let state: LinearIssueState

  /// Owning Linear team.
  let team: LinearIssueTeam

  /// Current issue labels.
  let labels: LinearIssueLabelConnection

  /// Current singular assignee.
  let assignee: LinearUserNode?

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
      teamID: team.id,
      labels: labels.nodes.map { LinearLabelOption(id: $0.id, name: $0.name, color: $0.color) },
      assignee: assignee?.displayItem,
      dueDate: dueDate,
      branchName: branchName,
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
  /// Stable team identifier.
  let id: String

  /// Workflow states connection.
  let states: LinearWorkflowStateConnection
}

/// Current labels connection embedded in issue payloads.
private struct LinearIssueLabelConnection: Decodable {
  let nodes: [LinearLabelNode]
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

import Foundation

/// Errors surfaced by GitHub REST API calls.
enum GitHubServiceError: LocalizedError {
  case httpError(Int, String?)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .httpError(let status, let detail):
      detail.map { "GitHub error \(status): \($0)" } ?? "GitHub error \(status)."
    case .invalidResponse:
      "GitHub returned an unexpected response."
    }
  }
}

/// Fetches and mutates issues for the signed-in GitHub user.
struct GitHubService: Sendable {
  private let session: URLSession = .shared
  private let auth: GitHubDeviceAuthService = .shared

  func fetchAccountLabel() async throws -> String {
    let user: UserResponse = try await request(URL(string: "https://api.github.com/user")!)
    return user.login
  }

  /// Returns every repository accessible with the existing OAuth token.
  func fetchRepositories() async throws -> [GitHubRepository] {
    let query = """
    query AccessibleRepositories($after: String) {
      viewer {
        repositories(
          first: 100
          after: $after
          affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]
          orderBy: { field: NAME, direction: ASC }
        ) {
          nodes { nameWithOwner hasIssuesEnabled }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
    """
    var repositories: [GitHubGraphQLRepository] = []
    var after: String?
    repeat {
      var variables: [String: Any] = [:]
      if let after { variables["after"] = after }
      let response: GitHubGraphQLResponse = try await request(
        URL(string: "https://api.github.com/graphql")!,
        method: "POST",
        body: ["query": query, "variables": variables]
      )
      repositories.append(contentsOf: response.data.viewer.repositories.nodes)
      after = response.data.viewer.repositories.pageInfo.hasNextPage
        ? response.data.viewer.repositories.pageInfo.endCursor
        : nil
    } while after != nil
    return repositories
      .filter(\.hasIssuesEnabled)
      .map { GitHubRepository(fullName: $0.nameWithOwner, isEnabled: true) }
  }

  /// Returns up to 25 assigned open issues from enabled repositories.
  /// Search pages are filtered only after fetching so disabled repositories cannot consume the cap.
  func fetchAssignedIssues(enabledRepositories: Set<String>) async throws -> [GitHubIssueItem] {
    guard !enabledRepositories.isEmpty else { return [] }
    let enabled = Set(enabledRepositories.map { $0.lowercased() })
    var page = 1
    var issues: [GitHubIssueItem] = []
    while issues.count < 25 {
      var components = URLComponents(string: "https://api.github.com/issues")!
      components.queryItems = [
        URLQueryItem(name: "filter", value: "assigned"),
        URLQueryItem(name: "state", value: "open"),
        URLQueryItem(name: "sort", value: "updated"),
        URLQueryItem(name: "direction", value: "desc"),
        URLQueryItem(name: "per_page", value: "100"),
        URLQueryItem(name: "page", value: String(page))
      ]
      let batch: [SearchItem] = try await request(components.url!)
      issues.append(contentsOf: batch.compactMap { item in
        guard item.pullRequest == nil,
              let repo = Self.repoFullName(from: item.repositoryURL),
              enabled.contains(repo.lowercased()) else {
          return nil
        }
        return item.displayItem(repoFullName: repo)
      })
      guard batch.count == 100 else { break }
      page += 1
    }
    return Array(issues.prefix(25))
  }

  /// Returns up to 25 open issues from enabled repositories, not only assigned ones.
  func fetchOpenIssues(enabledRepositories: Set<String>) async throws -> [GitHubIssueItem] {
    let repositories = Array(enabledRepositories)
    var collected: [GitHubIssueItem] = []
    // Fetch in bounded chunks so users with many enabled repositories stay
    // clear of GitHub's secondary rate limits.
    for chunkStart in stride(from: 0, to: repositories.count, by: 8) {
      let chunk = repositories[chunkStart..<min(chunkStart + 8, repositories.count)]
      let chunkIssues = try await withThrowingTaskGroup(of: [GitHubIssueItem].self) { group in
        for repo in chunk {
          group.addTask {
            // A failing repository must not take down the whole feed, but
            // auth and cancellation errors must still propagate.
            do {
              return try await self.fetchRepoIssues(repoFullName: repo)
            } catch {
              if error is OAuthError || error is CancellationError {
                throw error
              }
              if let urlError = error as? URLError, urlError.code == .cancelled {
                throw error
              }
              return []
            }
          }
        }
        var batch: [GitHubIssueItem] = []
        for try await issues in group {
          batch.append(contentsOf: issues)
        }
        return batch
      }
      collected.append(contentsOf: chunkIssues)
    }
    return Array(
      collected
        .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        .prefix(25)
    )
  }

  /// Returns open issues (excluding pull requests) from one repository.
  /// Pages until enough real issues are collected since pull requests share the feed.
  private func fetchRepoIssues(repoFullName repo: String) async throws -> [GitHubIssueItem] {
    var page = 1
    var issues: [GitHubIssueItem] = []
    while issues.count < 25, page <= 3 {
      var components = URLComponents(string: "https://api.github.com/repos/\(repo)/issues")!
      components.queryItems = [
        URLQueryItem(name: "state", value: "open"),
        URLQueryItem(name: "sort", value: "updated"),
        URLQueryItem(name: "direction", value: "desc"),
        URLQueryItem(name: "per_page", value: "100"),
        URLQueryItem(name: "page", value: String(page))
      ]
      let batch: [SearchItem] = try await request(components.url!)
      issues.append(contentsOf: batch.compactMap { item in
        guard item.pullRequest == nil else { return nil }
        return item.displayItem(repoFullName: repo)
      })
      guard batch.count == 100 else { break }
      page += 1
    }
    return issues
  }

  func fetchLabels(repoFullName: String) async throws -> [GitHubLabelOption] {
    try await fetchPaged(repoFullName: repoFullName, suffix: "labels", as: LabelResponse.self)
      .map(\.displayItem)
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  func fetchAssignees(repoFullName: String) async throws -> [GitHubAssigneeOption] {
    try await fetchPaged(repoFullName: repoFullName, suffix: "assignees", as: UserResponse.self)
      .map { GitHubAssigneeOption(login: $0.login) }
      .sorted { $0.login.localizedStandardCompare($1.login) == .orderedAscending }
  }

  /// Creates an issue and returns it for optimistic display before indexes catch up.
  @discardableResult
  func createIssue(repoFullName: String, title: String, body: String, labels: [String], assignees: [String]) async throws -> GitHubIssueItem {
    var payload: [String: Any] = ["title": title]
    if !body.isEmpty { payload["body"] = body }
    if !labels.isEmpty { payload["labels"] = labels }
    if !assignees.isEmpty { payload["assignees"] = assignees }
    let created: CreatedIssueResponse = try await request(
      try endpoint(repoFullName: repoFullName, suffix: "issues"),
      method: "POST",
      body: payload
    )
    return GitHubIssueItem(
      id: created.nodeID,
      title: created.title,
      repoFullName: repoFullName,
      number: created.number,
      url: URL(string: created.htmlURL),
      updatedAt: created.updatedAt,
      labels: created.labels.map(\.displayItem),
      assignees: created.assignees.map { GitHubAssigneeOption(login: $0.login) }
    )
  }

  func updateIssueState(repoFullName: String, number: Int, isOpen: Bool) async throws {
    let _: IssueMutationResponse = try await request(
      try endpoint(repoFullName: repoFullName, suffix: "issues/\(number)"),
      method: "PATCH",
      body: ["state": isOpen ? "open" : "closed"]
    )
  }

  func updateIssueLabels(repoFullName: String, number: Int, labels: [String]) async throws {
    let _: [LabelResponse] = try await request(
      try endpoint(repoFullName: repoFullName, suffix: "issues/\(number)/labels"),
      method: "PUT",
      body: ["labels": labels]
    )
  }

  func updateIssueAssignees(repoFullName: String, number: Int, assignees: [String]) async throws {
    let _: AssigneesResponse = try await request(
      try endpoint(repoFullName: repoFullName, suffix: "issues/\(number)"),
      method: "PATCH",
      body: ["assignees": assignees]
    )
  }

  private func fetchPaged<Response: Decodable & Sendable>(
    repoFullName: String,
    suffix: String,
    as type: Response.Type
  ) async throws -> [Response] {
    var page = 1
    var values: [Response] = []
    repeat {
      var components = URLComponents(url: try endpoint(repoFullName: repoFullName, suffix: suffix), resolvingAgainstBaseURL: false)!
      components.queryItems = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
      let batch: [Response] = try await request(components.url!)
      values.append(contentsOf: batch)
      guard batch.count == 100 else { break }
      page += 1
    } while true
    return values
  }

  private func endpoint(repoFullName: String, suffix: String) throws -> URL {
    guard let url = URL(string: "https://api.github.com/repos/\(repoFullName)/\(suffix)") else {
      throw GitHubServiceError.invalidResponse
    }
    return url
  }

  private func request<Response: Decodable & Sendable>(
    _ url: URL,
    method: String = "GET",
    body: [String: Any]? = nil
  ) async throws -> Response {
    guard let token = await auth.accessToken() else { throw OAuthError.notSignedIn }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if status == 401 { throw OAuthError.reauthenticationRequired }
      let detail = (try? JSONDecoder().decode(MessageEnvelope.self, from: data))?.message
      throw GitHubServiceError.httpError(status, detail)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    guard let decoded = try? decoder.decode(Response.self, from: data) else {
      throw GitHubServiceError.invalidResponse
    }
    return decoded
  }

  private static func repoFullName(from repositoryURL: String) -> String? {
    guard let url = URL(string: repositoryURL) else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 3, parts[0] == "repos" else { return nil }
    return "\(parts[1])/\(parts[2])"
  }

  private struct GitHubGraphQLResponse: Decodable, Sendable { let data: GitHubGraphQLData }
  private struct GitHubGraphQLData: Decodable, Sendable { let viewer: GitHubGraphQLViewer }
  private struct GitHubGraphQLViewer: Decodable, Sendable { let repositories: GitHubGraphQLRepositoryConnection }
  private struct GitHubGraphQLRepositoryConnection: Decodable, Sendable {
    let nodes: [GitHubGraphQLRepository]
    let pageInfo: GitHubGraphQLPageInfo
  }
  private struct GitHubGraphQLRepository: Decodable, Sendable {
    let nameWithOwner: String
    let hasIssuesEnabled: Bool
  }
  private struct GitHubGraphQLPageInfo: Decodable, Sendable {
    let hasNextPage: Bool
    let endCursor: String?
  }
  private struct UserResponse: Decodable, Sendable { let login: String }
  private struct SearchItem: Decodable, Sendable {
    let nodeID: String
    let title: String
    let number: Int
    let htmlURL: String
    let repositoryURL: String
    let updatedAt: Date?
    let labels: [LabelResponse]
    let assignees: [UserResponse]
    let pullRequest: PullRequestMarker?

    var baseItem: (labels: [GitHubLabelOption], assignees: [GitHubAssigneeOption]) {
      (labels.map(\.displayItem), assignees.map { GitHubAssigneeOption(login: $0.login) })
    }

    func displayItem(repoFullName: String) -> GitHubIssueItem {
      GitHubIssueItem(
        id: nodeID,
        title: title,
        repoFullName: repoFullName,
        number: number,
        url: URL(string: htmlURL),
        updatedAt: updatedAt,
        labels: labels.map(\.displayItem),
        assignees: assignees.map { GitHubAssigneeOption(login: $0.login) }
      )
    }

    enum CodingKeys: String, CodingKey {
      case nodeID = "nodeId", title, number, htmlURL = "htmlUrl", repositoryURL = "repositoryUrl", updatedAt, labels, assignees, pullRequest
    }
  }
  private struct PullRequestMarker: Decodable, Sendable {}
  private struct LabelResponse: Decodable, Sendable {
    let name: String
    let color: String
    var displayItem: GitHubLabelOption { GitHubLabelOption(name: name, color: color) }
  }
  private struct IssueMutationResponse: Decodable, Sendable { let id: Int }

  /// Response of the create-issue endpoint; lacks `repositoryUrl`, so the repo is filled in by the caller.
  private struct CreatedIssueResponse: Decodable, Sendable {
    let nodeID: String
    let title: String
    let number: Int
    let htmlURL: String
    let updatedAt: Date?
    let labels: [LabelResponse]
    let assignees: [UserResponse]

    enum CodingKeys: String, CodingKey {
      case nodeID = "nodeId", title, number, htmlURL = "htmlUrl", updatedAt, labels, assignees
    }
  }
  private struct AssigneesResponse: Decodable, Sendable { let assignees: [UserResponse] }
  private struct MessageEnvelope: Decodable, Sendable { let message: String? }
}

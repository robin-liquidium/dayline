import Foundation

/// Errors surfaced by GitHub REST API calls.
enum GitHubServiceError: LocalizedError {
  /// GitHub rejected the request.
  case httpError(Int, String?)

  /// The response could not be decoded.
  case invalidResponse

  /// Human-readable error text.
  var errorDescription: String? {
    switch self {
    case .httpError(let status, let detail):
      detail.map { "GitHub error \(status): \($0)" } ?? "GitHub error \(status)."
    case .invalidResponse:
      "GitHub returned an unexpected response."
    }
  }
}

/// Fetches the signed-in user's assigned GitHub issues over REST.
struct GitHubService: Sendable {
  private let session: URLSession = .shared
  private let auth: GitHubDeviceAuthService = .shared

  /// Returns the signed-in user's GitHub login handle.
  func fetchAccountLabel() async throws -> String {
    let user: UserResponse = try await get(URL(string: "https://api.github.com/user")!)
    return user.login
  }

  /// Returns open issues assigned to the signed-in user, most recently updated first.
  func fetchAssignedIssues() async throws -> [GitHubIssueItem] {
    var components = URLComponents(string: "https://api.github.com/search/issues")!
    components.queryItems = [
      URLQueryItem(name: "q", value: "is:issue is:open assignee:@me"),
      URLQueryItem(name: "sort", value: "updated"),
      URLQueryItem(name: "order", value: "desc"),
      URLQueryItem(name: "per_page", value: "25")
    ]

    let result: SearchResponse = try await get(components.url!)
    return result.items.compactMap { item in
      guard let repoFullName = Self.repoFullName(from: item.repositoryURL) else {
        return nil
      }
      return GitHubIssueItem(
        id: item.nodeID,
        title: item.title,
        repoFullName: repoFullName,
        number: item.number,
        url: URL(string: item.htmlURL),
        updatedAt: item.updatedAt
      )
    }
  }

  /// Sends one authorized GET and decodes the JSON response.
  private func get<Response: Decodable & Sendable>(_ url: URL) async throws -> Response {
    guard let token = await auth.accessToken() else {
      throw OAuthError.notSignedIn
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0

    guard (200..<300).contains(status) else {
      if status == 401 {
        throw OAuthError.reauthenticationRequired
      }
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

  /// Extracts `owner/name` from a repository API URL.
  private static func repoFullName(from repositoryURL: String) -> String? {
    guard let url = URL(string: repositoryURL) else {
      return nil
    }
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 3, parts[0] == "repos" else {
      return nil
    }
    return "\(parts[1])/\(parts[2])"
  }

  /// Signed-in user payload.
  private struct UserResponse: Decodable, Sendable {
    let login: String
  }

  /// Issue search payload.
  private struct SearchResponse: Decodable, Sendable {
    let items: [SearchItem]
  }

  /// One issue search result.
  private struct SearchItem: Decodable, Sendable {
    let nodeID: String
    let title: String
    let number: Int
    let htmlURL: String
    let repositoryURL: String
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
      case nodeID = "nodeId"
      case title
      case number
      case htmlURL = "htmlUrl"
      case repositoryURL = "repositoryUrl"
      case updatedAt
    }
  }

  /// GitHub error envelope.
  private struct MessageEnvelope: Decodable, Sendable {
    let message: String?
  }
}

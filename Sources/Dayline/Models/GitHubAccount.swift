import Foundation

/// One repository accessible to the connected GitHub account.
struct GitHubRepository: Codable, Identifiable, Equatable, Sendable {
  var id: String { fullName }
  let fullName: String
  var isEnabled: Bool
}

/// Persisted non-secret GitHub account preferences.
struct GitHubAccount: Codable, Equatable, Sendable {
  var repositories: [GitHubRepository]

  /// Preserves explicit choices, removes inaccessible repositories, and enables new discoveries.
  func reconcilingRepositories(_ discovered: [GitHubRepository]) -> GitHubAccount {
    let selections = Dictionary(uniqueKeysWithValues: repositories.map { ($0.fullName.lowercased(), $0.isEnabled) })
    return GitHubAccount(repositories: discovered.map { repository in
      GitHubRepository(
        fullName: repository.fullName,
        isEnabled: selections[repository.fullName.lowercased()] ?? true
      )
    }.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending })
  }
}

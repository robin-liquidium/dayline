import Foundation

/// Persists GitHub repository selections locally.
struct GitHubAccountRepository {
  static let defaultsKey = "githubAccount"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() throws -> GitHubAccount {
    guard let data = defaults.data(forKey: Self.defaultsKey) else {
      return GitHubAccount(repositories: [])
    }
    return try JSONDecoder().decode(GitHubAccount.self, from: data)
  }

  func save(_ account: GitHubAccount) throws {
    defaults.set(try JSONEncoder().encode(account), forKey: Self.defaultsKey)
  }
}

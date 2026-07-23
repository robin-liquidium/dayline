import Foundation

/// Persists Linear workspace identity and team selections locally.
struct LinearAccountRepository {
  static let defaultsKey = "linearAccount"

  let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() throws -> LinearAccount {
    guard let data = defaults.data(forKey: Self.defaultsKey) else {
      return LinearAccount(workspaceName: "", userLabel: "", teams: [])
    }
    return try JSONDecoder().decode(LinearAccount.self, from: data)
  }

  func save(_ account: LinearAccount) throws {
    defaults.set(try JSONEncoder().encode(account), forKey: Self.defaultsKey)
  }
}

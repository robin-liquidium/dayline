import Foundation
import Testing
@testable import Dayline

struct GitHubAccountRepositoryTests {
  @Test func reconciliationPreservesSelectionsDropsMissingAndEnablesNewRepositories() {
    let account = GitHubAccount(repositories: [
      GitHubRepository(fullName: "Org/Disabled", isEnabled: false),
      GitHubRepository(fullName: "Org/Removed", isEnabled: true)
    ])

    let reconciled = account.reconcilingRepositories([
      GitHubRepository(fullName: "org/disabled", isEnabled: true),
      GitHubRepository(fullName: "Org/New", isEnabled: false)
    ])

    #expect(reconciled.repositories.map(\.fullName) == ["org/disabled", "Org/New"])
    #expect(reconciled.repositories[0].isEnabled == false)
    #expect(reconciled.repositories[1].isEnabled == true)
  }

  @Test func repositoryRoundTripPreservesAnExplicitEmptySelection() throws {
    let suiteName = "GitHubAccountRepositoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let repository = GitHubAccountRepository(defaults: defaults)
    let account = GitHubAccount(repositories: [
      GitHubRepository(fullName: "Org/One", isEnabled: false),
      GitHubRepository(fullName: "Org/Two", isEnabled: false)
    ])

    try repository.save(account)

    #expect(try repository.load() == account)
    #expect(try repository.load().repositories.filter(\.isEnabled).isEmpty)
  }
}

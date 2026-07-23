import Foundation
import Testing
@testable import Dayline

struct LinearAccountRepositoryTests {
  @Test func reconciliationPreservesSelectionsDropsMissingAndEnablesNewTeams() {
    let account = LinearAccount(
      workspaceName: "Old Workspace",
      userLabel: "old@example.com",
      teams: [
        LinearTeamSelection(id: "disabled", key: "DIS", name: "Disabled", isEnabled: false),
        LinearTeamSelection(id: "removed", key: "REM", name: "Removed", isEnabled: true)
      ]
    )

    let reconciled = account.reconciling(
      workspaceName: "New Workspace",
      userLabel: "new@example.com",
      teams: [
        LinearTeamSelection(id: "disabled", key: "DIS", name: "Disabled", isEnabled: true),
        LinearTeamSelection(id: "new", key: "NEW", name: "New", isEnabled: false)
      ]
    )

    #expect(reconciled.workspaceName == "New Workspace")
    #expect(reconciled.userLabel == "new@example.com")
    #expect(reconciled.hasDiscoveredTeams)
    #expect(reconciled.teams.map(\.id) == ["disabled", "new"])
    #expect(reconciled.teams[0].isEnabled == false)
    #expect(reconciled.teams[1].isEnabled == true)
  }

  @Test func repositoryRoundTripPreservesAnExplicitEmptySelection() throws {
    let suiteName = "LinearAccountRepositoryTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let repository = LinearAccountRepository(defaults: defaults)
    let account = LinearAccount(
      workspaceName: "Dayline",
      userLabel: "alex@example.com",
      teams: [LinearTeamSelection(id: "team", key: "DAY", name: "Dayline", isEnabled: false)],
      hasDiscoveredTeams: true
    )

    try repository.save(account)

    #expect(try repository.load() == account)
    #expect(try repository.load().teams.filter(\.isEnabled).isEmpty)
  }
}

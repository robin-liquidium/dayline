import Foundation

/// One Linear team available to the connected account.
struct LinearTeamSelection: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let key: String
  let name: String
  var isEnabled: Bool

  var label: String {
    "\(key) - \(name)"
  }
}

/// Persisted non-secret Linear account identity and team selections.
struct LinearAccount: Codable, Equatable, Sendable {
  var workspaceName: String
  var userLabel: String
  var teams: [LinearTeamSelection]
  var hasDiscoveredTeams: Bool = false

  /// Preserves explicit choices, removes unavailable teams, and enables new discoveries.
  func reconciling(
    workspaceName: String,
    userLabel: String,
    teams discoveredTeams: [LinearTeamSelection]
  ) -> LinearAccount {
    let selections = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.isEnabled) })
    return LinearAccount(
      workspaceName: workspaceName,
      userLabel: userLabel,
      teams: discoveredTeams.map { team in
        LinearTeamSelection(
          id: team.id,
          key: team.key,
          name: team.name,
          isEnabled: selections[team.id] ?? true
        )
      }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
      hasDiscoveredTeams: true
    )
  }
}

/// Fresh account identity and team catalog returned by Linear.
struct LinearAccountDiscovery: Sendable {
  let workspaceName: String
  let userLabel: String
  let teams: [LinearTeamSelection]
}

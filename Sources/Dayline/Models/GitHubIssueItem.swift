import Foundation

/// One open GitHub issue assigned to the signed-in user.
struct GitHubIssueItem: Identifiable, Equatable, Sendable {
  /// Stable node identifier from the GitHub API.
  let id: String

  /// Issue title.
  let title: String

  /// Owning repository in `owner/name` form.
  let repoFullName: String

  /// Issue number inside the repository.
  let number: Int

  /// Browser URL for the issue.
  let url: URL?

  /// Last update timestamp reported by GitHub.
  let updatedAt: Date?

  /// Labels currently applied to the issue.
  let labels: [GitHubLabelOption]

  /// Users currently assigned to the issue.
  let assignees: [GitHubAssigneeOption]

  /// Compact `owner/name#123` reference for row metadata.
  var reference: String {
    "\(repoFullName)#\(number)"
  }

  func replacing(
    labels: [GitHubLabelOption]? = nil,
    assignees: [GitHubAssigneeOption]? = nil
  ) -> GitHubIssueItem {
    GitHubIssueItem(
      id: id, title: title, repoFullName: repoFullName, number: number, url: url,
      updatedAt: updatedAt, labels: labels ?? self.labels, assignees: assignees ?? self.assignees
    )
  }
}

/// One GitHub repository label available to an issue.
struct GitHubLabelOption: Identifiable, Equatable, Sendable {
  var id: String { name }
  let name: String
  let color: String
}

/// One GitHub repository collaborator eligible for assignment.
struct GitHubAssigneeOption: Identifiable, Equatable, Sendable {
  var id: String { login }
  let login: String
}

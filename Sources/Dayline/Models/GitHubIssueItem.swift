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

  /// Compact `owner/name#123` reference for row metadata.
  var reference: String {
    "\(repoFullName)#\(number)"
  }
}

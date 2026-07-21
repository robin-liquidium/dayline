import Foundation

/// What the Linear issue copy shortcut places on the clipboard.
enum LinearCopyStyle: String, CaseIterable, Identifiable {
  /// The full browser URL of the Linear issue.
  case link

  /// Linear's suggested git branch name for the issue.
  case branchName

  /// Identifiable conformance for picker lists.
  var id: String {
    rawValue
  }

  /// Human-readable settings label.
  var label: String {
    switch self {
    case .link:
      "Issue link"
    case .branchName:
      "Git branch name"
    }
  }
}

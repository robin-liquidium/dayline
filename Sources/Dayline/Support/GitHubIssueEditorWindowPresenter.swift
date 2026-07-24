import AppKit

/// Brings the GitHub issue creator window forward for the menu-bar accessory app.
enum GitHubIssueEditorWindowPresenter {
  /// Activates the app and orders the newest GitHub issue creator window to the front.
  static func bringIssueWindowToFront() {
    WindowPresenterSupport.bringWindowToFront(titled: ["New GitHub Issue"])
  }
}

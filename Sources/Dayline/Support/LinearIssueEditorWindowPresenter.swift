import AppKit

/// Brings the Linear issue creator window forward for the menu-bar accessory app.
enum LinearIssueEditorWindowPresenter {
  /// Activates the app and orders the newest Linear issue creator window to the front.
  static func bringIssueWindowToFront() {
    WindowPresenterSupport.bringWindowToFront(titled: ["New Linear Issue"])
  }
}

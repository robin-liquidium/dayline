import AppKit

/// Brings the Linear issue creator window forward for the menu-bar accessory app.
enum LinearIssueEditorWindowPresenter {
  /// Activates the app and orders the newest Linear issue creator window to the front.
  static func bringIssueWindowToFront() {
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      orderIssueWindowFront()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.activate(ignoringOtherApps: true)
      orderIssueWindowFront()
    }
  }

  /// Finds the SwiftUI-created issue window and makes it key/frontmost.
  private static func orderIssueWindowFront() {
    let issueWindow = NSApp.windows.reversed().first { window in
      window.title == "New Linear Issue"
    }

    issueWindow?.makeKeyAndOrderFront(nil)
    issueWindow?.orderFrontRegardless()
  }
}

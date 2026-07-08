import AppKit

/// Shared window activation helper for SwiftUI windows in the menu-bar app.
enum WindowPresenterSupport {
  /// Activates the app and orders the newest matching window to the front.
  static func bringWindowToFront(titled titles: Set<String>) {
    activateAndOrderWindow(titled: titles)

    DispatchQueue.main.async {
      activateAndOrderWindow(titled: titles)
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      activateAndOrderWindow(titled: titles)
    }
  }

  /// Activates the app before trying to foreground a matching window.
  private static func activateAndOrderWindow(titled titles: Set<String>) {
    NSApp.activate()
    orderWindowFront(titled: titles)
  }

  /// Finds a SwiftUI-created window by title and makes it key/frontmost.
  private static func orderWindowFront(titled titles: Set<String>) {
    let matchingWindow = NSApp.windows.reversed().first { window in
      titles.contains(window.title)
    }

    matchingWindow?.makeKeyAndOrderFront(nil)
    matchingWindow?.orderFrontRegardless()
  }
}

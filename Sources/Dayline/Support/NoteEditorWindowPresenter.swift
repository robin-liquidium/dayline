import AppKit

/// Brings note editor windows forward for the menu-bar accessory app.
enum NoteEditorWindowPresenter {
  /// Activates the app and orders the newest note editor window to the front.
  static func bringNoteWindowToFront() {
    NSApp.activate(ignoringOtherApps: true)

    DispatchQueue.main.async {
      NSApp.activate(ignoringOtherApps: true)
      orderNoteWindowFront()
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      NSApp.activate(ignoringOtherApps: true)
      orderNoteWindowFront()
    }
  }

  /// Finds a note editor window SwiftUI created and makes it key/frontmost.
  private static func orderNoteWindowFront() {
    let noteWindow = NSApp.windows.reversed().first { window in
      window.title == "Note" || window.title == "New Note"
    }

    noteWindow?.makeKeyAndOrderFront(nil)
    noteWindow?.orderFrontRegardless()
  }
}

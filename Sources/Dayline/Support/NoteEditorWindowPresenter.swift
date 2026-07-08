import AppKit

/// Brings note editor windows forward for the menu-bar accessory app.
enum NoteEditorWindowPresenter {
  /// Activates the app and orders the newest note editor window to the front.
  static func bringNoteWindowToFront() {
    WindowPresenterSupport.bringWindowToFront(titled: ["Note", "New Note"])
  }
}

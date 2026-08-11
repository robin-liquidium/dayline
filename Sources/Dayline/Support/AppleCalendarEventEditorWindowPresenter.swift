import AppKit

/// Brings the Apple Calendar event creator forward for the menu-bar accessory app.
enum AppleCalendarEventEditorWindowPresenter {
  static func bringEventWindowToFront() {
    WindowPresenterSupport.bringWindowToFront(titled: ["New Apple Calendar Event"])
  }
}

import AppKit

/// Brings the Apple Reminder creator window forward for the menu-bar accessory app.
enum AppleReminderEditorWindowPresenter {
  static func bringReminderWindowToFront() {
    WindowPresenterSupport.bringWindowToFront(titled: ["New Apple Reminder"])
  }
}

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Dayline

struct GlobalShortcutTests {
  @Test func defaultsDoNotConflictWithEachOther() {
    let defaults = [
      GlobalShortcut.newNoteDefault,
      GlobalShortcut.newLinearIssueDefault,
      GlobalShortcut.openGoogleCalendarDefault,
      GlobalShortcut.newGitHubIssueDefault
    ]
    #expect(Set(defaults.map { "\($0.keyCode)-\($0.carbonModifiers)" }).count == defaults.count)
    #expect(GlobalShortcut.newGitHubIssueFallbacks.allSatisfy { $0 != GlobalShortcut.newNoteDefault })
    #expect(GlobalShortcut.newGitHubIssueFallbacks.allSatisfy { $0 != GlobalShortcut.newLinearIssueDefault })
    #expect(GlobalShortcut.newGitHubIssueFallbacks.allSatisfy { $0 != GlobalShortcut.openGoogleCalendarDefault })
  }

  @Test func defaultsUseControlOptionCommand() {
    let expectedModifiers = UInt32(controlKey | optionKey | cmdKey)
    #expect(GlobalShortcut.newNoteDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.newLinearIssueDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.openGoogleCalendarDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.newGitHubIssueDefault.carbonModifiers == expectedModifiers)
  }

  @Test func codableRoundTrip() throws {
    let shortcut = GlobalShortcut(keyCode: 45, carbonModifiers: UInt32(controlKey | cmdKey))
    let data = try JSONEncoder().encode(shortcut)
    #expect(try JSONDecoder().decode(GlobalShortcut.self, from: data) == shortcut)
  }

  @Test func displayStringShowsModifiersAndKey() {
    #expect(GlobalShortcut.newNoteDefault.displayString.hasPrefix("⌃⌥⌘"))
    #expect(GlobalShortcut.newNoteDefault.displayString.hasSuffix("N"))
    #expect(GlobalShortcut.newLinearIssueDefault.displayString.hasSuffix("L"))
    #expect(GlobalShortcut.openGoogleCalendarDefault.displayString.hasSuffix("C"))
    #expect(GlobalShortcut.newGitHubIssueDefault.displayString.hasSuffix("G"))
  }

  @Test func eventWithoutCommandControlOrOptionIsRejected() {
    let event = makeKeyEvent(keyCode: UInt16(kVK_ANSI_N), modifiers: [])
    #expect(GlobalShortcut(event: event) == nil)

    let shiftOnly = makeKeyEvent(keyCode: UInt16(kVK_ANSI_N), modifiers: [.shift])
    #expect(GlobalShortcut(event: shiftOnly) == nil)
  }

  @Test func eventCaptureKeepsKeyCodeAndModifiers() {
    let event = makeKeyEvent(
      keyCode: UInt16(kVK_ANSI_L),
      modifiers: [.control, .option, .command]
    )
    let shortcut = GlobalShortcut(event: event)
    #expect(shortcut?.keyCode == UInt32(kVK_ANSI_L))
    #expect(shortcut?.carbonModifiers == UInt32(controlKey | optionKey | cmdKey))
  }

  @MainActor
  @Test func persistedHoverShortcutCollisionIsRepairedWithoutChangingExistingActions() {
    let repaired = StatusStore.repairedHoverHotkeys(
      copy: "c",
      status: "d",
      priority: "p",
      dueDate: "d",
      label: "c",
      assignee: "a"
    )

    #expect(repaired == ["c", "d", "p", "e", "l", "a"])
    #expect(Set(repaired).count == 6)
  }

  @MainActor
  @Test func emptyHoverShortcutInputNeverMatchesAnAction() {
    #expect(!StatusStore.hotkeyMatches("", configured: "c"))
    #expect(!StatusStore.hotkeyMatches("   ", configured: "s"))
    #expect(StatusStore.hotkeyMatches("L", configured: "l"))
  }

  /// Builds a synthetic key event for recorder tests.
  private func makeKeyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "n",
      charactersIgnoringModifiers: "n",
      isARepeat: false,
      keyCode: keyCode
    )!
  }
}

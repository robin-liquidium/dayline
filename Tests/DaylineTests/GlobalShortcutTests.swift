import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Dayline

struct GlobalShortcutTests {
  @Test func allDefaultsAndFallbacksArePairwiseUnique() {
    // Each fallback list starts with its own default shortcut.
    #expect(GlobalShortcut.newGitHubIssueFallbacks.first == GlobalShortcut.newGitHubIssueDefault)
    #expect(GlobalShortcut.openGoogleCalendarFallbacks.first == GlobalShortcut.openGoogleCalendarDefault)
    #expect(GlobalShortcut.newAppleReminderFallbacks.first == GlobalShortcut.newAppleReminderDefault)
    let shortcuts = [
      GlobalShortcut.newNoteDefault,
      GlobalShortcut.newLinearIssueDefault
    ] + GlobalShortcut.newGitHubIssueFallbacks
      + GlobalShortcut.openGoogleCalendarFallbacks
      + GlobalShortcut.newAppleReminderFallbacks
    #expect(Set(shortcuts.map { "\($0.keyCode)-\($0.carbonModifiers)" }).count == shortcuts.count)
  }

  @Test func defaultsUseControlOptionCommand() {
    let expectedModifiers = UInt32(controlKey | optionKey | cmdKey)
    #expect(GlobalShortcut.newNoteDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.newLinearIssueDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.openGoogleCalendarDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.newGitHubIssueDefault.carbonModifiers == expectedModifiers)
    #expect(GlobalShortcut.newAppleReminderDefault.carbonModifiers == expectedModifiers)
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
    #expect(GlobalShortcut.newAppleReminderDefault.displayString.hasSuffix("R"))
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

  @MainActor
  @Test func recorderStopsConsumingKeysAfterRecordingEnds() {
    let recorder = ShortcutCaptureNSView()
    let event = makeKeyEvent(keyCode: UInt16(kVK_ANSI_N), modifiers: [.command])
    var capturedKeys = 0
    recorder.onKeyDown = { _ in capturedKeys += 1 }

    recorder.isRecording = true
    #expect(recorder.performKeyEquivalent(with: event))
    #expect(capturedKeys == 1)

    recorder.isRecording = false
    recorder.keyDown(with: event)
    #expect(!recorder.performKeyEquivalent(with: event))
    #expect(capturedKeys == 1)
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

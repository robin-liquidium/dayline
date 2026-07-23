import AppKit
import Carbon.HIToolbox

/// A recorded global keyboard shortcut stored as a Carbon key code and modifiers.
struct GlobalShortcut: Codable, Equatable {
  /// Carbon virtual key code of the non-modifier key.
  var keyCode: UInt32

  /// Carbon modifier mask (cmdKey/optionKey/controlKey/shiftKey).
  var carbonModifiers: UInt32

  /// Default global shortcut for creating a new note: Control+Option+Command+N.
  static let newNoteDefault = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_N),
    carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
  )

  /// Default global shortcut for creating a new Linear issue: Control+Option+Command+L.
  static let newLinearIssueDefault = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_L),
    carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
  )

  /// Default global shortcut for opening Google Calendar: Control+Option+Command+C.
  static let openGoogleCalendarDefault = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_C),
    carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
  )

  /// Default global shortcut for creating a new GitHub issue: Control+Option+Command+G.
  static let newGitHubIssueDefault = GlobalShortcut(
    keyCode: UInt32(kVK_ANSI_G),
    carbonModifiers: UInt32(controlKey | optionKey | cmdKey)
  )

  /// GitHub issue shortcut fallbacks used when another saved shortcut already uses G.
  static let newGitHubIssueFallbacks = [
    newGitHubIssueDefault,
    GlobalShortcut(keyCode: UInt32(kVK_ANSI_J), carbonModifiers: UInt32(controlKey | optionKey | cmdKey)),
    GlobalShortcut(keyCode: UInt32(kVK_ANSI_B), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
  ]

  /// Calendar shortcut fallbacks used only when an existing saved shortcut already uses C.
  static let openGoogleCalendarFallbacks = [
    openGoogleCalendarDefault,
    GlobalShortcut(keyCode: UInt32(kVK_ANSI_G), carbonModifiers: UInt32(controlKey | optionKey | cmdKey)),
    GlobalShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
  ]

  /// Captures a shortcut from a key event, requiring at least one of Control/Option/Command.
  init?(event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    var modifiers: UInt32 = 0
    if flags.contains(.control) {
      modifiers |= UInt32(controlKey)
    }
    if flags.contains(.option) {
      modifiers |= UInt32(optionKey)
    }
    if flags.contains(.shift) {
      modifiers |= UInt32(shiftKey)
    }
    if flags.contains(.command) {
      modifiers |= UInt32(cmdKey)
    }
    guard modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
      return nil
    }
    self.keyCode = UInt32(event.keyCode)
    self.carbonModifiers = modifiers
  }

  init(keyCode: UInt32, carbonModifiers: UInt32) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }

  /// Human-readable shortcut label such as "⌃⌥⌘N".
  var displayString: String {
    var result = ""
    if carbonModifiers & UInt32(controlKey) != 0 {
      result += "⌃"
    }
    if carbonModifiers & UInt32(optionKey) != 0 {
      result += "⌥"
    }
    if carbonModifiers & UInt32(shiftKey) != 0 {
      result += "⇧"
    }
    if carbonModifiers & UInt32(cmdKey) != 0 {
      result += "⌘"
    }
    return result + Self.keyString(for: keyCode)
  }

  /// Resolves the display character for a Carbon key code using the active keyboard layout.
  private static func keyString(for keyCode: UInt32) -> String {
    if let specialName = specialKeyNames[keyCode] {
      return specialName
    }

    guard let unmanagedSource = TISCopyCurrentKeyboardLayoutInputSource(),
          let property = TISGetInputSourceProperty(
            unmanagedSource.takeRetainedValue(),
            kTISPropertyUnicodeKeyLayoutData
          ) else {
      return "?"
    }
    let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    let layout = unsafeBitCast(
      CFDataGetBytePtr(layoutData),
      to: UnsafePointer<UCKeyboardLayout>.self
    )
    var deadKeyState: UInt32 = 0
    var characters = [UniChar](repeating: 0, count: 4)
    var length = 0
    let status = UCKeyTranslate(
      layout,
      UInt16(keyCode),
      UInt16(kUCKeyActionDisplay),
      0,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit),
      &deadKeyState,
      characters.count,
      &length,
      &characters
    )
    guard status == noErr, length > 0 else {
      return "?"
    }
    return String(utf16CodeUnits: characters, count: length).uppercased()
  }

  /// Display names for keys that do not translate to printable characters.
  private static let specialKeyNames: [UInt32: String] = [
    UInt32(kVK_Space): "Space",
    UInt32(kVK_Return): "↩",
    UInt32(kVK_Tab): "⇥",
    UInt32(kVK_Delete): "⌫",
    UInt32(kVK_ForwardDelete): "⌦",
    UInt32(kVK_LeftArrow): "←",
    UInt32(kVK_RightArrow): "→",
    UInt32(kVK_UpArrow): "↑",
    UInt32(kVK_DownArrow): "↓",
    UInt32(kVK_Home): "↖",
    UInt32(kVK_End): "↘",
    UInt32(kVK_PageUp): "⇞",
    UInt32(kVK_PageDown): "⇟",
    UInt32(kVK_F1): "F1",
    UInt32(kVK_F2): "F2",
    UInt32(kVK_F3): "F3",
    UInt32(kVK_F4): "F4",
    UInt32(kVK_F5): "F5",
    UInt32(kVK_F6): "F6",
    UInt32(kVK_F7): "F7",
    UInt32(kVK_F8): "F8",
    UInt32(kVK_F9): "F9",
    UInt32(kVK_F10): "F10",
    UInt32(kVK_F11): "F11",
    UInt32(kVK_F12): "F12"
  ]
}

import AppKit
import Carbon.HIToolbox

/// Registers app-wide Carbon hotkeys that fire even while Dayline is in the background.
@MainActor
final class GlobalHotkeyService {
  /// Actions that can be bound to a global shortcut.
  enum Hotkey: UInt32 {
    case newNote = 1
    case newLinearIssue = 2
  }

  /// Four-character hotkey signature: 'DYLN'.
  private static let signature = OSType(0x4459_4C4E)

  private struct Registration {
    let shortcut: GlobalShortcut
    let ref: EventHotKeyRef
  }

  private var registrations: [Hotkey: Registration] = [:]
  private var eventHandlerRef: EventHandlerRef?
  private var onTrigger: ((Hotkey) -> Void)?

  /// Installs the shared Carbon event handler and stores the trigger callback.
  func start(onTrigger: @escaping (Hotkey) -> Void) {
    self.onTrigger = onTrigger
    guard eventHandlerRef == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let userData = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, userData in
        guard let event, let userData else {
          return OSStatus(eventNotHandledErr)
        }
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard hotKeyID.signature == GlobalHotkeyService.signature,
              let hotkey = GlobalHotkeyService.Hotkey(rawValue: hotKeyID.id) else {
          return OSStatus(eventNotHandledErr)
        }
        let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
        let onTrigger = service.onTrigger
        Task { @MainActor in
          onTrigger?(hotkey)
        }
        return noErr
      },
      1,
      &eventType,
      userData,
      &eventHandlerRef
    )
  }

  /// Registers one hotkey and preserves the previous working registration on failure.
  @discardableResult
  func update(shortcut: GlobalShortcut, for hotkey: Hotkey) -> OSStatus {
    if registrations[hotkey]?.shortcut == shortcut {
      return noErr
    }

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: hotkey.rawValue)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.carbonModifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &ref
    )
    guard status == noErr, let ref else {
      return status == noErr ? OSStatus(eventInternalErr) : status
    }

    if let existing = registrations[hotkey] {
      UnregisterEventHotKey(existing.ref)
    }
    registrations[hotkey] = Registration(shortcut: shortcut, ref: ref)
    return noErr
  }
}

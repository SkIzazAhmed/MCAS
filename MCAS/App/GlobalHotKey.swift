// GlobalHotKey.swift
//
// What: a keyboard shortcut that works in every app (default ⌥⌘V opens the shelf).
// Why:  uses Apple's Carbon hotkey API, the standard way to do this. Unlike
//       watching all key presses, it needs NO extra permission.
//
// Note: in Finder, ⌥⌘V normally means "move here". While MCAS runs it opens the
//       shelf instead. The shortcut becomes changeable in Settings (v1.0).

import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: e.g. UInt32(kVK_ANSI_V)
    ///   - modifiers: Carbon flags, e.g. UInt32(cmdKey | optionKey)
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D43_4153), id: id) // "MCAS"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            Log.app.error("Could not register hotkey (status \(status)). Another app may be using it.")
            return nil
        }
        Self.actions[id] = action
        Log.app.info("Hotkey registered")
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.actions[id]?() }
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }
}

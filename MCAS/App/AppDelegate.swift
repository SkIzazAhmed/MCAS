// AppDelegate.swift
//
// What: runs once the app has launched: sets up the notch shelf and the ⌥⌘V hotkey.
// Why:  these are AppKit windows/APIs, which SwiftUI's App struct can't create itself.

import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tests run inside the app; they must not open windows or grab shortcuts.
        guard !AppEnvironment.isRunningTests else { return }

        let controller = NotchController(model: AppModel.shared)
        controller.start()
        notch = controller

        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) { [weak controller] in
            controller?.toggleFromHotKey()
        }
    }
}

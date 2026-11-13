// AppDelegate.swift
//
// What: runs once the app has launched: sets up the notch shelf and the global
//       shortcut, and re-registers the shortcut when you change it in Settings.
// Why:  these are AppKit windows/APIs, which SwiftUI's App struct can't create itself.

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?
    private var hotKey: GlobalHotKey?
    private var registeredPreset: HotKeyPreset?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tests run inside the app; they must not open windows or grab shortcuts.
        guard !AppEnvironment.isRunningTests else { return }

        let controller = NotchController(model: AppModel.shared)
        controller.start()
        notch = controller

        registerHotKey()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .mcasSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }
    }

    /// (Re)registers the shortcut chosen in Settings. Does nothing if unchanged.
    private func registerHotKey() {
        let preset = AppSettings.shared.hotKey
        guard preset != registeredPreset else { return }
        hotKey?.unregister()
        hotKey = GlobalHotKey(keyCode: preset.keyCode, modifiers: preset.carbonModifiers) { [weak notch] in
            notch?.toggleFromHotKey()
        }
        registeredPreset = hotKey == nil ? nil : preset
        Log.app.info("Shortcut set to \(preset.label, privacy: .public)")
    }
}

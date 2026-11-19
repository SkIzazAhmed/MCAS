// AppSettings.swift
//
// What: your preferences (F13), saved in UserDefaults so they survive restarts:
//   • which shortcut opens the shelf
//   • how many days to keep history (pinned items are always kept)
//   • secret guard on/off
//   • extra apps whose copies are never saved
// Why:  one place to read and change settings. When something changes, a
//       notification tells the rest of the app (watcher, hotkey) to update.

import Carbon.HIToolbox
import Foundation
import Observation

extension Notification.Name {
    static let mcasSettingsChanged = Notification.Name("com.izaz.mcas.settingsChanged")
}

/// The shortcuts you can pick for opening the shelf.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionCommandV
    case shiftCommandV
    case controlOptionV
    case controlCommandV

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionCommandV: return "⌥⌘V"
        case .shiftCommandV: return "⇧⌘V"
        case .controlOptionV: return "⌃⌥V"
        case .controlCommandV: return "⌃⌘V"
        }
    }

    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }

    /// Carbon modifier flags for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        switch self {
        case .optionCommandV: return UInt32(optionKey | cmdKey)
        case .shiftCommandV: return UInt32(shiftKey | cmdKey)
        case .controlOptionV: return UInt32(controlKey | optionKey)
        case .controlCommandV: return UInt32(controlKey | cmdKey)
        }
    }

    /// Shown next to the choice so you know what you're overriding.
    var note: String? {
        switch self {
        case .optionCommandV: return "Overrides Finder's \"Move item here\""
        case .shiftCommandV: return "Overrides \"Paste and match style\" in some apps"
        default: return nil
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let retentionChoices = [1, 7, 30, 90, 365, 0] // 0 = forever

    private(set) var hotKey: HotKeyPreset
    private(set) var retentionDays: Int
    private(set) var secretGuardEnabled: Bool
    /// Your own additions to the ignore list (bundle IDs, e.g. "com.example.app").
    private(set) var customIgnoredApps: [String]
    /// Show a small "Saved" flash beside the notch after each copy.
    private(set) var showsSaveFlash: Bool

    @ObservationIgnored private let defaults: UserDefaults

    private enum Key {
        static let hotKey = "hotKey"
        static let retentionDays = "retentionDays"
        static let secretGuard = "secretGuardEnabled"
        static let ignoredApps = "customIgnoredApps"
        static let saveFlash = "showsSaveFlash"
    }

    /// Tests pass their own UserDefaults so they never touch your real settings.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: Key.hotKey) ?? "") ?? .optionCommandV
        retentionDays = defaults.object(forKey: Key.retentionDays) as? Int ?? 30
        secretGuardEnabled = defaults.object(forKey: Key.secretGuard) as? Bool ?? true
        customIgnoredApps = defaults.stringArray(forKey: Key.ignoredApps) ?? []
        showsSaveFlash = defaults.object(forKey: Key.saveFlash) as? Bool ?? true
    }

    /// Built-in password managers plus your additions.
    var allIgnoredBundleIDs: Set<String> {
        SecretFilter.defaultIgnoredBundleIDs.union(customIgnoredApps)
    }

    func setHotKey(_ preset: HotKeyPreset) {
        hotKey = preset
        defaults.set(preset.rawValue, forKey: Key.hotKey)
        changed()
    }

    func setRetentionDays(_ days: Int) {
        retentionDays = max(0, days)
        defaults.set(retentionDays, forKey: Key.retentionDays)
        changed()
    }

    func setSecretGuardEnabled(_ enabled: Bool) {
        secretGuardEnabled = enabled
        defaults.set(enabled, forKey: Key.secretGuard)
        changed()
    }

    func setShowsSaveFlash(_ enabled: Bool) {
        showsSaveFlash = enabled
        defaults.set(enabled, forKey: Key.saveFlash)
        changed()
    }

    func addIgnoredApp(_ bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !customIgnoredApps.contains(id) else { return }
        customIgnoredApps.append(id)
        defaults.set(customIgnoredApps, forKey: Key.ignoredApps)
        changed()
    }

    func removeIgnoredApp(_ bundleID: String) {
        customIgnoredApps.removeAll { $0 == bundleID }
        defaults.set(customIgnoredApps, forKey: Key.ignoredApps)
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .mcasSettingsChanged, object: self)
    }
}

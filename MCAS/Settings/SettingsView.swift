// SettingsView.swift
//
// What: the Settings window (F13). Open it from the shelf's ⋯ menu → Settings….
//   General:  shortcut, launch at login, screenshots
//   History:  how long to keep items, clear history
//   Privacy:  secret guard, apps whose copies are never saved
//   Permissions and About
// Why:  everything here used to need a code change.

import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

/// Shows the Settings window. A plain AppKit window is used (instead of
/// SwiftUI's Settings scene) because MCAS has no Dock icon or app menu.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(settings: AppSettings, model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MCAS Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let settings: AppSettings
    let model: AppModel

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmClear = false
    @State private var isTrusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            general
            history
            privacy
            permissions
            about
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
        .onAppear { isTrusted = AXIsProcessTrusted() }
    }

    // MARK: - Sections

    private var general: some View {
        Section("General") {
            Picker("Open the shelf with", selection: Binding(get: { settings.hotKey }, set: { settings.setHotKey($0) })) {
                ForEach(HotKeyPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            if let note = settings.hotKey.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Launch MCAS when you log in", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Save screenshots (⇧⌘3 / ⇧⌘4 / ⇧⌘5)", isOn: Binding(
                get: { model.savesScreenshots },
                set: { model.setSavesScreenshots($0) }
            ))
        }
    }

    private var history: some View {
        Section {
            Picker("Keep history for", selection: Binding(get: { settings.retentionDays }, set: { settings.setRetentionDays($0) })) {
                ForEach(AppSettings.retentionChoices, id: \.self) { days in
                    Text(Self.retentionLabel(days)).tag(days)
                }
            }
            Button("Clear History…") { confirmClear = true }
                .confirmationDialog("Clear all history?", isPresented: $confirmClear) {
                    Button("Clear History", role: .destructive) { model.clearHistory() }
                } message: {
                    Text("Pinned items are kept. This can't be undone.")
                }
        } header: {
            Text("History")
        } footer: {
            Text("\(model.totalCount) items saved. Pinned items are always kept.")
        }
    }

    private var privacy: some View {
        Section {
            Toggle("Secret guard", isOn: Binding(get: { settings.secretGuardEnabled }, set: { settings.setSecretGuardEnabled($0) }))
            Text("Never saves API keys or card numbers. One-time codes (like 482913) are deleted after 60 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(settings.customIgnoredApps, id: \.self) { bundleID in
                HStack {
                    Text(Self.appName(for: bundleID))
                    Spacer()
                    Button("Remove") { settings.removeIgnoredApp(bundleID) }
                }
            }
            Menu("Ignore an App…") {
                ForEach(Self.runningApps(excluding: settings.allIgnoredBundleIDs)) { app in
                    Button(app.name) { settings.addIgnoredApp(app.bundleID) }
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Copies from these apps are never saved. Password managers (\(SecretFilter.defaultIgnoredBundleIDs.count) apps) are always ignored.")
        }
    }

    private var permissions: some View {
        Section("Permissions") {
            HStack {
                Label(isTrusted ? "Accessibility: allowed" : "Accessibility: not allowed",
                      systemImage: isTrusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(isTrusted ? .green : .orange)
                Spacer()
                Button("Open Settings") { model.openAccessibilitySettings() }
            }
            Text("Needed only to paste for you (it presses ⌘V). Without it, MCAS copies the item and you press ⌘V.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            Link("Source code on GitHub", destination: URL(string: "https://github.com/SkIzazAhmed/MCAS")!)
            Text("Free software under the GPL-3.0 license.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Couldn't change this: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func retentionLabel(_ days: Int) -> String {
        switch days {
        case 0: return "Forever"
        case 1: return "1 day"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    struct AppChoice: Identifiable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    /// Apps you have open right now, to pick from.
    static func runningApps(excluding: Set<String>) -> [AppChoice] {
        let ownID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppChoice? in
                guard let id = app.bundleIdentifier, id != ownID, !excluding.contains(id), seen.insert(id).inserted else { return nil }
                return AppChoice(name: app.localizedName ?? id, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

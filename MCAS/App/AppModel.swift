// AppModel.swift
//
// What: the app's "brain" — owns the watcher, the store and the paste service,
//       and holds the state the UI shows (recent items, count, paused).
// Why:  SwiftUI views read from one place. @Observable makes any view that
//       reads `recentItems` refresh automatically when it changes.
//
// Flow of a copy:  watcher.onCapture → save(_:) → store.save → reload() → UI updates

import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class AppModel {
    /// The one model used by the running app.
    static let shared = AppModel.makeForLaunch()

    private(set) var recentItems: [ClipItem] = []
    private(set) var totalCount = 0
    private(set) var isPaused = false
    /// Save new screenshot files (⇧⌘3/4/5) into history. Remembered between launches.
    private(set) var savesScreenshots = UserDefaults.standard.object(forKey: "savesScreenshots") as? Bool ?? true
    /// True after a paste couldn't press ⌘V because Accessibility is off.
    private(set) var needsAccessibility = false
    /// Shown in the menu if the database could not be opened.
    private(set) var startupProblem: String?

    @ObservationIgnored let store: HistoryStore
    @ObservationIgnored private let watcher: PasteboardWatcher
    @ObservationIgnored private let pasteService: PasteService
    @ObservationIgnored private let screenshotWatcher = ScreenshotWatcher()

    init(store: HistoryStore, watcher: PasteboardWatcher, pasteService: PasteService) {
        self.store = store
        self.watcher = watcher
        self.pasteService = pasteService
        watcher.onCapture = { [weak self] clip in
            self?.save(clip)
        }
        screenshotWatcher.onCapture = { [weak self] clip in
            self?.save(clip)
        }
        reload()
    }

    private static func makeForLaunch() -> AppModel {
        if AppEnvironment.isRunningTests {
            // Tests build their own objects. Give the host app a harmless setup
            // that never touches your real clipboard or history.
            let store = try! HistoryStore.inMemory()
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.izaz.mcas.test-host"))
            return AppModel(
                store: store,
                watcher: PasteboardWatcher(pasteboard: pasteboard),
                pasteService: PasteService(store: store, pasteboard: pasteboard)
            )
        }

        var problem: String?
        let store: HistoryStore
        do {
            store = try HistoryStore.onDisk()
        } catch {
            Log.storage.fault("Could not open history: \(error.localizedDescription, privacy: .public)")
            problem = "History could not be opened, so nothing will be kept after quitting."
            store = try! HistoryStore.inMemory()
        }
        let model = AppModel(store: store, watcher: PasteboardWatcher(), pasteService: PasteService(store: store))
        model.startupProblem = problem
        model.watcher.start()
        if model.savesScreenshots { model.screenshotWatcher.start() }
        Log.app.info("MCAS started with \(model.totalCount) saved items")
        return model
    }

    // MARK: - Actions

    func save(_ clip: CapturedClip) {
        do {
            try store.save(clip)
            reload()
        } catch {
            Log.storage.error("Saving failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reload() {
        do {
            recentItems = try store.recent(limit: 500)
            totalCount = try store.count()
        } catch {
            Log.storage.error("Loading failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        watcher.isPaused = paused
        screenshotWatcher.isPaused = paused
        Log.capture.info("Capture \(paused ? "paused" : "resumed", privacy: .public)")
    }

    func setSavesScreenshots(_ enabled: Bool) {
        savesScreenshots = enabled
        UserDefaults.standard.set(enabled, forKey: "savesScreenshots")
        if enabled { screenshotWatcher.start() } else { screenshotWatcher.stop() }
    }

    func copyToClipboard(_ item: ClipItem) {
        do {
            try pasteService.copyToClipboard(item)
            reload()
        } catch {
            Log.paste.error("Copy back failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Puts the item on the clipboard and pastes it into the app you were using.
    func paste(_ item: ClipItem) {
        do {
            handle(try pasteService.paste(item))
            reload()
        } catch {
            Log.paste.error("Paste failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Joins several items (in the order given) and pastes them at once.
    func pasteTogether(_ items: [ClipItem], separator: PasteSeparator) {
        do {
            handle(try pasteService.pasteTogether(items, separator: separator.string))
        } catch {
            Log.paste.error("Paste together failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ result: PasteService.Result) {
        if result == .copiedNeedsAccessibility {
            needsAccessibility = true
            requestAccessibility()
        }
    }

    // MARK: - Accessibility (needed only to press ⌘V for you)

    /// Shows macOS's own "allow Accessibility" prompt (macOS shows it only once).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        needsAccessibility = !AXIsProcessTrustedWithOptions(options)
    }

    /// Called when the shelf opens, so the hint disappears once permission is granted.
    func refreshAccessibilityStatus() {
        if needsAccessibility { needsAccessibility = !AXIsProcessTrusted() }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func clearHistory() {
        do {
            try store.deleteAll()
            reload()
        } catch {
            Log.storage.error("Clearing failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Debug helpers (used by the Debug menu)

    func debugSimulateCopy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("MCAS test copy at \(Date.now.formatted(date: .omitted, time: .standard))", forType: .string)
    }

    func debugOpenDataFolder() {
        NSWorkspace.shared.open(HistoryStore.defaultDirectory)
    }
}

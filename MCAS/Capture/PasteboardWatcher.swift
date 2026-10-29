// PasteboardWatcher.swift
//
// What: notices every new copy (⌘C) and hands it to whoever is listening.
// Why:  macOS has no "clipboard changed" notification. The only reliable way is
//       to check NSPasteboard.changeCount every half second. Reading a number is
//       nearly free, and we only read the actual data when the number changes.
//
// Flow:  timer tick → changeCount changed? → paused? → SecretFilter → ClipReader → onCapture

import AppKit

@MainActor
final class PasteboardWatcher {
    /// Called with every copy that should be saved.
    var onCapture: ((CapturedClip) -> Void)?
    /// While paused, copies are ignored (and NOT saved later).
    var isPaused = false
    var ignoredBundleIDs: Set<String> = SecretFilter.defaultIgnoredBundleIDs

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private let sourceAppProvider: @MainActor () -> SourceApp?
    private var lastChangeCount: Int
    private var timer: Timer?

    /// - Parameters:
    ///   - pasteboard: `.general` is the real clipboard; tests pass a private one.
    ///   - sourceAppProvider: who copied it; tests pass a fake.
    init(
        pasteboard: NSPasteboard = .general,
        interval: TimeInterval = 0.5,
        sourceAppProvider: @escaping @MainActor () -> SourceApp? = SourceApp.frontmost
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.sourceAppProvider = sourceAppProvider
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.checkForChanges()
            }
        }
        // Tolerance lets macOS group our wake-ups with others: saves battery.
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.capture.info("Watching the clipboard every \(self.interval)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks once. Returns the captured clip (also sent to `onCapture`), or nil.
    /// The timer calls this; tests call it directly.
    @discardableResult
    func checkForChanges(now: Date = .now) -> CapturedClip? {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return nil }
        lastChangeCount = count

        guard !isPaused else {
            Log.capture.debug("Copy ignored: capture is paused")
            return nil
        }

        let types = pasteboard.types ?? []
        if types.contains(.mcasInternal) {
            Log.capture.debug("Copy ignored: written by MCAS itself")
            return nil
        }

        let source = sourceAppProvider()
        if let reason = SecretFilter.reasonToSkip(types: types, sourceBundleID: source?.bundleID, ignoredBundleIDs: ignoredBundleIDs) {
            Log.capture.info("Copy not saved (\(reason.description, privacy: .public))")
            return nil
        }

        guard let clip = ClipReader.read(from: pasteboard, source: source, now: now) else { return nil }
        Log.capture.info("Captured \(clip.kind.rawValue, privacy: .public), \(clip.byteSize) bytes, from \(clip.sourceAppName ?? "unknown", privacy: .public)")
        onCapture?(clip)
        return clip
    }
}

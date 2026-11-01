// ScreenshotWatcher.swift
//
// What: saves every new screenshot (⇧⌘3, ⇧⌘4, ⇧⌘5) into history, even though
//       those shortcuts save a file and never touch the clipboard.
// Why:  a screenshot is something you "copied from the screen"; it should be
//       one click away in the shelf like everything else.
//
// How:  macOS marks every screenshot file with the Spotlight attribute
//       kMDItemIsScreenCapture = 1. NSMetadataQuery tells us live when a new file
//       with that mark appears, wherever your screenshots are saved. No polling.
//
// Notes:
//   • Screenshots taken with ⌃ (Control) go to the clipboard and are already
//     caught by PasteboardWatcher.
//   • While the little preview thumbnail floats in the corner, macOS hasn't
//     written the file yet, so the screenshot shows up in MCAS a few seconds later.
//   • Reading files on the Desktop makes macOS ask once:
//     "MCAS would like to access files in your Desktop folder" → Allow.

import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotWatcher {
    var onCapture: ((CapturedClip) -> Void)?
    var isPaused = false

    private let query = NSMetadataQuery()
    private var observer: NSObjectProtocol?
    private var startedAt = Date.now
    private var handledPaths = Set<String>()

    nonisolated static let source = SourceApp(bundleID: "com.apple.screencaptureui", name: "Screenshot")

    func start() {
        guard !query.isStarted else { return }
        startedAt = .now
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]

        // Only *updates* matter: results found at start are old screenshots.
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated {
                self?.handle(paths: paths)
            }
        }
        query.start()
        Log.capture.info("Watching for new screenshots")
    }

    func stop() {
        query.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func handle(paths: [String]) {
        for path in paths where !handledPaths.contains(path) {
            handledPaths.insert(path)
            let url = URL(fileURLWithPath: path)

            // Ignore screenshots older than this app launch (e.g. moved or renamed files).
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard created >= startedAt.addingTimeInterval(-5) else { continue }

            guard !isPaused else {
                Log.capture.debug("Screenshot ignored: capture is paused")
                continue
            }
            guard let clip = Self.makeClip(fileURL: url) else { continue }
            Log.capture.info("Captured screenshot, \(clip.byteSize) bytes")
            onCapture?(clip)
        }
    }

    /// Turns a screenshot file into a clip: image data stored as PNG (pastes
    /// everywhere), plus a thumbnail. Returns nil for videos or unreadable files.
    nonisolated static func makeClip(fileURL: URL, now: Date = .now) -> CapturedClip? {
        guard let type = UTType(filenameExtension: fileURL.pathExtension), type.conforms(to: .image) else {
            return nil // screen recordings (.mov) are skipped
        }
        guard var data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            Log.capture.error("Could not read screenshot file")
            return nil
        }
        if type != .png {
            // JPEG/HEIC/TIFF screenshots → PNG, which every app accepts on paste.
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return nil }
            data = png
        }
        guard data.count <= ClipReader.maxClipBytes else {
            Log.capture.notice("Screenshot skipped: \(data.count) bytes is over the limit")
            return nil
        }

        let reps = [CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.png.rawValue, data: data)]
        let preview: String
        if let size = ClipReader.pixelSize(of: data) {
            preview = "Screenshot \(size.width)×\(size.height)"
        } else {
            preview = "Screenshot"
        }
        return CapturedClip(
            kind: .image,
            previewText: preview,
            representations: reps,
            sourceAppBundleID: source.bundleID,
            sourceAppName: source.name,
            thumbnail: ClipReader.makeThumbnail(from: data),
            createdAt: now,
            contentHash: ClipReader.contentHash(kind: .image, string: nil, representations: reps)
        )
    }
}

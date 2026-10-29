// ClipReader.swift
//
// What: reads everything currently on a pasteboard and turns it into a CapturedClip.
// Why:  separated from the watcher so it can be tested on its own, and so the
//       "what kind of thing is this?" rules live in one place.
//
// Steps:
//   1. Collect every (type, data) pair from every pasteboard item.
//   2. Decide the kind (file, url, rich text, text, image, color, other).
//   3. Build a short preview and, for images, a thumbnail.
//   4. Shrink huge images (TIFF → PNG) and drop the copy if still too big.
//   5. Compute a fingerprint for duplicate detection.

import AppKit
import CryptoKit
import ImageIO

enum ClipReader {
    /// Copies bigger than this are not saved (POC limit; v1.0 moves big data to files on disk).
    static let maxClipBytes = 25 * 1024 * 1024

    static func read(from pasteboard: NSPasteboard, source: SourceApp?, now: Date = .now) -> CapturedClip? {
        guard let items = pasteboard.pasteboardItems, let first = items.first else { return nil }

        // 1. Collect raw data.
        var reps: [CapturedClip.Representation] = []
        for (index, item) in items.enumerated() {
            for type in item.types where type != .mcasInternal {
                if let data = item.data(forType: type) {
                    reps.append(.init(itemIndex: index, type: type.rawValue, data: data))
                }
            }
        }
        guard !reps.isEmpty else { return nil }

        // 2 + 3. Kind, preview, thumbnail.
        let types = Set(first.types)
        let string = first.string(forType: .string)
        var kind: ClipKind
        var preview: String
        var thumbnail: Data?

        if types.contains(.fileURL) {
            let names = items.compactMap { item -> String? in
                guard let raw = item.string(forType: .fileURL), let url = URL(string: raw) else { return nil }
                return url.lastPathComponent
            }
            kind = .file
            preview = names.count > 1 ? "\(names.count) files: " + names.joined(separator: ", ") : (names.first ?? "File")
        } else if let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if isWebURL(string) {
                kind = .url
            } else if types.contains(.rtf) || types.contains(.rtfd) || types.contains(.html) {
                kind = .richText
            } else {
                kind = .text
            }
            preview = String(string.prefix(1000))
        } else if let imageData = first.data(forType: .png) ?? first.data(forType: .tiff) {
            kind = .image
            thumbnail = makeThumbnail(from: imageData)
            if let size = pixelSize(of: imageData) {
                preview = "Image \(size.width)×\(size.height)"
            } else {
                preview = "Image"
            }
        } else if types.contains(.color) {
            kind = .color
            preview = "Color"
        } else if let link = first.string(forType: .URL) {
            kind = .url
            preview = link
        } else {
            kind = .other
            preview = "Copied \(first.types.first?.rawValue ?? "data")"
        }

        // 4. Size limit.
        reps = shrinkIfNeeded(reps)
        let total = reps.reduce(0) { $0 + $1.data.count }
        guard total <= maxClipBytes else {
            Log.capture.notice("Skipped a \(kind.rawValue, privacy: .public) copy: \(total) bytes is over the limit")
            return nil
        }

        // 5. Fingerprint.
        let hash = contentHash(kind: kind, string: string, representations: reps)

        return CapturedClip(
            kind: kind,
            previewText: preview,
            representations: reps,
            sourceAppBundleID: source?.bundleID,
            sourceAppName: source?.name,
            thumbnail: thumbnail,
            createdAt: now,
            contentHash: hash
        )
    }

    // MARK: - Helpers

    /// "https://example.com/page" → true. Multi-line text or plain words → false.
    static func isWebURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return false }
        return true
    }

    /// Text-like copies are fingerprinted by their text, so copying the same words
    /// again (even from another app) counts as a duplicate. Everything else by its bytes.
    static func contentHash(kind: ClipKind, string: String?, representations: [CapturedClip.Representation]) -> String {
        var hasher = SHA256()
        switch kind {
        case .text, .richText, .url:
            hasher.update(data: Data("text:".utf8))
            hasher.update(data: Data((string ?? "").utf8))
        default:
            let sorted = representations.sorted { ($0.itemIndex, $0.type) < ($1.itemIndex, $1.type) }
            for rep in sorted {
                hasher.update(data: Data("\(rep.itemIndex)|\(rep.type)|".utf8))
                hasher.update(data: rep.data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Screenshots copied as TIFF can be 30+ MB. If the copy is over the limit,
    /// replace TIFF with PNG (much smaller, same pixels).
    static func shrinkIfNeeded(_ reps: [CapturedClip.Representation]) -> [CapturedClip.Representation] {
        let total = reps.reduce(0) { $0 + $1.data.count }
        guard total > maxClipBytes else { return reps }

        let tiff = NSPasteboard.PasteboardType.tiff.rawValue
        let png = NSPasteboard.PasteboardType.png.rawValue
        let itemsWithPNG = Set(reps.filter { $0.type == png }.map(\.itemIndex))

        return reps.compactMap { rep in
            guard rep.type == tiff else { return rep }
            if itemsWithPNG.contains(rep.itemIndex) { return nil } // PNG already there, drop the TIFF
            guard let pngData = NSBitmapImageRep(data: rep.data)?.representation(using: .png, properties: [:]) else {
                return rep
            }
            return .init(itemIndex: rep.itemIndex, type: png, data: pngData)
        }
    }

    static func makeThumbnail(from data: Data, maxPixelSize: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}

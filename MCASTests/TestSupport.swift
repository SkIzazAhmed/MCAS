// TestSupport.swift
//
// Small helpers shared by the tests: a private clipboard, sample images, sample clips.
// Tests never touch your real clipboard — each one gets its own named pasteboard.

import AppKit
import XCTest
@testable import MCAS

enum TestSupport {
    /// A brand-new private pasteboard. Call `releaseGlobally()` on it when done.
    static func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("MCASTests.\(UUID().uuidString)"))
    }

    /// A tiny solid-color PNG.
    static func pngData(width: Int = 40, height: Int = 20) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    /// A text clip as the watcher would produce it.
    static func textClip(_ text: String, at date: Date) -> CapturedClip {
        let rep = CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))
        return CapturedClip(
            kind: .text,
            previewText: text,
            representations: [rep],
            sourceAppBundleID: "com.apple.TextEdit",
            sourceAppName: "TextEdit",
            thumbnail: nil,
            createdAt: date,
            contentHash: ClipReader.contentHash(kind: .text, string: text, representations: [rep])
        )
    }

    static let textEdit = SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")
}

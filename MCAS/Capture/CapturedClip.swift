// CapturedClip.swift
//
// What: a copy that was just read from the clipboard but is not saved yet.
// Why:  the watcher produces these, the store saves them. Keeping it a plain
//       struct (no database, no AppKit) makes it easy to create in tests.

import AppKit

/// The kind of thing that was copied. Decides the icon and preview in the shelf.
enum ClipKind: String, Codable, Sendable, CaseIterable {
    case text
    case richText
    case url
    case image
    case file
    case color
    case other
}

/// Which app the copy came from (best guess: the app in front when we noticed it).
struct SourceApp: Equatable, Sendable {
    var bundleID: String?
    var name: String?

    @MainActor
    static func frontmost() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}

struct CapturedClip: Equatable, Sendable {
    /// One piece of raw clipboard data, e.g. ("public.utf8-plain-text", bytes).
    /// A single copy usually has several: the same text as plain, RTF and HTML.
    /// We keep them all so pasting later is identical to the original.
    struct Representation: Equatable, Sendable {
        /// Which pasteboard item this belongs to (copying 3 files in Finder = 3 items).
        var itemIndex: Int
        /// The type identifier, e.g. "public.png".
        var type: String
        var data: Data
    }

    var kind: ClipKind
    /// Short human-readable text for the shelf card. Never used for pasting.
    var previewText: String
    var representations: [Representation]
    var sourceAppBundleID: String?
    var sourceAppName: String?
    /// A small PNG for image copies, so the shelf never loads the full image.
    var thumbnail: Data?
    var createdAt: Date
    /// Fingerprint used to spot duplicates (F7).
    var contentHash: String

    var byteSize: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }
}

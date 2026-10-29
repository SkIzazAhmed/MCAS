// ClipItem.swift
//
// What: the two database tables, as Swift structs.
//   • ClipItem           — one row per copy: kind, preview, time, source app.
//   • ClipRepresentation — the raw data of that copy (several rows per copy).
// Why:  the shelf only needs ClipItem (small and fast). The heavy data is loaded
//       only when you actually paste.
//
// GRDB protocols:
//   FetchableRecord          → can be read from the database
//   MutablePersistableRecord → can be inserted/updated (and gets its id back)

import Foundation
import GRDB

struct ClipItem: Identifiable, Equatable, Sendable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clip"

    var id: Int64?
    var createdAt: Date
    var kind: ClipKind
    var previewText: String
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var contentHash: String
    var byteSize: Int
    var thumbnail: Data?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let createdAt = Column(CodingKeys.createdAt)
        static let contentHash = Column(CodingKeys.contentHash)
    }
}

struct ClipRepresentation: Equatable, Sendable, Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "clipRepresentation"

    var id: Int64?
    var clipId: Int64
    var itemIndex: Int
    var type: String
    var data: Data

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let clipId = Column(CodingKeys.clipId)
        static let itemIndex = Column(CodingKeys.itemIndex)
    }
}

// MARK: - Display helpers

extension ClipItem {
    /// One tidy line for menus and cards: whitespace collapsed, max 60 characters.
    var displayTitle: String {
        let oneLine = previewText
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        if oneLine.isEmpty { return "(empty)" }
        return oneLine.count > 60 ? String(oneLine.prefix(59)) + "…" : oneLine
    }

    /// SF Symbol name for this kind of copy.
    var symbolName: String {
        switch kind {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .other: return "questionmark.square.dashed"
        }
    }
}

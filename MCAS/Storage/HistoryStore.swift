// HistoryStore.swift
//
// What: saves, loads, searches and deletes clipboard history in a SQLite database.
// Where: ~/Library/Application Support/MCAS/history.sqlite
// Why:  history must survive quitting and restarting.
//
// Rules kept here:
//   • Duplicates (F7): saving something whose fingerprint already exists replaces
//     the old row, so the copy "moves to the top". A pinned item stays pinned.
//   • Pin (F8): pinned items are listed separately and never expire.
//   • Retention (F10): items older than N days are removed, except pinned ones.
//   • One-time codes: rows with `expiresAt` are deleted when that time passes.
//
// Encryption (SQLCipher) comes in a later v1.0 step; until then the file is
// plain SQLite, which you can open with any SQLite viewer while debugging.

import Foundation
import GRDB

final class HistoryStore: Sendable {
    private let writer: any DatabaseWriter

    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// A throwaway database in memory. Used by tests.
    static func inMemory() throws -> HistoryStore {
        try HistoryStore(DatabaseQueue())
    }

    static func atPath(_ path: String) throws -> HistoryStore {
        try HistoryStore(DatabaseQueue(path: path))
    }

    /// ~/Library/Application Support/MCAS/
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MCAS", isDirectory: true)
    }

    /// The real history used by the app.
    static func onDisk() throws -> HistoryStore {
        let folder = defaultDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("history.sqlite").path
        Log.storage.info("Opening history at \(path, privacy: .public)")
        return try atPath(path)
    }

    // MARK: - Schema

    /// Each migration runs exactly once per database, in order. To change the
    /// schema later, ADD a new migration; never edit an old one (your existing
    /// history was created by "v1" and is upgraded by "v2").
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "clip") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("previewText", .text).notNull()
                t.column("sourceAppBundleID", .text)
                t.column("sourceAppName", .text)
                t.column("contentHash", .text).notNull().indexed()
                t.column("byteSize", .integer).notNull()
                t.column("thumbnail", .blob)
            }
            try db.create(table: "clipRepresentation") { t in
                t.autoIncrementedPrimaryKey("id")
                // Creates a "clipId" column. Deleting a clip deletes its data too.
                t.belongsTo("clip", onDelete: .cascade).notNull()
                t.column("itemIndex", .integer).notNull()
                t.column("type", .text).notNull()
                t.column("data", .blob).notNull()
            }
        }
        migrator.registerMigration("v2: pin and expiry") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "isPinned", .boolean).notNull().defaults(to: false)
                t.add(column: "expiresAt", .datetime)
            }
        }
        return migrator
    }

    // MARK: - Writing

    /// Saves a new copy. If the same content already exists, it is replaced,
    /// which moves it to the top (and keeps it pinned if it was).
    @discardableResult
    func save(_ clip: CapturedClip) throws -> ClipItem {
        try writer.write { db in
            let sameContent = ClipItem.filter(ClipItem.Columns.contentHash == clip.contentHash)
            let wasPinned = try sameContent.filter(ClipItem.Columns.isPinned == true).fetchCount(db) > 0
            let removed = try sameContent.deleteAll(db)
            if removed > 0 {
                Log.storage.debug("Duplicate copy: moved to top")
            }

            var item = ClipItem(
                id: nil,
                createdAt: clip.createdAt,
                kind: clip.kind,
                previewText: clip.previewText,
                sourceAppBundleID: clip.sourceAppBundleID,
                sourceAppName: clip.sourceAppName,
                contentHash: clip.contentHash,
                byteSize: clip.byteSize,
                thumbnail: clip.thumbnail,
                isPinned: wasPinned,
                expiresAt: wasPinned ? nil : clip.expiresAt
            )
            try item.insert(db)
            guard let clipId = item.id else { throw StoreError.missingID }

            for rep in clip.representations {
                var row = ClipRepresentation(id: nil, clipId: clipId, itemIndex: rep.itemIndex, type: rep.type, data: rep.data)
                try row.insert(db)
            }
            return item
        }
    }

    /// Moves an item to the top (used when you paste an older item).
    func bump(id: Int64, to date: Date = .now) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE clip SET createdAt = ? WHERE id = ?", arguments: [date, id])
        }
    }

    /// Pinning also cancels any auto-delete time: you asked to keep it.
    func setPinned(id: Int64, _ pinned: Bool) throws {
        try writer.write { db in
            if pinned {
                try db.execute(sql: "UPDATE clip SET isPinned = 1, expiresAt = NULL WHERE id = ?", arguments: [id])
            } else {
                try db.execute(sql: "UPDATE clip SET isPinned = 0 WHERE id = ?", arguments: [id])
            }
        }
    }

    func delete(id: Int64) throws {
        _ = try writer.write { db in
            try ClipItem.deleteOne(db, key: id)
        }
    }

    /// Clears history. Pinned items are kept unless `includingPinned` is true.
    func deleteAll(includingPinned: Bool = true) throws {
        _ = try writer.write { db in
            if includingPinned {
                try ClipItem.deleteAll(db)
            } else {
                try ClipItem.filter(ClipItem.Columns.isPinned == false).deleteAll(db)
            }
        }
        Log.storage.notice("History cleared")
    }

    /// Removes unpinned items older than `days` days. Returns how many were removed.
    @discardableResult
    func applyRetention(days: Int, now: Date = .now) throws -> Int {
        guard days > 0 else { return 0 } // 0 = keep forever
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let removed = try writer.write { db in
            try ClipItem
                .filter(ClipItem.Columns.isPinned == false && ClipItem.Columns.createdAt < cutoff)
                .deleteAll(db)
        }
        if removed > 0 { Log.storage.info("Retention removed \(removed) items older than \(days) days") }
        return removed
    }

    /// Deletes one-time codes whose time is up. Returns how many were removed.
    @discardableResult
    func deleteExpired(now: Date = .now) throws -> Int {
        let removed = try writer.write { db in
            try ClipItem
                .filter(ClipItem.Columns.expiresAt != nil && ClipItem.Columns.expiresAt <= now)
                .deleteAll(db)
        }
        if removed > 0 { Log.storage.info("Auto-deleted \(removed) one-time code(s)") }
        return removed
    }

    // MARK: - Reading

    /// Unpinned items, newest first.
    func recent(limit: Int = 200) throws -> [ClipItem] {
        try writer.read { db in
            try ClipItem
                .filter(ClipItem.Columns.isPinned == false)
                .order(ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Pinned items, most recently used first.
    func pinned() throws -> [ClipItem] {
        try writer.read { db in
            try ClipItem
                .filter(ClipItem.Columns.isPinned == true)
                .order(ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
                .fetchAll(db)
        }
    }

    /// Case-insensitive search in the preview text and source app name (F9).
    /// Pinned matches come first, then newest first.
    func search(_ query: String, limit: Int = 200) throws -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Escape LIKE's wildcards so searching for "50%" finds "50%", not everything.
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return try writer.read { db in
            try ClipItem
                .filter(sql: "previewText LIKE ? ESCAPE '\\' OR sourceAppName LIKE ? ESCAPE '\\'", arguments: [pattern, pattern])
                .order(ClipItem.Columns.isPinned.desc, ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try writer.read { db in try ClipItem.fetchCount(db) }
    }

    /// The raw data needed to paste an item, in original order.
    func representations(for clipId: Int64) throws -> [ClipRepresentation] {
        try writer.read { db in
            try ClipRepresentation
                .filter(ClipRepresentation.Columns.clipId == clipId)
                .order(ClipRepresentation.Columns.itemIndex, ClipRepresentation.Columns.id)
                .fetchAll(db)
        }
    }

    enum StoreError: Error {
        case missingID
    }
}

// HistoryStore.swift
//
// What: saves, loads and deletes clipboard history in a SQLite database.
// Where: ~/Library/Application Support/MCAS/history.sqlite
// Why:  history must survive quitting and restarting (POC checklist).
//
// Duplicates (F7): saving something whose fingerprint already exists deletes the
// old row first, so the copy "moves to the top" instead of appearing twice.
//
// Encryption (SQLCipher) comes in v1.0; for the POC the file is plain SQLite,
// which also means you can open it with any SQLite viewer while debugging.

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
    /// schema later, ADD a new migration ("v2", …); never edit an old one.
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
        return migrator
    }

    // MARK: - Writing

    /// Saves a new copy. If the same content already exists, it is replaced,
    /// which moves it to the top.
    @discardableResult
    func save(_ clip: CapturedClip) throws -> ClipItem {
        try writer.write { db in
            let removed = try ClipItem
                .filter(ClipItem.Columns.contentHash == clip.contentHash)
                .deleteAll(db)
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
                thumbnail: clip.thumbnail
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

    func delete(id: Int64) throws {
        _ = try writer.write { db in
            try ClipItem.deleteOne(db, key: id)
        }
    }

    func deleteAll() throws {
        _ = try writer.write { db in
            try ClipItem.deleteAll(db)
        }
        Log.storage.notice("History cleared")
    }

    // MARK: - Reading

    /// Newest first.
    func recent(limit: Int = 200) throws -> [ClipItem] {
        try writer.read { db in
            try ClipItem
                .order(ClipItem.Columns.createdAt.desc, ClipItem.Columns.id.desc)
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

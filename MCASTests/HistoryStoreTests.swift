// HistoryStoreTests.swift — saving, ordering, duplicates, persistence, deleting.

import AppKit
import XCTest
@testable import MCAS

final class HistoryStoreTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewestFirst() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("older", at: start))
        try store.save(TestSupport.textClip("newer", at: start.addingTimeInterval(60)))

        XCTAssertEqual(try store.recent().map(\.previewText), ["newer", "older"])
        XCTAssertEqual(try store.count(), 2)
    }

    func testDuplicateMovesToTopInsteadOfAddingCopy() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("A", at: start))
        try store.save(TestSupport.textClip("B", at: start.addingTimeInterval(1)))
        try store.save(TestSupport.textClip("A", at: start.addingTimeInterval(2)))

        XCTAssertEqual(try store.recent().map(\.previewText), ["A", "B"])
    }

    func testRepresentationsRoundTrip() throws {
        let store = try HistoryStore.inMemory()
        let item = try store.save(TestSupport.textClip("hello", at: start))
        let reps = try store.representations(for: try XCTUnwrap(item.id))

        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps.first?.type, NSPasteboard.PasteboardType.string.rawValue)
        XCTAssertEqual(reps.first.map { String(decoding: $0.data, as: UTF8.self) }, "hello")
    }

    /// POC checklist: "History survives quitting and relaunching the app."
    func testHistorySurvivesReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("history.sqlite").path

        do {
            let store = try HistoryStore.atPath(path)
            try store.save(TestSupport.textClip("keep me", at: start))
        } // store closes here, like quitting the app

        let reopened = try HistoryStore.atPath(path)
        XCTAssertEqual(try reopened.recent().map(\.previewText), ["keep me"])
    }

    func testDeleteRemovesItemAndItsData() throws {
        let store = try HistoryStore.inMemory()
        let item = try store.save(TestSupport.textClip("bye", at: start))
        let id = try XCTUnwrap(item.id)

        try store.delete(id: id)

        XCTAssertEqual(try store.count(), 0)
        XCTAssertTrue(try store.representations(for: id).isEmpty)
    }

    func testDeleteAll() throws {
        let store = try HistoryStore.inMemory()
        for i in 0..<5 { try store.save(TestSupport.textClip("item \(i)", at: start.addingTimeInterval(Double(i)))) }
        try store.deleteAll()
        XCTAssertEqual(try store.count(), 0)
    }

    func testBumpMovesItemToTop() throws {
        let store = try HistoryStore.inMemory()
        let old = try store.save(TestSupport.textClip("old", at: start))
        try store.save(TestSupport.textClip("new", at: start.addingTimeInterval(10)))

        try store.bump(id: try XCTUnwrap(old.id), to: start.addingTimeInterval(20))

        XCTAssertEqual(try store.recent().first?.previewText, "old")
    }
}

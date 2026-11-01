// MultiPasteTests.swift — selection order, "Paste together", and auto-paste rules.
// A fake keystroke sender is used, so these tests never type into your apps.

import AppKit
import XCTest
@testable import MCAS

final class MultiPasteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Selection

    func testSelectionKeepsPickOrderAndToggles() {
        var selection = Selection()
        selection.toggle(30)
        selection.toggle(10)
        selection.toggle(20)
        XCTAssertEqual(selection.ids, [30, 10, 20])
        XCTAssertEqual(selection.position(of: 10), 2)

        selection.toggle(10)
        XCTAssertEqual(selection.ids, [30, 20])
        XCTAssertNil(selection.position(of: 10))
    }

    // MARK: Paste together

    /// POC checklist: "Selecting 3 items and choosing Paste together pastes all 3, one per line."
    @MainActor
    func testThreeItemsPasteTogetherOnePerLine() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let a = try store.save(TestSupport.textClip("first", at: start))
        let b = try store.save(TestSupport.textClip("second", at: start.addingTimeInterval(1)))
        let c = try store.save(TestSupport.textClip("third", at: start.addingTimeInterval(2)))

        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})

        // Picked in the order c, a, b → pasted in that order.
        let result = try service.pasteTogether([c, a, b], separator: PasteSeparator.newline.string)

        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(pb.string(forType: .string), "third\nfirst\nsecond")
        XCTAssertTrue(pb.types?.contains(.mcasInternal) ?? false, "joined text must not be saved as a new item")
    }

    @MainActor
    func testImagesAreSkippedWhenJoining() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let text = try store.save(TestSupport.textClip("caption", at: start))

        let png = TestSupport.pngData()
        let imageRep = CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.png.rawValue, data: png)
        let image = try store.save(CapturedClip(
            kind: .image, previewText: "Image", representations: [imageRep],
            sourceAppBundleID: nil, sourceAppName: nil, thumbnail: nil, createdAt: start.addingTimeInterval(1),
            contentHash: ClipReader.contentHash(kind: .image, string: nil, representations: [imageRep])
        ))

        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})
        _ = try service.pasteTogether([image, text], separator: ", ")

        XCTAssertEqual(pb.string(forType: .string), "caption")
    }

    @MainActor
    func testOnlyImagesMeansNothingToPaste() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let rep = CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.png.rawValue, data: TestSupport.pngData())
        let image = try store.save(CapturedClip(
            kind: .image, previewText: "Image", representations: [rep], sourceAppBundleID: nil, sourceAppName: nil,
            thumbnail: nil, createdAt: start, contentHash: "img"
        ))
        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})

        XCTAssertEqual(try service.pasteTogether([image], separator: "\n"), .nothingToPaste)
    }

    // MARK: Auto-paste

    @MainActor
    func testWithoutAccessibilityItemIsStillCopied() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let item = try store.save(TestSupport.textClip("hello", at: start))
        var keystrokes = 0
        let service = PasteService(store: store, pasteboard: pb, isTrusted: { false }, sendPasteKeystroke: { keystrokes += 1 })

        let result = try service.paste(item)

        XCTAssertEqual(result, .copiedNeedsAccessibility)
        XCTAssertEqual(pb.string(forType: .string), "hello", "user can still press ⌘V")
        XCTAssertEqual(keystrokes, 0)
    }

    @MainActor
    func testCopiedFilesJoinAsPaths() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let fileType = NSPasteboard.PasteboardType.fileURL.rawValue
        let reps = [
            CapturedClip.Representation(itemIndex: 0, type: fileType, data: Data("file:///tmp/a.txt".utf8)),
            CapturedClip.Representation(itemIndex: 1, type: fileType, data: Data("file:///tmp/b.txt".utf8)),
        ]
        let files = try store.save(CapturedClip(
            kind: .file, previewText: "2 files", representations: reps, sourceAppBundleID: nil, sourceAppName: nil,
            thumbnail: nil, createdAt: start, contentHash: "files"
        ))
        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})

        XCTAssertEqual(try service.text(of: files), "/tmp/a.txt\n/tmp/b.txt")
    }
}

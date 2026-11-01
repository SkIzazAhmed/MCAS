// ScreenshotWatcherTests.swift — screenshot files become image items in history.

import AppKit
import XCTest
@testable import MCAS

final class ScreenshotWatcherTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testPNGScreenshotBecomesImageItem() throws {
        let file = folder.appendingPathComponent("Screenshot 2026-10-29 at 5.00.00 PM.png")
        try TestSupport.pngData(width: 40, height: 20).write(to: file)

        let clip = try XCTUnwrap(ScreenshotWatcher.makeClip(fileURL: file))

        XCTAssertEqual(clip.kind, .image)
        XCTAssertEqual(clip.previewText, "Screenshot 40×20")
        XCTAssertEqual(clip.sourceAppName, "Screenshot")
        XCTAssertEqual(clip.representations.map(\.type), [NSPasteboard.PasteboardType.png.rawValue])
        XCTAssertNotNil(clip.thumbnail)
    }

    func testJPEGScreenshotIsStoredAsPNG() throws {
        let png = TestSupport.pngData(width: 30, height: 30)
        let jpeg = try XCTUnwrap(NSBitmapImageRep(data: png)?.representation(using: .jpeg, properties: [:]))
        let file = folder.appendingPathComponent("Screenshot.jpg")
        try jpeg.write(to: file)

        let clip = try XCTUnwrap(ScreenshotWatcher.makeClip(fileURL: file))

        XCTAssertEqual(clip.representations.first?.type, NSPasteboard.PasteboardType.png.rawValue)
        XCTAssertEqual(clip.previewText, "Screenshot 30×30")
    }

    func testScreenRecordingsAreSkipped() throws {
        let file = folder.appendingPathComponent("Screen Recording.mov")
        try Data([0, 1, 2, 3]).write(to: file)
        XCTAssertNil(ScreenshotWatcher.makeClip(fileURL: file))
    }

    func testSameScreenshotTwiceIsADuplicate() throws {
        let data = TestSupport.pngData()
        let a = folder.appendingPathComponent("a.png"), b = folder.appendingPathComponent("b.png")
        try data.write(to: a); try data.write(to: b)

        let store = try HistoryStore.inMemory()
        try store.save(try XCTUnwrap(ScreenshotWatcher.makeClip(fileURL: a)))
        try store.save(try XCTUnwrap(ScreenshotWatcher.makeClip(fileURL: b)))

        XCTAssertEqual(try store.count(), 1)
    }
}

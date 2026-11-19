// V3FeatureTests.swift — smart types and the paste queue.

import AppKit
import XCTest
@testable import MCAS

final class SmartTypeTests: XCTestCase {
    func testLinks() {
        XCTAssertEqual(SmartType.detect(kind: .url, text: "https://github.com/SkIzazAhmed/MCAS"),
                       .link(URL(string: "https://github.com/SkIzazAhmed/MCAS")!))
        XCTAssertEqual(SmartType.detect(kind: .text, text: "not a link"), .none)
    }

    func testHexColors() {
        XCTAssertEqual(SmartType.detect(kind: .text, text: "#FF6B00"), .color(red: 255, green: 107, blue: 0))
        XCTAssertEqual(SmartType.detect(kind: .text, text: " #f60 "), .color(red: 255, green: 102, blue: 0))
        XCTAssertEqual(SmartType.detect(kind: .text, text: "facade"), .none, "hex-looking words need a #")
        XCTAssertEqual(SmartType.detect(kind: .text, text: "#12345"), .none, "5 digits is not a color")
    }

    func testRGBColors() {
        XCTAssertEqual(SmartType.detect(kind: .text, text: "rgb(10, 20, 30)"), .color(red: 10, green: 20, blue: 30))
        XCTAssertEqual(SmartType.detect(kind: .text, text: "RGBA(255,255,255,0.5)"), .color(red: 255, green: 255, blue: 255))
        XCTAssertEqual(SmartType.detect(kind: .text, text: "rgb(300, 0, 0)"), .none, "out of range")
    }

    func testColorConversions() {
        let color = SmartType.color(red: 255, green: 107, blue: 0)
        XCTAssertEqual(color.hexString, "#FF6B00")
        XCTAssertEqual(color.rgbString, "rgb(255, 107, 0)")
        XCTAssertNil(SmartType.none.hexString)
    }

    func testEmails() {
        XCTAssertEqual(SmartType.detect(kind: .text, text: "izaz@opensuse.org"), .email("izaz@opensuse.org"))
        XCTAssertEqual(SmartType.detect(kind: .text, text: "write to izaz@opensuse.org today"), .none)
    }

    func testCode() {
        let swift = "func greet() {\n    return \"hi\"\n}"
        XCTAssertEqual(SmartType.detect(kind: .text, text: swift), .code)
        XCTAssertEqual(SmartType.detect(kind: .text, text: "Dear team,\nsee you {soon}"), .none, "one sign is not enough")
        XCTAssertEqual(SmartType.detect(kind: .text, text: "let x = 1; let y = 2"), .none, "single line")
    }

    func testImagesHaveNoSmartType() {
        XCTAssertEqual(SmartType.detect(kind: .image, text: "#FF6B00"), .none)
    }
}

final class PasteQueueTests: XCTestCase {
    private func item(_ id: Int64, _ text: String) -> ClipItem {
        ClipItem(id: id, createdAt: .now, kind: .text, previewText: text, sourceAppBundleID: nil,
                 sourceAppName: nil, contentHash: text, byteSize: 0, thumbnail: nil)
    }

    func testEmptyQueueIsNotCreated() {
        XCTAssertNil(PasteQueue(items: []))
    }

    func testAdvancesInPickOrderThenFinishes() throws {
        var queue = try XCTUnwrap(PasteQueue(items: [item(1, "name"), item(2, "email"), item(3, "phone")]))

        XCTAssertEqual(queue.current?.previewText, "name")
        XCTAssertEqual(queue.progressLabel, "1 of 3")
        XCTAssertEqual(queue.advance()?.previewText, "email")
        XCTAssertEqual(queue.shortLabel, "2/3")
        XCTAssertEqual(queue.advance()?.previewText, "phone")
        XCTAssertNil(queue.advance())
        XCTAssertTrue(queue.isFinished)
        XCTAssertNil(queue.advance(), "stays finished")
    }

    /// Writing a queue item to the clipboard must not reorder your history.
    @MainActor
    func testCopyingWithoutBumpKeepsOrder() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let old = try store.save(TestSupport.textClip("old", at: start))
        try store.save(TestSupport.textClip("new", at: start.addingTimeInterval(10)))
        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})

        try service.copyToClipboard(old, bump: false)

        XCTAssertEqual(pb.string(forType: .string), "old")
        XCTAssertEqual(try store.recent().first?.previewText, "new")
    }
}

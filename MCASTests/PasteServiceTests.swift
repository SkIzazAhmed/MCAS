// PasteServiceTests.swift — putting an item back gives exactly what was copied.
//
// Note: a watcher treats whatever is already on the clipboard when it's created
// as "seen". So in tests, create the watcher BEFORE copying.

import AppKit
import XCTest
@testable import MCAS

final class PasteServiceTests: XCTestCase {

    @MainActor
    func testRichTextComesBackIdentical() throws {
        let source = TestSupport.makePasteboard(); defer { source.releaseGlobally() }
        let target = TestSupport.makePasteboard(); defer { target.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let watcher = PasteboardWatcher(pasteboard: source, sourceAppProvider: { nil })

        // Copy rich text and capture it.
        let attributed = NSAttributedString(string: "Styled", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let original = NSPasteboardItem()
        original.setString("Styled", forType: .string)
        original.setData(rtf, forType: .rtf)
        source.clearContents()
        source.writeObjects([original])

        let clip = try XCTUnwrap(watcher.checkForChanges())
        let item = try store.save(clip)

        // Put it back on another pasteboard.
        try PasteService(store: store, pasteboard: target).copyToClipboard(item)

        XCTAssertEqual(target.string(forType: .string), "Styled")
        XCTAssertEqual(target.data(forType: .rtf), rtf)
        XCTAssertTrue(target.types?.contains(.mcasInternal) ?? false, "MCAS marks its own writes so they aren't saved twice")
    }

    @MainActor
    func testMultipleFilesComeBackAsSeparateItems() throws {
        let source = TestSupport.makePasteboard(); defer { source.releaseGlobally() }
        let target = TestSupport.makePasteboard(); defer { target.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let watcher = PasteboardWatcher(pasteboard: source, sourceAppProvider: { nil })

        source.clearContents()
        source.writeObjects([URL(fileURLWithPath: "/tmp/a.txt") as NSURL, URL(fileURLWithPath: "/tmp/b.txt") as NSURL])
        let clip = try XCTUnwrap(watcher.checkForChanges())
        let item = try store.save(clip)

        try PasteService(store: store, pasteboard: target).copyToClipboard(item)

        XCTAssertEqual(target.pasteboardItems?.count, 2)
        let urls = target.readObjects(forClasses: [NSURL.self]) as? [URL]
        XCTAssertEqual(urls?.map(\.lastPathComponent), ["a.txt", "b.txt"])
    }
}

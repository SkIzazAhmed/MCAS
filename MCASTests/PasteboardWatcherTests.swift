// PasteboardWatcherTests.swift — does the watcher notice copies and read them correctly?

import AppKit
import XCTest
@testable import MCAS

final class PasteboardWatcherTests: XCTestCase {

    @MainActor
    func testNothingCapturedUntilSomethingIsCopied() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })
        XCTAssertNil(watcher.checkForChanges())
    }

    @MainActor
    func testCapturesPlainText() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })
        var received: [CapturedClip] = []
        watcher.onCapture = { received.append($0) }

        pb.clearContents()
        pb.setString("Hello MCAS", forType: .string)
        let clip = watcher.checkForChanges()

        XCTAssertEqual(clip?.kind, .text)
        XCTAssertEqual(clip?.previewText, "Hello MCAS")
        XCTAssertEqual(clip?.sourceAppName, "TextEdit")
        XCTAssertEqual(received.count, 1, "onCapture should be called once")
        XCTAssertNil(watcher.checkForChanges(), "same copy must not be captured twice")
    }

    @MainActor
    func testSkipsPasswordManagerMarker() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })

        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        pb.clearContents()
        pb.writeObjects([item])

        XCTAssertNil(watcher.checkForChanges())
    }

    @MainActor
    func testSkipsCopiesFromIgnoredApps() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: {
            SourceApp(bundleID: "com.1password.1password", name: "1Password")
        })
        pb.clearContents()
        pb.setString("secret", forType: .string)
        XCTAssertNil(watcher.checkForChanges())
    }

    @MainActor
    func testPauseIgnoresCopiesAndDoesNotCatchUpLater() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })

        watcher.isPaused = true
        pb.clearContents()
        pb.setString("while paused", forType: .string)
        XCTAssertNil(watcher.checkForChanges())

        watcher.isPaused = false
        XCTAssertNil(watcher.checkForChanges(), "the paused copy must not be saved after resuming")

        pb.clearContents()
        pb.setString("after resume", forType: .string)
        XCTAssertEqual(watcher.checkForChanges()?.previewText, "after resume")
    }

    @MainActor
    func testSkipsMCASOwnWrites() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })

        let item = NSPasteboardItem()
        item.setString("pasted from the shelf", forType: .string)
        item.setData(Data(), forType: .mcasInternal)
        pb.clearContents()
        pb.writeObjects([item])

        XCTAssertNil(watcher.checkForChanges())
    }

    @MainActor
    func testDetectsURL() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { nil })
        pb.clearContents()
        pb.setString("https://www.opensuse.org/", forType: .string)
        XCTAssertEqual(watcher.checkForChanges()?.kind, .url)
    }

    @MainActor
    func testDetectsRichText() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { nil })

        let attributed = NSAttributedString(string: "Bold words", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
        let item = NSPasteboardItem()
        item.setString("Bold words", forType: .string)
        item.setData(rtf, forType: .rtf)
        pb.clearContents()
        pb.writeObjects([item])

        let clip = watcher.checkForChanges()
        XCTAssertEqual(clip?.kind, .richText)
        let keptTypes = clip?.representations.map(\.type) ?? []
        XCTAssertTrue(keptTypes.contains(NSPasteboard.PasteboardType.rtf.rawValue), "RTF is kept, not just plain text")
        XCTAssertTrue(keptTypes.contains(NSPasteboard.PasteboardType.string.rawValue))
    }

    @MainActor
    func testCapturesImageWithThumbnail() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { nil })
        pb.clearContents()
        pb.setData(TestSupport.pngData(width: 40, height: 20), forType: .png)

        let clip = watcher.checkForChanges()
        XCTAssertEqual(clip?.kind, .image)
        XCTAssertEqual(clip?.previewText, "Image 40×20")
        XCTAssertNotNil(clip?.thumbnail)
    }

    @MainActor
    func testCapturesMultipleFiles() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { nil })
        pb.clearContents()
        pb.writeObjects([
            URL(fileURLWithPath: "/tmp/notes.txt") as NSURL,
            URL(fileURLWithPath: "/tmp/slides.pdf") as NSURL,
        ])

        let clip = watcher.checkForChanges()
        XCTAssertEqual(clip?.kind, .file)
        XCTAssertEqual(clip?.previewText, "2 files: notes.txt, slides.pdf")
    }

    /// POC checklist: "Copying 10 times keeps all 10 in history, newest first."
    @MainActor
    func testTenCopiesAreAllKeptNewestFirst() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })
        watcher.onCapture = { _ = try? store.save($0) }

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 1...10 {
            pb.clearContents()
            pb.setString("Copy \(i)", forType: .string)
            watcher.checkForChanges(now: start.addingTimeInterval(Double(i)))
        }

        let items = try store.recent()
        XCTAssertEqual(items.count, 10)
        XCTAssertEqual(items.first?.previewText, "Copy 10")
        XCTAssertEqual(items.last?.previewText, "Copy 1")
    }
}

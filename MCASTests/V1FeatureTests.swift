// V1FeatureTests.swift — pin, search, retention, one-time codes, secret guard, settings.

import AppKit
import XCTest
@testable import MCAS

final class PinSearchRetentionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testPinnedItemsAreListedSeparately() throws {
        let store = try HistoryStore.inMemory()
        let a = try store.save(TestSupport.textClip("keep me", at: start))
        try store.save(TestSupport.textClip("ordinary", at: start.addingTimeInterval(1)))

        try store.setPinned(id: try XCTUnwrap(a.id), true)

        XCTAssertEqual(try store.pinned().map(\.previewText), ["keep me"])
        XCTAssertEqual(try store.recent().map(\.previewText), ["ordinary"])
        XCTAssertEqual(try store.count(), 2)
    }

    func testCopyingAPinnedItemAgainKeepsItPinned() throws {
        let store = try HistoryStore.inMemory()
        let a = try store.save(TestSupport.textClip("address", at: start))
        try store.setPinned(id: try XCTUnwrap(a.id), true)

        let again = try store.save(TestSupport.textClip("address", at: start.addingTimeInterval(60)))

        XCTAssertTrue(again.isPinned)
        XCTAssertEqual(try store.count(), 1)
    }

    func testSearchIsCaseInsensitiveAndPinnedFirst() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("Meeting notes for Monday", at: start))
        let pinned = try store.save(TestSupport.textClip("monday standup link", at: start.addingTimeInterval(-100)))
        try store.save(TestSupport.textClip("unrelated", at: start.addingTimeInterval(1)))
        try store.setPinned(id: try XCTUnwrap(pinned.id), true)

        let results = try store.search("MONDAY")

        XCTAssertEqual(results.map(\.previewText), ["monday standup link", "Meeting notes for Monday"])
    }

    func testSearchTreatsPercentLiterally() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("50% off", at: start))
        try store.save(TestSupport.textClip("500 items", at: start.addingTimeInterval(1)))

        XCTAssertEqual(try store.search("50%").map(\.previewText), ["50% off"])
        XCTAssertTrue(try store.search("   ").isEmpty)
    }

    func testSearchMatchesSourceApp() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("hello", at: start)) // source: TextEdit
        XCTAssertEqual(try store.search("textedit").count, 1)
    }

    func testRetentionRemovesOldItemsButKeepsPinned() throws {
        let store = try HistoryStore.inMemory()
        let now = start
        let oldPinned = try store.save(TestSupport.textClip("old but pinned", at: now.addingTimeInterval(-40 * 86_400)))
        try store.save(TestSupport.textClip("old", at: now.addingTimeInterval(-40 * 86_400 - 1)))
        try store.save(TestSupport.textClip("recent", at: now.addingTimeInterval(-2 * 86_400)))
        try store.setPinned(id: try XCTUnwrap(oldPinned.id), true)

        let removed = try store.applyRetention(days: 30, now: now)

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try store.recent().map(\.previewText), ["recent"])
        XCTAssertEqual(try store.pinned().map(\.previewText), ["old but pinned"])
    }

    func testRetentionZeroMeansForever() throws {
        let store = try HistoryStore.inMemory()
        try store.save(TestSupport.textClip("ancient", at: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(try store.applyRetention(days: 0, now: start), 0)
        XCTAssertEqual(try store.count(), 1)
    }

    func testOneTimeCodesExpire() throws {
        let store = try HistoryStore.inMemory()
        var code = TestSupport.textClip("482913", at: start)
        code.expiresAt = start.addingTimeInterval(60)
        try store.save(code)
        try store.save(TestSupport.textClip("normal", at: start))

        XCTAssertEqual(try store.deleteExpired(now: start.addingTimeInterval(30)), 0, "not yet")
        XCTAssertEqual(try store.deleteExpired(now: start.addingTimeInterval(61)), 1)
        XCTAssertEqual(try store.recent().map(\.previewText), ["normal"])
    }

    func testPinningCancelsExpiry() throws {
        let store = try HistoryStore.inMemory()
        var code = TestSupport.textClip("482913", at: start)
        code.expiresAt = start.addingTimeInterval(60)
        let item = try store.save(code)

        try store.setPinned(id: try XCTUnwrap(item.id), true)

        XCTAssertEqual(try store.deleteExpired(now: start.addingTimeInterval(120)), 0)
        XCTAssertEqual(try store.pinned().first?.expiresAt, nil)
    }

    func testClearHistoryCanKeepPinned() throws {
        let store = try HistoryStore.inMemory()
        let a = try store.save(TestSupport.textClip("pinned", at: start))
        try store.save(TestSupport.textClip("other", at: start.addingTimeInterval(1)))
        try store.setPinned(id: try XCTUnwrap(a.id), true)

        try store.deleteAll(includingPinned: false)

        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.pinned().count, 1)
    }

    @MainActor
    func testPasteAsPlainTextDropsFormatting() throws {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let store = try HistoryStore.inMemory()
        let attributed = NSAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: 4), documentAttributes: [:]))
        let reps = [
            CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.string.rawValue, data: Data("Bold".utf8)),
            CapturedClip.Representation(itemIndex: 0, type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf),
        ]
        let item = try store.save(CapturedClip(
            kind: .richText, previewText: "Bold", representations: reps, sourceAppBundleID: nil, sourceAppName: nil,
            thumbnail: nil, createdAt: start, contentHash: "rich"
        ))
        let service = PasteService(store: store, pasteboard: pb, isTrusted: { true }, sendPasteKeystroke: {})

        _ = try service.pastePlainText(item)

        XCTAssertEqual(pb.string(forType: .string), "Bold")
        XCTAssertNil(pb.data(forType: .rtf), "formatting removed")
    }
}

final class SecretGuardTests: XCTestCase {
    func testAPIKeysAreSkipped() {
        let keys = [
            "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789",
            "ghp_abcdefghijklmnopqrstuvwxyz0123456789AB",
            "AKIAIOSFODNN7EXAMPLE",
            "export OPENAI_API_KEY=sk-proj-abcdefghij1234567890XYZ",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----",
        ]
        for key in keys {
            guard case .skip = SecretGuard.classify(key) else {
                return XCTFail("should skip: \(key.prefix(20))")
            }
        }
    }

    func testValidCardNumbersAreSkipped() {
        // Standard test card numbers (they pass the Luhn check).
        for card in ["4111 1111 1111 1111", "5555-5555-5555-4444", "378282246310005"] {
            guard case .skip = SecretGuard.classify(card) else { return XCTFail("should skip \(card)") }
        }
    }

    func testRandomLongNumbersAreKept() {
        XCTAssertEqual(SecretGuard.classify("4111 1111 1111 1112"), .allow, "fails Luhn: not a card")
        XCTAssertEqual(SecretGuard.classify("+91 98765 43210"), .allow)
    }

    func testOneTimeCodesAreKeptBriefly() {
        for code in ["482913", " 12345678 ", "482 913", "482-913"] {
            XCTAssertEqual(SecretGuard.classify(code), .keepBriefly(seconds: 60), code)
        }
    }

    func testOrdinaryTextIsAllowed() {
        for text in ["2026", "hello world", "1234", "sk-short", "Order #48291 shipped", "https://github.com/SkIzazAhmed/MCAS"] {
            XCTAssertEqual(SecretGuard.classify(text), .allow, text)
        }
    }

    @MainActor
    func testWatcherSkipsKeysAndMarksCodes() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        pb.clearContents()
        pb.setString("ghp_abcdefghijklmnopqrstuvwxyz0123456789AB", forType: .string)
        XCTAssertNil(watcher.checkForChanges(now: now))

        pb.clearContents()
        pb.setString("482913", forType: .string)
        XCTAssertEqual(watcher.checkForChanges(now: now)?.expiresAt, now.addingTimeInterval(60))
    }

    @MainActor
    func testWatcherSavesEverythingWhenGuardIsOff() {
        let pb = TestSupport.makePasteboard(); defer { pb.releaseGlobally() }
        let watcher = PasteboardWatcher(pasteboard: pb, sourceAppProvider: { TestSupport.textEdit })
        watcher.secretGuardEnabled = false

        pb.clearContents()
        pb.setString("482913", forType: .string)
        let clip = watcher.checkForChanges()
        XCTAssertNotNil(clip)
        XCTAssertNil(clip?.expiresAt)
    }
}

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testDefaultsAndPersistence() throws {
        let suite = "MCASTests.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hotKey, .optionCommandV)
        XCTAssertEqual(settings.retentionDays, 30)
        XCTAssertTrue(settings.secretGuardEnabled)

        settings.setHotKey(.controlOptionV)
        settings.setRetentionDays(7)
        settings.setSecretGuardEnabled(false)
        settings.addIgnoredApp("com.example.notes")
        settings.addIgnoredApp("com.example.notes") // no duplicates

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hotKey, .controlOptionV)
        XCTAssertEqual(reloaded.retentionDays, 7)
        XCTAssertFalse(reloaded.secretGuardEnabled)
        XCTAssertEqual(reloaded.customIgnoredApps, ["com.example.notes"])
        XCTAssertTrue(reloaded.allIgnoredBundleIDs.contains("com.bitwarden.desktop"), "built-in list always included")

        reloaded.removeIgnoredApp("com.example.notes")
        XCTAssertTrue(AppSettings(defaults: defaults).customIgnoredApps.isEmpty)
    }
}

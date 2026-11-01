// PasteService.swift
//
// What: puts saved items back on the clipboard and pastes them into the app you
//       were using (F5), one item or several joined together (F6).
//
// How auto-paste works: MCAS writes the item to the clipboard, then sends a ⌘V
// keystroke to the front app. Sending keystrokes needs the Accessibility
// permission. Without it, the item is still on the clipboard and you press ⌘V.
//
// The MCAS marker type is added to everything written here, so the watcher
// knows "this was us" and doesn't save it again.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class PasteService {
    enum Result: Equatable {
        /// On the clipboard and ⌘V sent.
        case pasted
        /// On the clipboard; Accessibility is off, so the user presses ⌘V.
        case copiedNeedsAccessibility
        /// None of the selected items had text.
        case nothingToPaste
    }

    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let isTrusted: () -> Bool
    private let sendPasteKeystroke: () -> Void

    /// - Parameters:
    ///   - isTrusted / sendPasteKeystroke: real Accessibility by default; tests pass fakes
    ///     so running tests never types into your apps.
    init(
        store: HistoryStore,
        pasteboard: NSPasteboard = .general,
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        sendPasteKeystroke: @escaping () -> Void = PasteService.sendCommandV
    ) {
        self.store = store
        self.pasteboard = pasteboard
        self.isTrusted = isTrusted
        self.sendPasteKeystroke = sendPasteKeystroke
    }

    // MARK: - One item

    /// Puts `item` on the clipboard and moves it to the top of history.
    func copyToClipboard(_ item: ClipItem) throws {
        guard let id = item.id else { return }
        let reps = try store.representations(for: id)
        guard !reps.isEmpty else {
            Log.paste.error("Item \(id) has no data to paste")
            return
        }
        Self.write(reps, to: pasteboard)
        try store.bump(id: id)
        Log.paste.info("Copied item \(id) (\(item.kind.rawValue, privacy: .public)) to the clipboard")
    }

    /// Copy + ⌘V into the front app.
    @discardableResult
    func paste(_ item: ClipItem) throws -> Result {
        try copyToClipboard(item)
        return pasteIntoFrontApp()
    }

    // MARK: - Several items

    /// Joins the text of several items (in the order given) and pastes it once.
    /// Items without text (e.g. images) are skipped.
    @discardableResult
    func pasteTogether(_ items: [ClipItem], separator: String) throws -> Result {
        let texts = try items.compactMap { try text(of: $0) }
        guard !texts.isEmpty else { return .nothingToPaste }
        Self.writeText(texts.joined(separator: separator), to: pasteboard)
        Log.paste.info("Pasting \(texts.count) items together")
        return pasteIntoFrontApp()
    }

    /// The full text of an item: its plain text, or the file paths for copied files.
    func text(of item: ClipItem) throws -> String? {
        guard let id = item.id else { return nil }
        let reps = try store.representations(for: id)
        if let plain = reps.first(where: { $0.type == NSPasteboard.PasteboardType.string.rawValue }) {
            return String(decoding: plain.data, as: UTF8.self)
        }
        let paths = reps
            .filter { $0.type == NSPasteboard.PasteboardType.fileURL.rawValue }
            .compactMap { URL(string: String(decoding: $0.data, as: UTF8.self))?.path }
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
    }

    // MARK: - Writing to the clipboard

    /// Rebuilds the original pasteboard items from the saved representations.
    static func write(_ reps: [ClipRepresentation], to pasteboard: NSPasteboard) {
        let byItem = Dictionary(grouping: reps, by: \.itemIndex).sorted { $0.key < $1.key }
        let items: [NSPasteboardItem] = byItem.map { _, itemReps in
            let item = NSPasteboardItem()
            for rep in itemReps {
                item.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type))
            }
            return item
        }
        items.first?.setData(Data(), forType: .mcasInternal)
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    static func writeText(_ text: String, to pasteboard: NSPasteboard) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .mcasInternal)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    // MARK: - ⌘V

    private func pasteIntoFrontApp() -> Result {
        guard isTrusted() else {
            Log.paste.notice("Accessibility is off: item is on the clipboard, user presses ⌘V")
            return .copiedNeedsAccessibility
        }
        let send = sendPasteKeystroke
        // Wait a moment so the shelf has closed and the front app has focus again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let ourPID = ProcessInfo.processInfo.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication
            guard front?.processIdentifier != ourPID else {
                Log.paste.notice("MCAS itself is in front; not sending ⌘V")
                return
            }
            send()
            Log.paste.info("Sent ⌘V to \(front?.localizedName ?? "unknown app", privacy: .public)")
        }
        return .pasted
    }

    /// Presses ⌘V as if on the keyboard.
    nonisolated static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// How "Paste together" joins items.
enum PasteSeparator: String, CaseIterable, Identifiable {
    case newline, space, comma

    var id: String { rawValue }

    var string: String {
        switch self {
        case .newline: return "\n"
        case .space: return " "
        case .comma: return ", "
        }
    }

    var label: String {
        switch self {
        case .newline: return "One per line"
        case .space: return "Spaces"
        case .comma: return "Commas"
        }
    }
}

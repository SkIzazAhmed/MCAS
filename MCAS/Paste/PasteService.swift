// PasteService.swift
//
// What: puts a saved item back on the clipboard, exactly as it was copied.
// Why:  first half of F5 (one-click paste). The second half — sending ⌘V to the
//       front app via Accessibility — comes with the shelf, later in the POC.
//
// The MCAS marker type is added so the watcher knows "this was us" and doesn't
// save it again; instead the item is bumped to the top of history.

import AppKit

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard
    private let store: HistoryStore

    init(store: HistoryStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
    }

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
        Log.paste.info("Copied item \(id) (\(item.kind.rawValue, privacy: .public)) back to the clipboard")
    }

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
}

// PasteQueue.swift
//
// What: the "Paste as queue" list (second half of F6). You pick items in order;
//       MCAS puts the first on the clipboard, and every time you press ⌘V it
//       swaps in the next one. Great for filling in a form field by field.
// Why:  plain logic (which item is next, how many are left) kept apart from
//       the keyboard watching, so it can be tested.

import Foundation

struct PasteQueue: Equatable {
    let items: [ClipItem]
    private(set) var position = 0

    /// nil if `items` is empty.
    init?(items: [ClipItem]) {
        guard !items.isEmpty else { return nil }
        self.items = items
    }

    /// The item currently on the clipboard.
    var current: ClipItem? {
        items.indices.contains(position) ? items[position] : nil
    }

    var isFinished: Bool { current == nil }

    /// e.g. "2 of 5": shown while the queue runs.
    var progressLabel: String {
        "\(min(position + 1, items.count)) of \(items.count)"
    }

    /// Short form for the menu bar, e.g. "2/5".
    var shortLabel: String {
        "\(min(position + 1, items.count))/\(items.count)"
    }

    /// Moves to the next item and returns it, or nil when the queue is done.
    @discardableResult
    mutating func advance() -> ClipItem? {
        guard !isFinished else { return nil }
        position += 1
        return current
    }
}

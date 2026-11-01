// Selection.swift
//
// What: the list of items you've ⌘-clicked in the shelf, in the order you picked them.
// Why:  "Paste together" pastes in that order, so order matters. Kept as plain
//       logic so it can be tested without any UI.

import Foundation

struct Selection: Equatable {
    private(set) var ids: [Int64] = []

    var isEmpty: Bool { ids.isEmpty }
    var count: Int { ids.count }

    /// Adds the item, or removes it if it was already selected.
    mutating func toggle(_ id: Int64) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
    }

    /// 1-based position for the badge on the row, or nil if not selected.
    func position(of id: Int64) -> Int? {
        ids.firstIndex(of: id).map { $0 + 1 }
    }

    mutating func clear() { ids.removeAll() }

    /// The selected items in pick order (items no longer in history are dropped).
    func items(from all: [ClipItem]) -> [ClipItem] {
        ids.compactMap { id in all.first { $0.id == id } }
    }
}

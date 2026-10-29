// PasteboardTypes.swift
//
// What: the special clipboard type names MCAS cares about.
// Why:  keeps magic strings in one place.

import AppKit

extension NSPasteboard.PasteboardType {
    /// MCAS adds this marker when *it* puts something on the clipboard
    /// (e.g. when you paste from the shelf), so the watcher doesn't save it again.
    static let mcasInternal = NSPasteboard.PasteboardType("com.izaz.mcas.internal")
}

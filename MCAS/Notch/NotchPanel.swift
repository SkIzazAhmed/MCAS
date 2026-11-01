// NotchPanel.swift
//
// What: the two borderless windows MCAS puts at the top of the screen:
//   • the trigger: an invisible window exactly over the notch that notices hover/click
//   • the shelf: the panel that drops down with your history
// Why:  these need special window settings that normal SwiftUI windows don't offer.
//
// Key settings:
//   • .nonactivatingPanel: clicking the shelf doesn't steal focus from the app
//     you're working in, so auto-paste goes to the right place.
//   • level .statusBar: above the menu bar, so it can sit over the notch.
//   • canJoinAllSpaces + fullScreenAuxiliary: shows on every desktop and over full-screen apps.

import AppKit

final class NotchPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Clicking buttons in the panel must NOT move keyboard focus here, or the
        // ⌘V we send afterwards has nowhere to go. Only text fields take focus.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS normally pushes windows below the menu bar; we want to sit on it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Esc
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// Clicked somewhere else.
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// The trigger window's content: reports mouse enter/leave and clicks.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    /// On a real notch the view is black (invisible against the notch).
    /// On screens without a notch it's almost transparent, but not fully:
    /// fully transparent pixels let the mouse pass straight through.
    var isOverRealNotch = true {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        (isOverRealNotch ? NSColor.black : NSColor.black.withAlphaComponent(0.02)).setFill()
        bounds.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

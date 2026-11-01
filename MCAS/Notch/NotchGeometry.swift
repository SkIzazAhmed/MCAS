// NotchGeometry.swift
//
// What: works out where the notch is on a screen, and where the shelf panel goes.
// Why:  notch sizes differ between MacBook models, so nothing is hard-coded:
//       everything is read from NSScreen at runtime.
//
// How the notch is found:
//   • safeAreaInsets.top > 0 means the screen has a notch (its height = menu bar height).
//   • auxiliaryTopLeftArea / auxiliaryTopRightArea are the usable menu bar parts
//     left and right of it. The notch is the gap between them.
// Screens without a notch get a small invisible "tab" at the top-center instead.
//
// Coordinates: macOS screen coordinates, origin at the BOTTOM-left, y goes up.

import AppKit

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    /// The notch (or the fallback tab) in screen coordinates.
    var notchRect: CGRect
    var hasNotch: Bool

    static let fallbackTabWidth: CGFloat = 200

    static func forScreen(_ screen: NSScreen) -> NotchGeometry {
        compute(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width ?? 0,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width ?? 0,
            menuBarHeight: NSStatusBar.system.thickness
        )
    }

    /// Pure math, so it can be tested with made-up screens.
    static func compute(
        screenFrame frame: CGRect,
        safeAreaTop: CGFloat,
        leftAreaWidth: CGFloat,
        rightAreaWidth: CGFloat,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, leftAreaWidth > 0, rightAreaWidth > 0 {
            let width = frame.width - leftAreaWidth - rightAreaWidth
            if width > 0 {
                let rect = CGRect(x: frame.minX + leftAreaWidth, y: frame.maxY - safeAreaTop, width: width, height: safeAreaTop)
                return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: true)
            }
        }
        let height = max(menuBarHeight, 24)
        let rect = CGRect(x: frame.midX - fallbackTabWidth / 2, y: frame.maxY - height, width: fallbackTabWidth, height: height)
        return NotchGeometry(screenFrame: frame, notchRect: rect, hasNotch: false)
    }

    /// The shelf hangs from the top edge of the screen, centered under the notch,
    /// and never sticks out past the screen's sides.
    func shelfFrame(width: CGFloat, height: CGFloat) -> CGRect {
        let w = min(max(width, notchRect.width + 40), screenFrame.width)
        var x = notchRect.midX - w / 2
        x = min(max(x, screenFrame.minX), screenFrame.maxX - w)
        return CGRect(x: x, y: screenFrame.maxY - height, width: w, height: height)
    }

    /// The built-in notched display if there is one, otherwise the main screen.
    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }
}

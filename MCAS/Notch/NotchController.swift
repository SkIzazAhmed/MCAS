// NotchController.swift
//
// What: opens and closes the notch shelf (F3).
//
// Opening:
//   • hover over the notch for 150 ms   → opens in "hover" mode
//   • click the notch, or press ⌥⌘V     → opens in "pinned" mode (stays until dismissed)
// Closing:
//   • hover mode: the mouse leaves the shelf for 300 ms
//   • any mode: Esc, clicking outside, picking an item, or ⌥⌘V again
//
// The shelf never takes keyboard focus, so the app you were typing in keeps its
// cursor and auto-paste (⌘V) lands there. Esc and outside clicks are noticed
// with event monitors instead.
//
// Why the delays: passing the cursor across the top of the screen shouldn't pop
// the shelf open, and a small wobble outside shouldn't snap it shut.

import AppKit
import SwiftUI

@MainActor
final class NotchController {
    enum OpenMode { case hover, pinned }

    static let shelfWidth: CGFloat = 480
    /// Height of the shelf below the notch (the window also covers the notch itself).
    static let shelfContentHeight: CGFloat = 560
    static let hoverOpenDelay: TimeInterval = 0.15
    static let leaveCloseDelay: TimeInterval = 0.3

    private let model: AppModel
    private var geometry: NotchGeometry
    private let trigger: NotchPanel
    private let shelf: NotchPanel
    private let hoverView = HoverTrackingView()

    private var openMode: OpenMode?
    private var pendingOpen: DispatchWorkItem?
    private var leaveTimer: Timer?
    private var outsideSince: Date?
    private var screenObserver: NSObjectProtocol?
    private var eventMonitors: [Any] = []

    var isOpen: Bool { openMode != nil }

    init(model: AppModel) {
        self.model = model
        geometry = NotchGeometry.preferredScreen.map(NotchGeometry.forScreen)
            ?? NotchGeometry.compute(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                     safeAreaTop: 0, leftAreaWidth: 0, rightAreaWidth: 0, menuBarHeight: 24)
        trigger = NotchPanel(contentRect: geometry.notchRect)
        shelf = NotchPanel(contentRect: .zero)

        trigger.contentView = hoverView
        hoverView.onHoverChange = { [weak self] inside in self?.hoverChanged(inside) }
        hoverView.onClick = { [weak self] in self?.open(.pinned) }
        shelf.onEscape = { [weak self] in self?.close() }
        shelf.onResignKey = { [weak self] in self?.close() }
    }

    func start() {
        layout()
        trigger.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close()
                self?.layout()
            }
        }
        Log.notch.info("Notch ready: hasNotch=\(self.geometry.hasNotch), rect=\(String(describing: self.geometry.notchRect), privacy: .public)")
    }

    /// Recomputes positions (at start and whenever displays change).
    func layout() {
        if let screen = NotchGeometry.preferredScreen {
            geometry = .forScreen(screen)
        }
        trigger.setFrame(geometry.notchRect, display: true)
        hoverView.isOverRealNotch = geometry.hasNotch

        let frame = geometry.shelfFrame(width: Self.shelfWidth, height: geometry.notchRect.height + Self.shelfContentHeight)
        shelf.setFrame(frame, display: false)

        let root = NotchShelfView(model: model, notchHeight: geometry.notchRect.height) { [weak self] in
            self?.close()
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [] // the window decides the size, not SwiftUI
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        shelf.contentView = host
    }

    // MARK: - Open / close

    func toggleFromHotKey() {
        if openMode == .pinned { close() } else { open(.pinned) }
    }

    func open(_ mode: OpenMode) {
        pendingOpen?.cancel()
        pendingOpen = nil

        if let current = openMode {
            // Already open by hover, now clicked or hotkey: upgrade to pinned.
            if mode == .pinned, current == .hover {
                openMode = .pinned
                stopLeaveTimer()
            }
            return
        }

        openMode = mode
        model.reload()
        model.refreshAccessibilityStatus()

        shelf.alphaValue = 0
        shelf.orderFrontRegardless()
        if mode == .hover { startLeaveTimer() }
        startEventMonitors()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            shelf.animator().alphaValue = 1
        }
        Log.notch.debug("Shelf opened (\(mode == .hover ? "hover" : "pinned", privacy: .public))")
    }

    func close() {
        pendingOpen?.cancel()
        pendingOpen = nil
        guard isOpen else { return }
        openMode = nil
        stopLeaveTimer()
        stopEventMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            shelf.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return } // reopened during the fade
                self.shelf.orderOut(nil)
            }
        })
    }

    // MARK: - Esc and clicks outside

    private static let escapeKeyCode: UInt16 = 53

    private func startEventMonitors() {
        stopEventMonitors()
        // Clicks in other apps. Needs no permission.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeIfClickOutside() }
        }) {
            eventMonitors.append(monitor)
        }
        // Esc while another app is in front. macOS only delivers this once
        // MCAS has the Accessibility permission (the same one auto-paste uses).
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let isEscape = event.keyCode == Self.escapeKeyCode
            MainActor.assumeIsolated { if isEscape { self?.close() } }
        }) {
            eventMonitors.append(monitor)
        }
        // Esc while the shelf itself has focus (later: the search field).
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == Self.escapeKeyCode else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func stopEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func closeIfClickOutside() {
        let point = NSEvent.mouseLocation
        let inside = shelf.frame.contains(point) || geometry.notchRect.contains(point)
        if !inside { close() }
    }

    // MARK: - Hover

    private func hoverChanged(_ inside: Bool) {
        if inside {
            guard !isOpen, pendingOpen == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.pendingOpen = nil
                    self?.open(.hover)
                }
            }
            pendingOpen = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverOpenDelay, execute: work)
        } else {
            pendingOpen?.cancel()
            pendingOpen = nil
        }
    }

    /// While open by hover, check 10× a second whether the mouse is still near.
    /// (Only runs while the shelf is open, so it costs nothing the rest of the time.)
    private func startLeaveTimer() {
        outsideSince = nil
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        leaveTimer = timer
    }

    private func stopLeaveTimer() {
        leaveTimer?.invalidate()
        leaveTimer = nil
        outsideSince = nil
    }

    private func checkMouse() {
        guard openMode == .hover else { return }
        let point = NSEvent.mouseLocation
        let inside = shelf.frame.contains(point) || geometry.notchRect.insetBy(dx: -6, dy: -6).contains(point)
        if inside {
            outsideSince = nil
        } else if let since = outsideSince {
            if Date.now.timeIntervalSince(since) >= Self.leaveCloseDelay { close() }
        } else {
            outsideSince = .now
        }
    }
}

/// The shelf's look in the notch: a black shape that grows out of the notch,
/// with the history inside.
struct NotchShelfView: View {
    let model: AppModel
    let notchHeight: CGFloat
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            ShelfView(model: model, listHeight: 420, close: close)
        }
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22, style: .continuous)
                .fill(Color.black)
        )
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

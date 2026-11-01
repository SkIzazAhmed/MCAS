// MCASApp.swift
//
// What: where the app starts.
//   • AppDelegate sets up the notch shelf and the ⌥⌘V hotkey.
//   • The menu bar icon opens the same shelf as a small panel: the fallback for
//     external displays and Macs without a notch.
// Why:  MCAS has no Dock icon or main window (LSUIElement = YES in build settings).

import SwiftUI

@main
struct MCASApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            ShelfView(model: model, listHeight: 440) {
                // Close the panel and hand focus back to the app you were in,
                // so the paste lands there.
                NSApplication.shared.keyWindow?.close()
                NSApplication.shared.deactivate()
            }
            .frame(width: 400)
        } label: {
            Image(systemName: model.isPaused ? "pause.circle" : "list.clipboard")
        }
        // .window = a real panel that can scroll (the default .menu style can't hold a list).
        .menuBarExtraStyle(.window)
    }
}

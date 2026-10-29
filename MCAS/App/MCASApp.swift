// MCASApp.swift
//
// What: where the app starts. Creates the menu bar icon and its menu.
// Why:  MCAS has no Dock icon or main window (LSUIElement = YES in build
//       settings). Until the notch shelf exists, the menu bar menu is how you
//       see that capture works: copy something, click the icon, it's there.

import SwiftUI

@main
struct MCASApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu(model: model)
        } label: {
            Image(systemName: model.isPaused ? "pause.circle" : "list.clipboard")
        }
    }
}

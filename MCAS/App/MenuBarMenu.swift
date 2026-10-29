// MenuBarMenu.swift
//
// What: the menu that drops down from the MCAS menu bar icon.
//   • the last 10 copies, grouped by day (click one to copy it again)
//   • Pause capture
//   • Debug tools (debug builds only)
//   • Quit
// Why:  a temporary window into the history while we build the notch shelf.
//       It stays afterwards as the fallback for Macs without a notch.

import SwiftUI

struct MenuBarMenu: View {
    let model: AppModel

    var body: some View {
        if let problem = model.startupProblem {
            Text("⚠️ \(problem)")
            Divider()
        }

        Text("\(model.totalCount) items saved")

        Divider()

        if model.recentItems.isEmpty {
            Text("Copy something to get started")
        } else {
            ForEach(DayGrouping.group(Array(model.recentItems.prefix(10)))) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        Button {
                            model.copyToClipboard(item)
                        } label: {
                            Label(item.displayTitle, systemImage: item.symbolName)
                        }
                    }
                }
            }
        }

        Divider()

        Toggle("Pause capture", isOn: Binding(
            get: { model.isPaused },
            set: { model.setPaused($0) }
        ))

        Button("Clear history") {
            model.clearHistory()
        }

        #if DEBUG
        Menu("Debug") {
            Button("Simulate a copy") { model.debugSimulateCopy() }
            Button("Open data folder") { model.debugOpenDataFolder() }
        }
        #endif

        Divider()

        Button("Quit MCAS") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

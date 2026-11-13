// ShelfView.swift
//
// What: the history panel: search box, Pinned items, day groups (Today /
//       Yesterday / …), a selection bar for "Paste together", and a footer.
// Where: shown in the notch (NotchShelfView) and from the menu bar icon.
//
//   Click a row          → pastes it into the app you were using
//   Shift-click          → pastes as plain text (no fonts, colors or links)
//   ⌘-click rows         → selects several (numbered in the order you pick)
//   Right-click          → Pin, Paste as Plain Text, Copy Without Pasting, Delete
//   Type in Search       → filters all history; Return pastes the first match

import SwiftUI

/// One titled group of rows in the shelf.
struct ShelfSection: Identifiable {
    let id: String
    let title: String
    let items: [ClipItem]
}

struct ShelfView: View {
    let model: AppModel
    var listHeight: CGFloat = 440
    /// Closes whatever window the shelf is in (notch panel or menu bar panel).
    let close: () -> Void

    @State private var selection = Selection()
    @State private var query = ""
    @State private var results: [ClipItem] = []
    @AppStorage("pasteSeparator") private var separator: PasteSeparator = .newline

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The sections currently on screen.
    private var sections: [ShelfSection] {
        if isSearching {
            guard !results.isEmpty else { return [] }
            let title = results.count == 1 ? "1 match" : "\(results.count) matches"
            return [ShelfSection(id: "results", title: title, items: results)]
        }
        var list: [ShelfSection] = []
        if !model.pinnedItems.isEmpty {
            list.append(ShelfSection(id: "pinned", title: "Pinned", items: model.pinnedItems))
        }
        list += DayGrouping.group(model.recentItems).map {
            ShelfSection(id: $0.id.description, title: $0.title, items: $0.items)
        }
        return list
    }

    /// Every item shown, in order (used to look up selected items).
    private var allListed: [ClipItem] {
        sections.flatMap(\.items)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            if let problem = model.startupProblem {
                banner(problem, systemImage: "exclamationmark.triangle")
            }
            if model.needsAccessibility {
                accessibilityBanner
            }
            if sections.isEmpty {
                emptyState
            } else {
                history
            }
            Divider()
            if selection.isEmpty { footer } else { selectionBar }
        }
        .onChange(of: query) { refreshResults() }
        .onChange(of: model.recentItems) { refreshResults() }
        .onChange(of: model.pinnedItems) { refreshResults() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            Text("MCAS").font(.headline)
            Spacer()
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var countText: String {
        let total = model.totalCount
        return total == 1 ? "1 item" : "\(total) items"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .onSubmit {
                    if let first = results.first { pick(first, plainText: false) }
                }
            if isSearching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised")
            Text("Your item is on the clipboard: press ⌘V. To paste automatically, allow MCAS in Accessibility.")
            Spacer(minLength: 0)
            Button("Open Settings") { model.openAccessibilitySettings() }
        }
        .font(.caption)
        .padding(10)
        .background(Color.orange.opacity(0.15))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: isSearching ? "magnifyingglass" : "list.clipboard").font(.title)
            Text(isSearching ? "No matches for \"\(query)\"" : "Copy something to get started")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: listHeight)
    }

    private var history: some View {
        ScrollView {
            // Lazy: only rows on screen are drawn, so hundreds of items stay fast.
            LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            row(for: item)
                        }
                    } header: {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial)
                    }
                }
            }
            .padding(6)
        }
        .frame(height: listHeight)
    }

    private func row(for item: ClipItem) -> some View {
        ClipRowView(item: item, selectionNumber: item.id.flatMap(selection.position(of:))) {
            clicked(item)
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
            Button("Paste as Plain Text") { pick(item, plainText: true) }
            Button("Copy Without Pasting") {
                model.copyToClipboard(item)
                close()
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(item) }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Pause", isOn: Binding(get: { model.isPaused }, set: { model.setPaused($0) }))
            Toggle("Screenshots", isOn: Binding(get: { model.savesScreenshots }, set: { model.setSavesScreenshots($0) }))
            Spacer()
            Text("⌘-click: select · ⇧-click: plain text")
                .foregroundStyle(.secondary)
            Menu {
                Button("Settings…") {
                    close()
                    model.openSettings()
                }
                Button("Clear History (keeps pinned)") { model.clearHistory() }
                #if DEBUG
                Divider()
                Button("Simulate a copy") { model.debugSimulateCopy() }
                Button("Open data folder") { model.debugOpenDataFolder() }
                #endif
                Divider()
                Button("Quit MCAS") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selection.count) selected")
                .font(.caption.weight(.semibold))
            Picker("Join", selection: $separator) {
                ForEach(PasteSeparator.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("Cancel") { selection.clear() }
            Button("Paste together") { pasteSelection() }
                .keyboardShortcut(.defaultAction)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func refreshResults() {
        results = isSearching ? model.search(query) : []
    }

    private func clicked(_ item: ClipItem) {
        guard let id = item.id else { return }
        let flags = NSEvent.modifierFlags
        // ⌘-click, or any click while a selection exists, adds/removes from the selection.
        if flags.contains(.command) || !selection.isEmpty {
            selection.toggle(id)
            return
        }
        pick(item, plainText: flags.contains(.shift))
    }

    private func pick(_ item: ClipItem, plainText: Bool) {
        close()
        if plainText {
            model.pastePlainText(item)
        } else {
            model.paste(item)
        }
        query = ""
    }

    private func pasteSelection() {
        let items = selection.items(from: allListed)
        selection.clear()
        close()
        model.pasteTogether(items, separator: separator)
    }
}

/// One history row: icon or thumbnail, the text, and where/when it was copied.
struct ClipRowView: View {
    let item: ClipItem
    /// 1, 2, 3… when selected for "Paste together".
    var selectionNumber: Int?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                        }
                        if item.expiresAt != nil {
                            Image(systemName: "timer")
                                .help("One-time code: deleted automatically after 60 seconds")
                        }
                        Text(subtitle)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let selectionNumber {
                    Text("\(selectionNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(String(item.previewText.prefix(300)))
    }

    private var backgroundColor: Color {
        if selectionNumber != nil { return Color.accentColor.opacity(0.28) }
        return isHovered ? Color.accentColor.opacity(0.18) : Color.clear
    }

    @ViewBuilder
    private var icon: some View {
        if let data = item.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        let time = item.createdAt.formatted(date: .omitted, time: .shortened)
        if let app = item.sourceAppName { return "\(app) · \(time)" }
        return time
    }
}

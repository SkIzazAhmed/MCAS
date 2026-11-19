// ShelfView.swift
//
// What: the history panel: search box, Pinned items, day groups (Today /
//       Yesterday / …), a selection bar for "Paste together" / "Paste as queue",
//       and a footer.
// Where: shown in the notch (NotchShelfView) and from the menu bar icon.
//
// Mouse:
//   Click a row          → pastes it into the app you were using
//   Shift-click          → pastes as plain text (no fonts, colors or links)
//   ⌘-click rows         → selects several (numbered in the order you pick)
//   Right-click          → Pin, Paste as Plain Text, Copy, Delete + smart actions
// Keyboard (after ⌥⌘V, the cursor is already in the search box):
//   type                 → filters all history
//   ↑ / ↓                → moves the highlight
//   Return / ⇧Return     → pastes the highlighted item / as plain text
//   ⌘1 … ⌘9              → pastes the 1st … 9th item
//   Esc                  → closes

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
    /// Index (into `allListed`) of the row the arrow keys point at.
    @State private var highlighted: Int?
    @FocusState private var searchFocused: Bool
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

    /// Every item shown, top to bottom (arrow keys, ⌘1–9 and selections use this).
    private var allListed: [ClipItem] {
        sections.flatMap(\.items)
    }

    private var highlightedItem: ClipItem? {
        guard let highlighted, allListed.indices.contains(highlighted) else { return nil }
        return allListed[highlighted]
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
            if let queue = model.queue {
                queueBanner(queue)
            }
            if sections.isEmpty {
                emptyState
            } else {
                history
            }
            Divider()
            if selection.isEmpty { footer } else { selectionBar }
        }
        .onChange(of: query) {
            refreshResults()
            highlighted = isSearching ? 0 : nil
        }
        .onChange(of: model.recentItems) { refreshResults() }
        .onChange(of: model.pinnedItems) { refreshResults() }
        .onChange(of: model.searchFocusRequest) {
            searchFocused = true
            highlighted = allListed.isEmpty ? nil : 0
        }
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
                .focused($searchFocused)
                .onSubmit {
                    if let item = highlightedItem ?? allListed.first { pick(item, plainText: false) }
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(keys: [.return]) { press in
                    // ⇧Return = plain text. Plain Return falls through to onSubmit.
                    guard press.modifiers.contains(.shift), let item = highlightedItem ?? allListed.first else { return .ignored }
                    pick(item, plainText: true)
                    return .handled
                }
                .onKeyPress(characters: .decimalDigits) { press in
                    // ⌘1 … ⌘9 paste the first nine items. Digits alone are typed as usual.
                    guard press.modifiers.contains(.command),
                          let digit = Int(press.characters), (1...9).contains(digit),
                          allListed.indices.contains(digit - 1)
                    else { return .ignored }
                    pick(allListed[digit - 1], plainText: false)
                    return .handled
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

    private func queueBanner(_ queue: PasteQueue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "list.number")
            VStack(alignment: .leading, spacing: 1) {
                Text("Paste queue · \(queue.progressLabel)").fontWeight(.semibold)
                Text("Press ⌘V in any app to paste the next item.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Stop") { model.stopQueue() }
        }
        .font(.caption)
        .padding(10)
        .background(Color.accentColor.opacity(0.15))
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
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy: only rows on screen are drawn, so hundreds of items stay fast.
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                row(for: item)
                                    .id(item.id ?? -1)
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
            .onChange(of: highlighted) {
                if let id = highlightedItem?.id {
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .frame(height: listHeight)
    }

    private func row(for item: ClipItem) -> some View {
        let smart = item.smartType
        return ClipRowView(
            item: item,
            smartType: smart,
            selectionNumber: item.id.flatMap(selection.position(of:)),
            isHighlighted: item.id != nil && item.id == highlightedItem?.id
        ) {
            clicked(item)
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
            Button("Paste as Plain Text") { pick(item, plainText: true) }
            Button("Copy Without Pasting") {
                model.copyToClipboard(item)
                close()
            }
            smartActions(for: smart)
            Divider()
            Button("Delete", role: .destructive) { model.delete(item) }
        }
    }

    /// Extra right-click actions for links, colors and emails.
    @ViewBuilder
    private func smartActions(for smart: SmartType) -> some View {
        switch smart {
        case .link(let url):
            Divider()
            Button("Open Link") {
                close()
                model.open(url)
            }
        case .color:
            Divider()
            if let hex = smart.hexString {
                Button("Copy as HEX (\(hex))") { model.copyText(hex); close() }
            }
            if let rgb = smart.rgbString {
                Button("Copy as RGB (\(rgb))") { model.copyText(rgb); close() }
            }
        case .email(let address):
            Divider()
            Button("New Email") {
                close()
                model.newEmail(to: address)
            }
        case .code, .none:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Pause", isOn: Binding(get: { model.isPaused }, set: { model.setPaused($0) }))
            Toggle("Screenshots", isOn: Binding(get: { model.savesScreenshots }, set: { model.setSavesScreenshots($0) }))
            Spacer()
            Text("↑↓ ↩ · ⌘1–9 · ⌘-click to select")
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
        HStack(spacing: 8) {
            Text("\(selection.count) selected")
                .font(.caption.weight(.semibold))
            Picker("Join", selection: $separator) {
                ForEach(PasteSeparator.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button("Cancel") { selection.clear() }
            Button("Paste as queue") { queueSelection() }
                .help("Each ⌘V you press pastes the next item, in the order you picked them")
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

    private func moveHighlight(by step: Int) {
        let count = allListed.count
        guard count > 0 else { return }
        let next = (highlighted ?? -1) + step
        highlighted = min(max(next, 0), count - 1)
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
        highlighted = nil
    }

    private func pasteSelection() {
        let items = selection.items(from: allListed)
        selection.clear()
        close()
        model.pasteTogether(items, separator: separator)
    }

    private func queueSelection() {
        let items = selection.items(from: allListed)
        selection.clear()
        close()
        model.startQueue(items)
    }
}

/// One history row: icon, thumbnail or color swatch, the text, and where/when
/// it was copied.
struct ClipRowView: View {
    let item: ClipItem
    var smartType: SmartType = .none
    /// 1, 2, 3… when selected for "Paste together" / "Paste as queue".
    var selectionNumber: Int?
    /// Chosen with the arrow keys.
    var isHighlighted = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(smartType == .code ? .system(.body, design: .monospaced) : .body)
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
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: isHighlighted ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(String(item.previewText.prefix(300)))
    }

    private var backgroundColor: Color {
        if selectionNumber != nil { return Color.accentColor.opacity(0.28) }
        if isHighlighted { return Color.accentColor.opacity(0.22) }
        return isHovered ? Color.accentColor.opacity(0.18) : Color.clear
    }

    @ViewBuilder
    private var icon: some View {
        if case let .color(r, g, b) = smartType {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.2)))
                .padding(3)
        } else if let data = item.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    private var symbolName: String {
        switch smartType {
        case .email: return "envelope"
        case .code: return "chevron.left.forwardslash.chevron.right"
        default: return item.symbolName
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if case .link(let url) = smartType, let host = url.host() {
            parts.append(host.replacingOccurrences(of: "www.", with: ""))
        }
        if let app = item.sourceAppName { parts.append(app) }
        parts.append(item.createdAt.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

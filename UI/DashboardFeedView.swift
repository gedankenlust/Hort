import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DashboardFeedView: View {
    let selection: SidebarSelection
    @Binding var selectedMemories: Set<UUID>

    @StateObject private var engine = MemoryEngine.shared
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var exportNote: String?
    @State private var memories: [MemoryObject] = []
    /// Anchor for ⇧-click range selection (the last plain/⌘ click).
    @State private var selectionAnchor: UUID?
    /// Debounces the (possibly Ollama-backed) search while typing.
    @State private var searchTask: Task<Void, Never>?

    // Flexible columns: as many as fit at the minimum width, each stretching to
    // fill the remaining space so cards expand/contract with the column width.
    private let columns = [GridItem(.adaptive(minimum: Theme.Layout.cardMinWidth, maximum: .infinity),
                                    spacing: Theme.Layout.gridSpacing)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(isSearchActive ? LocalizedStringKey("dashboard.search") : LocalizedStringKey(title))
                    .font(Theme.Fonts.label(20, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text("\(memories.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.elevated)
                    .clipShape(Capsule())

                if selectedMemories.count >= 1 {
                    Button(action: { selectedMemories.removeAll() }) {
                        HStack(spacing: 5) {
                            Text("\(selectedMemories.count) " + L("dashboard.selected"))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(Theme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Colors.accentSoft)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("dashboard.clear_selection_help")
                }

                Spacer()

                if let note = exportNote {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                if settings.semanticEnabled {
                    iconButton("sparkles", help: "ask.help") { app.showingAsk = true }
                }
                iconButton("square.and.arrow.up", help: "dashboard.export_help",
                           disabled: memories.isEmpty, action: exportCurrent)
                searchControl
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Theme.Colors.background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Colors.border).frame(height: 1)
            }

            // Content Grid or Onboarding
            if engine.recentMemories.isEmpty {
                OnboardingView()
            } else {
                ScrollView {
                    if memories.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading,
                                  spacing: Theme.Layout.gridSpacing) {
                            ForEach(memories) { memory in
                                card(for: memory)
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .background(Theme.Colors.background)
        .onChange(of: app.focusSearchToken) { _, _ in
            isSearching = true
            searchFocused = true
        }
        .onChange(of: app.exportToken) { _, _ in
            exportCurrent()
        }
        .onChange(of: app.selectAllToken) { _, _ in
            selectAllVisible()
        }
        .background(selectAllShortcut)
        .onAppear {
            refreshMemories()
        }
        .onChange(of: engine.dataVersion) { _, _ in
            refreshMemories()
        }
        .onChange(of: selection) { _, _ in
            refreshMemories()
        }
        .onChange(of: isSearching) { _, _ in
            refreshMemories()
        }
        .onChange(of: searchText) { _, _ in
            refreshMemories()
        }
    }

    private func iconButton(_ systemName: String, help: String,
                            disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundColor(disabled ? Theme.Colors.textTertiary.opacity(0.5)
                                          : Theme.Colors.textSecondary)
                .frame(width: 30, height: 30)
                .background(Theme.Colors.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private var isSearchActive: Bool {
        isSearching && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Subviews

    private func card(for memory: MemoryObject) -> some View {
        MemoryCardView(memory: memory,
                       isSelected: selectedMemories.contains(memory.id),
                       onCopy: { copyToClipboard(memory) },
                       onFavorite: { engine.update(id: memory.id) { $0.isFavorite.toggle() } },
                       onArchive: {
                           engine.update(id: memory.id) { $0.isArchived.toggle() }
                           selectedMemories.remove(memory.id)
                       },
                       onDelete: {
                           engine.delete(memory)
                           selectedMemories.remove(memory.id)
                       })
            .onTapGesture { handleSelection(of: memory) }
            .draggable(dragPayload(for: memory)) {
                dragPreview(for: memory)
            }
            .help("dashboard.multiselect_hint")
    }

    /// Drag payload: all selected ids (newline-separated) when this card is part
    /// of a multi-selection, otherwise just this card — so dragging a selected
    /// card onto a board/section moves the whole selection.
    private func dragPayload(for memory: MemoryObject) -> String {
        if selectedMemories.contains(memory.id), selectedMemories.count > 1 {
            return selectedMemories.map(\.uuidString).joined(separator: "\n")
        }
        return memory.id.uuidString
    }

    /// Copies a card's content to the clipboard without re-capturing it.
    private func copyToClipboard(_ memory: MemoryObject) {
        guard let content = memory.content, !content.isEmpty else { return }
        ClipboardMonitor.shared.writeWithoutCapture(content)
    }

    /// Selects every currently shown card.
    private func selectAllVisible() {
        selectedMemories = Set(memories.map(\.id))
        selectionAnchor = memories.first?.id
    }

    /// A zero-size, invisible button that binds ⌘A inside the view hierarchy.
    /// More reliable than a menu command, which needs a first responder and can
    /// swallow the first press when no view is focused.
    private var selectAllShortcut: some View {
        Button(action: selectAllVisible) { }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(app.inspectorTextFocused)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    /// Click selection: plain = single, ⌘ = toggle, ⇧ = range from the anchor
    /// (last plain/⌘ click) through this card in the current feed order.
    private func handleSelection(of memory: MemoryObject) {
        // Clicking a card takes focus away from any inspector text field, so the
        // feed re-claims ⌘A (select all cards) instead of leaving it stuck.
        NSApp.keyWindow?.makeFirstResponder(nil)
        app.inspectorTextFocused = false

        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor,
           let a = memories.firstIndex(where: { $0.id == anchor }),
           let b = memories.firstIndex(where: { $0.id == memory.id }) {
            let lo = min(a, b), hi = max(a, b)
            selectedMemories = Set(memories[lo...hi].map(\.id))
            // keep the anchor so the range can be re-adjusted
        } else if flags.contains(.command) {
            if selectedMemories.contains(memory.id) {
                selectedMemories.remove(memory.id)
            } else {
                selectedMemories.insert(memory.id)
            }
            selectionAnchor = memory.id
        } else {
            selectedMemories = [memory.id]
            selectionAnchor = memory.id
        }
    }

    /// Reveals the search field, or runs the active query, on the magnifier.
    @ViewBuilder
    private var searchControl: some View {
        if isSearching {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textTertiary)
                TextField(LocalizedStringKey("dashboard.search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 200)
                    .focused($searchFocused)
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.Colors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1)
            )
        } else {
            iconButton("magnifyingglass", help: "dashboard.search") {
                isSearching = true
                searchFocused = true
            }
        }
    }

    private func closeSearch() {
        searchText = ""
        isSearching = false
        searchFocused = false
        refreshMemories()
    }

    /// Exports the currently shown memories (respecting section/tag/search
    /// filtering) as an Obsidian-friendly ZIP via a save panel.
    private func exportCurrent() {
        let items = memories
        guard !items.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        panel.nameFieldStringValue = "Hort-Export-\(formatter.string(from: Date())).zip"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportEngine.shared.exportBundle(items, to: url)
            exportNote = String(format: L("dashboard.exported"), "\(items.count)", url.lastPathComponent)
        } catch {
            exportNote = L("dashboard.export_failed")
            print("Export failed: \(error)")
        }
    }

    /// The memories shown for the current section, or hybrid search results when
    /// a query is active. Search is async (it may embed the query), so results
    /// are applied on the main actor and ignored if the query changed meanwhile.
    private func refreshMemories() {
        searchTask?.cancel()
        if isSearchActive {
            let query = searchText
            searchTask = Task {
                // Debounce: avoid embedding the query (an Ollama call) on every
                // keystroke; only search once typing settles.
                try? await Task.sleep(nanoseconds: 280_000_000)
                if Task.isCancelled { return }
                let results = await engine.search(query)
                await MainActor.run {
                    guard !Task.isCancelled, isSearchActive, searchText == query else { return }
                    memories = results
                }
            }
        } else {
            memories = engine.fetchMemories(for: selection)
        }
    }

    private var title: String {
        switch selection {
        case .inbox: return "sidebar.inbox"
        case .all: return "sidebar.all"
        case .favorites: return "sidebar.favorites"
        case .archive: return "sidebar.archive"
        case .board(let name): return name
        case .folder(let board, let folder): return "\(board) / \(folder)"
        case .tag(let name): return "#\(name)"
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: emptyIcon)
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 80, height: 80)
                .background(Theme.Colors.accentSoft)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                )
            
            VStack(spacing: 8) {
                Text(emptyText)
                    .font(Theme.Fonts.label(16, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(emptySubtext)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var emptyIcon: String {
        if isSearchActive { return "magnifyingglass" }
        switch selection {
        case .inbox: return "tray"
        case .all: return "square.stack"
        case .favorites: return "star"
        case .archive: return "archivebox"
        case .board: return "square.grid.2x2"
        case .folder: return "folder"
        case .tag: return "tag"
        }
    }

    private var emptyText: String {
        if isSearchActive { return L("dashboard.empty_search") }
        switch selection {
        case .inbox: return L("dashboard.empty_inbox")
        case .all: return L("dashboard.empty_all")
        case .favorites: return L("dashboard.empty_favorites")
        case .archive: return L("dashboard.empty_archive")
        case .board(let name): return String(format: L("dashboard.empty_board"), name)
        case .folder(_, let folder): return String(format: L("dashboard.empty_folder"), folder)
        case .tag(let name): return String(format: L("dashboard.empty_tag"), name)
        }
    }

    private var emptySubtext: String {
        if isSearchActive { return L("dashboard.empty_search_desc") }
        switch selection {
        case .inbox: return L("dashboard.empty_inbox_desc")
        case .all: return L("dashboard.empty_all_desc")
        case .favorites: return L("dashboard.empty_favorites_desc")
        case .archive: return L("dashboard.empty_archive_desc")
        case .board(let name): return String(format: L("dashboard.empty_board_desc"), name)
        case .folder(_, let folder): return String(format: L("dashboard.empty_folder_desc"), folder)
        case .tag(let name): return String(format: L("dashboard.empty_tag_desc"), name)
        }
    }

    @ViewBuilder
    private func dragPreview(for memory: MemoryObject) -> some View {
        if selectedMemories.contains(memory.id), selectedMemories.count > 1 {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Colors.accent)
                Text("\(selectedMemories.count) " + L("dashboard.selected"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.Colors.elevatedHi)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.Colors.accent, lineWidth: 1))
        } else {
            singleDragPreview(for: memory)
        }
    }

    @ViewBuilder
    private func singleDragPreview(for memory: MemoryObject) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iconName(for: memory.type))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 18, height: 18)
                .background(Theme.Colors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            
            Text(memory.type.rawValue.uppercased())
                .font(Theme.Fonts.label(9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(Theme.Colors.textSecondary)
            
            if let content = memory.content, !content.isEmpty {
                let display = memory.type == .image || memory.type == .screenshot ? L("dashboard.image_asset") : content
                Text(display.prefix(20))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Colors.elevatedHi)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.Colors.accent, lineWidth: 1)
        )
    }

    private func iconName(for type: MemoryType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .screenshot: return "camera.viewfinder"
        case .file: return "doc"
        }
    }
}

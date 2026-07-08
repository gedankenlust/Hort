import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum FeedViewMode: String {
    case grid, list
}

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
    @State private var searchTask: Task<Void, Never>?
    @AppStorage("feedViewMode") private var viewMode: FeedViewMode = .grid
    @State private var newCardIDs: Set<UUID> = []
    @State private var showArchiveOldDialog = false

    // Flexible columns: as many as fit at the minimum width, each stretching to
    // fill the remaining space so cards expand/contract with the column width.
    private let columns = [GridItem(.adaptive(minimum: HortSizing.cardMinWidth, maximum: .infinity),
                                    spacing: HortSizing.cardSpacing)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: HortSpacing.md) {
                Text(isSearchActive ? LocalizedStringKey("dashboard.search") : LocalizedStringKey(title))
                    .font(HortTypography.label(size: HortTypography.Size.title))
                    .foregroundColor(HortColors.textPrimary)
                Text("\(memories.count)")
                    .font(HortTypography.label(size: 12))
                    .monospacedDigit()
                    .foregroundColor(HortColors.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(HortColors.elevated)
                    .clipShape(Capsule())

                if selectedMemories.count >= 1 {
                    Button(action: { selectedMemories.removeAll() }) {
                        HStack(spacing: HortSpacing.xs) {
                            Text("\(selectedMemories.count) " + L("dashboard.selected"))
                                .font(HortTypography.label(size: 11))
                                .monospacedDigit()
                            Image(systemName: "xmark").font(HortTypography.label(size: 9))
                        }
                        .foregroundColor(HortColors.accent)
                        .padding(.horizontal, HortSpacing.sm)
                        .padding(.vertical, 3)
                        .background(HortColors.accentSoft)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("dashboard.clear_selection_help")
                }

                Spacer()

                if let note = exportNote {
                    Text(note)
                        .font(HortTypography.primary(size: HortTypography.Size.bodySmall))
                        .foregroundColor(HortColors.textTertiary)
                        .lineLimit(1)
                }
                if settings.semanticEnabled {
                    HortIconButton(icon: "sparkles", help: "ask.help") { app.showingAsk = true }
                }
                if selection == .inbox, memories.count > 10 {
                    HortIconButton(icon: "archivebox.circle", help: "dashboard.archive_old") {
                        showArchiveOldDialog = true
                    }
                    .confirmationDialog(L("dashboard.archive_old"),
                                       isPresented: $showArchiveOldDialog,
                                       titleVisibility: .visible) {
                        Button(L("dashboard.archive_week")) { archiveOlderThan(days: 7) }
                        Button(L("dashboard.archive_month")) { archiveOlderThan(days: 30) }
                        Button(L("common.cancel"), role: .cancel) {}
                    }
                }
                HortIconButton(
                    icon: viewMode == .grid ? "list.bullet" : "square.grid.2x2",
                    help: viewMode == .grid ? "dashboard.list_view" : "dashboard.grid_view"
                ) {
                    withAnimation(.easeOut(duration: HortAnimation.fast)) {
                        viewMode = viewMode == .grid ? .list : .grid
                    }
                }
                HortIconButton(icon: "square.and.arrow.up",
                               help: "dashboard.export_help",
                               disabled: memories.isEmpty,
                               action: exportCurrent)
                searchControl
            }
            .padding(.horizontal, HortSpacing.xxl)
            .padding(.vertical, HortSpacing.lg)
            .background(HortColors.background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(HortColors.border).frame(height: 1)
            }

            // Content Grid or Onboarding
            if engine.recentMemories.isEmpty {
                OnboardingView()
            } else {
                ScrollView {
                    if isSearchActive && memories.isEmpty {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(HortColors.accent)
                            .frame(maxWidth: .infinity, minHeight: 420)
                    } else if memories.isEmpty {
                        emptyState
                    } else if viewMode == .grid {
                        LazyVGrid(columns: columns, alignment: .leading,
                                  spacing: HortSizing.cardSpacing) {
                            ForEach(memories) { memory in
                                card(for: memory)
                            }
                        }
                        .padding(HortSpacing.xxl)
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(memories) { memory in
                                listRow(for: memory)
                            }
                        }
                        .padding(.vertical, HortSpacing.md)
                    }
                }
            }
        }
        .background(HortColors.background)
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
        .background(quickLookShortcut)
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

    private var isSearchActive: Bool {
        isSearching && !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Subviews

    private func card(for memory: MemoryObject) -> some View {
        MemoryCardView(memory: memory,
                       isSelected: selectedMemories.contains(memory.id),
                       boardColor: boardColor(for: memory),
                       onCopy: { copyToClipboard(memory) },
                       onFavorite: { engine.update(id: memory.id) { $0.isFavorite.toggle() } },
                       onArchive: {
                           engine.update(id: memory.id) { $0.isArchived.toggle() }
                           selectedMemories.remove(memory.id)
                       },
                       onDelete: {
                           engine.delete(memory)
                           selectedMemories.remove(memory.id)
                           app.stashForUndo([memory])
                       },
                       onTagClick: { tag in app.selection = .tag(tag) })
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                    .stroke(HortColors.accent, lineWidth: newCardIDs.contains(memory.id) ? 1.5 : 0)
                    .shadow(color: HortColors.accent.opacity(newCardIDs.contains(memory.id) ? 0.5 : 0), radius: 8)
                    .allowsHitTesting(false)
            )
            .onTapGesture(count: 2) { openQuickLook(memory) }
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
            HortTextField(
                placeholder: "dashboard.search_placeholder",
                text: $searchText,
                leadingIcon: "magnifyingglass",
                trailingView: AnyView(
                    Button(action: closeSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(HortTypography.primary(size: 13))
                            .foregroundColor(HortColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                ),
                focus: $searchFocused
            )
            .frame(width: 200)
        } else {
            HortIconButton(icon: "magnifyingglass", help: "dashboard.search") {
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
            let old = Set(memories.map(\.id))
            let fresh = engine.fetchMemories(for: selection)
            let arrived = Set(fresh.map(\.id)).subtracting(old)
            memories = fresh
            if !arrived.isEmpty, !old.isEmpty {
                newCardIDs.formUnion(arrived)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.6)) { newCardIDs.subtract(arrived) }
                }
            }
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
        HortEmptyState(
            icon: emptyIcon,
            title: LocalizedStringKey(emptyText),
            subtitle: LocalizedStringKey(emptySubtext),
            actionTitle: isSearchActive ? LocalizedStringKey("dashboard.clear_search") : nil,
            action: isSearchActive ? closeSearch : nil
        )
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
            HStack(spacing: HortSpacing.sm) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(HortTypography.label(size: 11))
                    .foregroundColor(HortColors.accent)
                Text("\(selectedMemories.count) " + L("dashboard.selected"))
                    .font(HortTypography.label(size: 11))
                    .foregroundColor(HortColors.textPrimary)
            }
            .padding(.horizontal, HortSpacing.sm)
            .padding(.vertical, HortSpacing.xs)
            .background(HortColors.elevatedHover)
            .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous)
                    .strokeBorder(HortColors.accent, lineWidth: 1)
            )
        } else {
            singleDragPreview(for: memory)
        }
    }

    @ViewBuilder
    private func singleDragPreview(for memory: MemoryObject) -> some View {
        HStack(spacing: HortSpacing.sm) {
            Image(systemName: iconName(for: memory.type))
                .font(HortTypography.label(size: 10))
                .foregroundColor(HortColors.accent)
                .frame(width: 18, height: 18)
                .background(HortColors.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(memory.type.rawValue.uppercased())
                .font(HortTypography.label(size: 9))
                .tracking(0.5)
                .foregroundColor(HortColors.textSecondary)

            if let content = memory.content, !content.isEmpty {
                let display = memory.type == .image || memory.type == .screenshot ? L("dashboard.image_asset") : content
                Text(display.prefix(20))
                    .font(HortTypography.primary(size: 11))
                    .foregroundColor(HortColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, HortSpacing.sm)
        .padding(.vertical, HortSpacing.xs)
        .background(HortColors.elevatedHover)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous)
                .strokeBorder(HortColors.accent, lineWidth: 1)
        )
    }

    // MARK: - Inbox triage

    private func archiveOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let old = memories.filter { $0.createdAt < cutoff }
        guard !old.isEmpty else { return }
        let ids = old.map(\.id)
        engine.update(ids: ids) { $0.isArchived = true }
    }

    // MARK: - List view

    private func listRow(for memory: MemoryObject) -> some View {
        let selected = selectedMemories.contains(memory.id)
        return HStack(spacing: HortSpacing.md) {
            Image(systemName: iconName(for: memory.type))
                .font(HortTypography.label(size: 11))
                .foregroundColor(listIconTint(memory.type))
                .frame(width: 22)
            if let color = boardColor(for: memory) {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(listTitle(memory))
                    .font(HortTypography.primary(weight: .medium))
                    .foregroundColor(HortColors.textPrimary)
                    .lineLimit(1)
                if !memory.tags.isEmpty {
                    Text(memory.tags.prefix(3).joined(separator: ", "))
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .foregroundColor(HortColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if memory.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundColor(HortColors.accent)
            }
            Text(memory.createdAt, style: .time)
                .font(HortTypography.technical(size: HortTypography.Size.caption))
                .monospacedDigit()
                .foregroundColor(HortColors.textTertiary)
        }
        .padding(.horizontal, HortSpacing.xxl)
        .padding(.vertical, HortSpacing.sm)
        .background(selected ? HortColors.accentSoft.opacity(0.35) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openQuickLook(memory) }
        .onTapGesture { handleSelection(of: memory) }
        .draggable(dragPayload(for: memory)) { singleDragPreview(for: memory) }
    }

    private func listTitle(_ memory: MemoryObject) -> String {
        if memory.type == .url, let content = memory.content, let url = URL(string: content) {
            return url.host ?? content
        }
        if let content = memory.content, !content.isEmpty {
            return String(content.prefix(80)).components(separatedBy: .newlines).first ?? content
        }
        return memory.type.rawValue.capitalized
    }

    private func listIconTint(_ type: MemoryType) -> Color {
        switch type {
        case .text:       return HortColors.accent
        case .url:        return HortColors.info
        case .image:      return HortColors.success
        case .screenshot: return HortColors.warning
        case .file:       return HortColors.textSecondary
        }
    }

    private func boardColor(for memory: MemoryObject) -> Color? {
        guard let boardName = memory.board else { return nil }
        return settings.boards.first(where: { $0.name == boardName })?
            .colorHex.flatMap { Color(hexString: $0) }
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

    // MARK: - Quick Look

    private var quickLookShortcut: some View {
        Button(action: { quickLookSelected() }) { }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(app.inspectorTextFocused)
            .opacity(0)
            .allowsHitTesting(false)
    }

    private func quickLookSelected() {
        guard selectedMemories.count == 1, let id = selectedMemories.first,
              let memory = engine.fetch(id: id) else { return }
        openQuickLook(memory)
    }

    private func openQuickLook(_ memory: MemoryObject) {
        if memory.type == .url, let content = memory.content, let url = URL(string: content) {
            NSWorkspace.shared.open(url)
            return
        }
        var fileURL: URL?
        if let path = memory.thumbnailPath, FileManager.default.fileExists(atPath: path) {
            fileURL = URL(fileURLWithPath: path)
        } else if let content = memory.content, FileManager.default.fileExists(atPath: content) {
            fileURL = URL(fileURLWithPath: content)
        }
        guard let url = fileURL else { return }
        NSWorkspace.shared.open(url)
    }
}

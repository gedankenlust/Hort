import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection
    var onOpenSettings: () -> Void = {}

    @ObservedObject private var engine = MemoryEngine.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var addingBoard = false
    @State private var newBoardName = ""
    @FocusState private var boardFieldFocused: Bool

    @State private var renamingBoard: String?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    @State private var collapsedBoards: Set<String> = []
    @State private var folderAlertBoard: String? = nil
    @State private var newFolderName = ""

    @State private var renamingTag: String?
    @State private var renameTagText = ""
    @State private var inboxCount = 0
    @State private var allCount = 0
    @State private var favoritesCount = 0
    @State private var archiveCount = 0
    @State private var boardCounts: [String: Int] = [:]
    @State private var folderCounts: [String: Int] = [:]
    @State private var allTags: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark

            // Primary navigation
            VStack(alignment: .leading, spacing: HortSpacing.xs) {
                SidebarItem(icon: "tray.and.arrow.down", title: "sidebar.inbox",
                            count: inboxCount,
                            isActive: selection == .inbox,
                            action: { selection = .inbox },
                            dropHandler: { apply($0) { $0.board = nil; $0.isArchived = false } })
                SidebarItem(icon: "square.stack", title: "sidebar.all",
                            count: allCount,
                            isActive: selection == .all,
                            action: { selection = .all },
                            dropHandler: { apply($0) { $0.isArchived = false } })
                SidebarItem(icon: "star", title: "sidebar.favorites",
                            count: favoritesCount,
                            isActive: selection == .favorites,
                            action: { selection = .favorites },
                            dropHandler: { apply($0) { $0.isFavorite = true } })
                SidebarItem(icon: "archivebox", title: "sidebar.archive",
                            count: archiveCount,
                            isActive: selection == .archive,
                            action: { selection = .archive },
                            dropHandler: { apply($0) { $0.isArchived = true } })
            }
            .padding(.horizontal, HortSpacing.sm)

            boardsSection

            if !allTags.isEmpty {
                HortSectionHeader(title: "sidebar.tags")
                    .padding(.horizontal, HortSpacing.lg)
                    .padding(.top, HortSpacing.xl)
                    .padding(.bottom, HortSpacing.sm)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: HortSpacing.xs) {
                        ForEach(sortedTags, id: \.self) { tag in
                            SidebarItem(icon: "number", title: tag,
                                        isActive: selection == .tag(tag),
                                        action: { selection = .tag(tag) },
                                        dropHandler: { id in
                                            apply(id) { if !$0.tags.contains(tag) { $0.tags.append(tag) } }
                                        })
                                .contextMenu {
                                    Button { startRenamingTag(tag) } label: {
                                        Label("sidebar.rename_tag", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { deleteTagGlobally(tag) } label: {
                                        Label("sidebar.delete_tag", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, HortSpacing.sm)
                }
            }

            Spacer()

            VStack(spacing: HortSpacing.sm) {
                if settings.aiEnabled {
                    OllamaIndicator(action: onOpenSettings)
                }
                StatusIndicator()
            }
            .padding(.horizontal, HortSpacing.md)
            .padding(.bottom, HortSpacing.md)
        }
        .background(HortColors.surface)
        .frame(minWidth: HortSizing.sidebarWidth, idealWidth: HortSizing.sidebarWidth, maxHeight: .infinity, alignment: .top)
        .navigationSplitViewColumnWidth(HortSizing.sidebarWidth)
        .onAppear { refreshCounts() }
        .onChange(of: engine.dataVersion) { _, _ in refreshCounts() }
        .alert("sidebar.new_folder", isPresented: Binding(
            get: { folderAlertBoard != nil },
            set: { if !$0 { folderAlertBoard = nil } }
        )) {
            TextField("common.name", text: $newFolderName)
            Button("common.add") {
                if let boardName = folderAlertBoard {
                    settings.addFolder(to: boardName, folderName: newFolderName)
                }
                newFolderName = ""
                folderAlertBoard = nil
            }
            Button("common.cancel", role: .cancel) {
                newFolderName = ""
                folderAlertBoard = nil
            }
        } message: {
            Text(String(format: L("sidebar.add_folder_msg"), folderAlertBoard ?? ""))
        }
    }

    // MARK: - Wordmark

    private var wordmark: some View {
        HStack(spacing: HortSpacing.sm) {
            if let logoURL = Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets"),
               let image = NSImage(contentsOfFile: logoURL.path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                // Fallback to original mark if asset missing
                RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous)
                    .fill(HortColors.accent)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(HortColors.background)
                    )
            }

            Text("Hort")
                .font(HortTypography.label(size: HortTypography.Size.headline))
                .foregroundColor(HortColors.textPrimary)
            Spacer()
            HortIconButton(icon: "gearshape", help: "settings.title", action: onOpenSettings)
        }
        .padding(HortSpacing.lg)
    }

    // MARK: - Boards (user-created)

    private var boardsSection: some View {
        VStack(alignment: .leading, spacing: HortSpacing.xs) {
            HortSectionHeader(title: "sidebar.boards",
                              action: startAddingBoard,
                              actionHelp: "sidebar.new_board")
                .padding(.horizontal, HortSpacing.lg)
                .padding(.top, HortSpacing.xl)
                .padding(.bottom, HortSpacing.sm)

            if addingBoard {
                HortTextField(
                    placeholder: "sidebar.board_name_placeholder",
                    text: $newBoardName,
                    onSubmit: commitNewBoard,
                    leadingIcon: "folder.badge.plus",
                    focus: Binding(get: { boardFieldFocused }, set: { boardFieldFocused = $0 })
                )
                .padding(.horizontal, HortSpacing.sm)
            }

            ForEach(boardList, id: \.self) { board in
                if renamingBoard == board.name {
                    boardRenameField(for: board.name)
                } else {
                    let boardColor = board.colorHex.flatMap { Color(hexString: $0) }
                    VStack(alignment: .leading, spacing: HortSpacing.xs) {
                        HStack(spacing: 0) {
                            if !board.folders.isEmpty {
                                Button {
                                    if collapsedBoards.contains(board.name) {
                                        collapsedBoards.remove(board.name)
                                    } else {
                                        collapsedBoards.insert(board.name)
                                    }
                                } label: {
                                    Image(systemName: collapsedBoards.contains(board.name) ? "chevron.right" : "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(HortColors.textTertiary)
                                        .frame(width: 14, height: 14)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, HortSpacing.xs)
                            } else {
                                Spacer().frame(width: 18)
                            }

                            SidebarItem(icon: "square.grid.2x2", title: board.name,
                                        count: boardCounts[board.name] ?? 0,
                                        isActive: selection == .board(board.name),
                                        action: { selection = .board(board.name) },
                                        dropHandler: { id in
                                            apply(id) { $0.board = board.name; $0.folder = nil; $0.isArchived = false }
                                        },
                                        iconColor: boardColor,
                                        accentColor: boardColor)
                                .contextMenu {
                                    Menu("common.change_color") {
                                        Button("Cyan") { settings.changeBoardColor(board.name, to: "32D2E0") }
                                        Button("Grün") { settings.changeBoardColor(board.name, to: "4CD964") }
                                        Button("Pink") { settings.changeBoardColor(board.name, to: "FF2D55") }
                                        Button("Orange") { settings.changeBoardColor(board.name, to: "FF9500") }
                                        Button("Grau") { settings.changeBoardColor(board.name, to: "8E8E93") }
                                        Button("common.reset") { settings.changeBoardColor(board.name, to: nil) }
                                    }
                                    Button {
                                        folderAlertBoard = board.name
                                        newFolderName = ""
                                    } label: {
                                        Label("sidebar.new_folder", systemImage: "folder.badge.plus")
                                    }
                                    Button { startRenaming(board.name) } label: {
                                        Label("sidebar.rename_board", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        removeBoard(board.name)
                                    } label: {
                                        Label("sidebar.remove_board", systemImage: "trash")
                                    }
                                }
                        }

                        if !collapsedBoards.contains(board.name) {
                            ForEach(board.folders, id: \.self) { folder in
                                SidebarItem(icon: "folder", title: folder,
                                            count: folderCounts["\(board.name)||\(folder)"] ?? 0,
                                            isActive: selection == .folder(board: board.name, folder: folder),
                                            action: { selection = .folder(board: board.name, folder: folder) },
                                            dropHandler: { id in
                                                apply(id) { $0.board = board.name; $0.folder = folder; $0.isArchived = false }
                                            },
                                            accentColor: boardColor,
                                            indentation: 24)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            settings.removeFolder(from: board.name, folderName: folder)
                                        } label: {
                                            Label("sidebar.remove_folder", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, HortSpacing.sm)

            if boardList.isEmpty && !addingBoard {
                Button(action: startAddingBoard) {
                    HStack(spacing: HortSpacing.sm) {
                        Image(systemName: "plus")
                            .font(HortTypography.label(size: HortTypography.Size.caption))
                        Text("sidebar.new_board")
                            .font(HortTypography.primary())
                        Spacer()
                    }
                    .foregroundColor(HortColors.textTertiary)
                    .padding(.vertical, HortSpacing.sm)
                    .padding(.horizontal, HortSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, HortSpacing.sm)
            }
        }
    }

    // MARK: - Data

    /// Boards to show: the user's list, plus any board referenced by a memory
    /// that isn't in the list yet (so nothing gets orphaned).
    private var boardList: [Board] {
        var list = settings.boards
        let inUse = Set(engine.recentMemories.compactMap { $0.board })
        let existingNames = Set(list.map { $0.name })
        for boardName in inUse.sorted() where !existingNames.contains(boardName) {
            list.append(Board(name: boardName))
        }
        return list
    }

    private var sortedTags: [String] {
        allTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func refreshCounts() {
        let data = engine.fetchSidebarData()
        inboxCount = data.inbox
        allCount = data.all
        favoritesCount = data.favorites
        archiveCount = data.archive
        boardCounts = data.boards
        folderCounts = data.folders
        allTags = data.tags
    }

    // MARK: - Actions

    private func startAddingBoard() {
        addingBoard = true
        boardFieldFocused = true
    }

    private func commitNewBoard() {
        settings.addBoard(newBoardName)
        newBoardName = ""
        addingBoard = false
    }

    private func removeBoard(_ name: String) {
        settings.removeBoard(name)
        if selection == .board(name) { selection = .inbox }
    }

    private func boardRenameField(for board: String) -> some View {
        HortTextField(
            placeholder: "sidebar.board_name_placeholder",
            text: $renameText,
            onSubmit: { commitRename(from: board) },
            leadingIcon: "square.grid.2x2",
            focus: Binding(get: { renameFocused }, set: { renameFocused = $0 })
        )
        .padding(.horizontal, HortSpacing.sm)
    }

    private func startRenaming(_ board: String) {
        renamingBoard = board
        renameText = board
        renameFocused = true
    }

    private func commitRename(from board: String) {
        let target = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty, target != board {
            settings.renameBoard(board, to: target)
            engine.renameBoard(board, to: target)
            if selection == .board(board) { selection = .board(target) }
        }
        renamingBoard = nil
        renameText = ""
    }

    private func startRenamingTag(_ tag: String) {
        renamingTag = tag
        renameTagText = tag
        let alert = NSAlert()
        alert.messageText = L("sidebar.rename_tag")
        alert.informativeText = L("sidebar.rename_tag_msg")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = tag
        alert.accessoryView = input
        alert.addButton(withTitle: L("common.ok"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !newName.isEmpty, newName != tag {
                engine.renameTag(tag, to: newName)
                if selection == .tag(tag) { selection = .tag(newName) }
            }
        }
        renamingTag = nil
    }

    private func deleteTagGlobally(_ tag: String) {
        engine.deleteTag(tag)
        if selection == .tag(tag) { selection = .all }
    }

    /// Resolves dragged memory ids (one per line — a multi-selection drag sends
    /// all selected ids) and applies the mutation to each. Returns whether any
    /// matched.
    private func apply(_ payload: String, _ mutate: (inout MemoryObject) -> Void) -> Bool {
        let ids = payload.split(separator: "\n").compactMap { UUID(uuidString: String($0)) }
        guard !ids.isEmpty else { return false }
        engine.update(ids: ids, mutate)
        return true
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var isActive: Bool = false
    var action: () -> Void = {}
    /// Optional drop handler. Receives the dragged memory's UUID string and
    /// returns whether it was accepted.
    var dropHandler: ((String) -> Bool)? = nil
    var iconColor: Color? = nil
    /// Tint applied to the active indicator and active foreground.
    var accentColor: Color? = nil
    var indentation: CGFloat = 0

    @State private var isHovering = false
    @State private var isDropTargeted = false

    private var activeColor: Color {
        accentColor ?? HortColors.accent
    }

    var body: some View {
        if let dropHandler {
            button.dropDestination(for: String.self) { items, _ in
                guard let first = items.first else { return false }
                return dropHandler(first)
            } isTargeted: { isDropTargeted = $0 }
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: HortSpacing.md) {
                Image(systemName: icon)
                    .font(HortTypography.primary())
                    .frame(width: 18)
                    .foregroundColor(iconColor ?? (isActive ? activeColor : HortColors.textSecondary))
                Text(LocalizedStringKey(title))
                    .font(HortTypography.primary(weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: HortSpacing.xs)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .monospacedDigit()
                        .foregroundColor(isActive ? activeColor : HortColors.textTertiary)
                }
            }
            .foregroundColor(foreground)
            .padding(.vertical, HortSpacing.sm)
            .padding(.horizontal, HortSpacing.md)
            .padding(.leading, HortSpacing.md + indentation)
            .background(
                RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous).fill(background)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activeColor)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 1 + indentation)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous)
                    .strokeBorder(activeColor, lineWidth: isDropTargeted ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return activeColor }
        if isHovering { return HortColors.textPrimary }
        return HortColors.textSecondary
    }

    private var background: Color {
        if isDropTargeted { return activeColor.opacity(0.14) }
        if isActive { return activeColor.opacity(0.14) }
        if isHovering { return HortColors.elevatedHover.opacity(0.5) }
        return .clear
    }
}

struct StatusIndicator: View {
    @ObservedObject private var capture = CaptureEngine.shared

    private var tint: Color {
        capture.isCapturing ? HortColors.accent : HortColors.warning
    }

    private var statusKey: String {
        capture.isCapturing ? "sidebar.system_live" : "sidebar.capture_paused"
    }

    var body: some View {
        Button {
            capture.toggle()
        } label: {
            HStack(spacing: HortSpacing.sm) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                Text(L(statusKey))
                    .font(HortTypography.primary(size: HortTypography.Size.caption, weight: .medium))
                    .foregroundColor(tint)
                Spacer(minLength: 0)
                Image(systemName: capture.isCapturing ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(tint)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, HortSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous).fill(tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(capture.isCapturing ? "Pause capture" : "Resume capture")
        .accessibilityLabel(L(statusKey))
    }
}

struct OllamaIndicator: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var runtime = AIRuntime.shared
    var action: () -> Void

    /// Re-checks reachability every 15s so a stopped/started Ollama is reflected.
    private let pollTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    /// Dot/accent colour: amber while analyzing, red when offline, accent when
    /// reachable, muted when not yet checked.
    private var tint: Color {
        if runtime.isAnalyzing { return HortColors.warning }
        switch runtime.reachable {
        case .some(true): return HortColors.accent
        case .some(false): return HortColors.danger
        case .none: return HortColors.textTertiary
        }
    }

    private var label: String {
        if runtime.isAnalyzing {
            let queued = runtime.queuedCount
            return queued > 0 ? "Analysiert… (+\(queued))" : "Analysiert…"
        }
        if runtime.reachable == false { return "Ollama offline" }
        return "Ollama: \(settings.aiModel)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: HortSpacing.sm) {
                if runtime.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                        .shadow(color: tint.opacity(0.8), radius: 4)
                }
                Text(label)
                    .font(HortTypography.primary(size: HortTypography.Size.caption, weight: .medium))
                    .foregroundColor(tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(tint)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, HortSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous).fill(tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(runtime.lastError.map { "AI error: \($0) - Click to open settings" }
              ?? "Local AI model - Click to open settings")
        .accessibilityLabel(label)
        .onAppear { runtime.refreshReachability() }
        .onReceive(pollTimer) { _ in
            if !runtime.isAnalyzing { runtime.refreshReachability() }
        }
    }
}

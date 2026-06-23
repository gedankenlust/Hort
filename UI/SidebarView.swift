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
            VStack(alignment: .leading, spacing: 2) {
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
            .padding(.horizontal, 10)

            boardsSection

            if !allTags.isEmpty {
                sectionHeader("sidebar.tags", add: nil)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(allTags, id: \.self) { tag in
                            SidebarItem(icon: "number", title: tag,
                                        isActive: selection == .tag(tag),
                                        action: { selection = .tag(tag) },
                                        dropHandler: { id in
                                            apply(id) { if !$0.tags.contains(tag) { $0.tags.append(tag) } }
                                        })
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                if settings.aiEnabled {
                    OllamaIndicator(action: onOpenSettings)
                }
                StatusIndicator()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Theme.Colors.surface)
        .frame(minWidth: Theme.Layout.sidebarWidth, maxHeight: .infinity, alignment: .top)
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
        HStack(spacing: 9) {
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.Colors.accent)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.Colors.background)
                    )
            }
            
            Text("Hort")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - Boards (user-created)

    private var boardsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionHeader("sidebar.boards", add: { startAddingBoard() })

            if addingBoard {
                HStack(spacing: 7) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textTertiary)
                    TextField("Board name…", text: $newBoardName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .focused($boardFieldFocused)
                        .onSubmit { commitNewBoard() }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.Colors.elevated))
                .padding(.horizontal, 10)
            }

            ForEach(boardList, id: \.self) { board in
                if renamingBoard == board.name {
                    boardRenameField(for: board.name)
                } else {
                    let boardColor = board.colorHex.flatMap { Color(hexString: $0) }
                    VStack(alignment: .leading, spacing: 2) {
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
                                        .foregroundColor(Theme.Colors.textTertiary)
                                        .frame(width: 14, height: 14)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 4)
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
                                        iconColor: boardColor)
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
            .padding(.horizontal, 10)

            if boardList.isEmpty && !addingBoard {
                Button(action: { startAddingBoard() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("sidebar.new_board")
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }
        }
    }

    // MARK: - Section header (with optional add button)

    private func sectionHeader(_ text: String, add: (() -> Void)?) -> some View {
        HStack {
            Text(LocalizedStringKey(text))
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Theme.Colors.textTertiary)
            Spacer()
            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("New board")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 8)
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
        HStack(spacing: 7) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundColor(Theme.Colors.textTertiary)
            TextField("Board name…", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textPrimary)
                .focused($renameFocused)
                .onSubmit { commitRename(from: board) }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.Colors.elevated))
        .padding(.horizontal, 10)
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
    var indentation: CGFloat = 0

    @State private var isHovering = false
    @State private var isDropTargeted = false

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
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundColor(iconColor ?? (isActive ? Theme.Colors.accent : Theme.Colors.textSecondary))
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(isActive ? Theme.Colors.accent : Theme.Colors.textTertiary)
                }
            }
            .foregroundColor(foreground)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .padding(.leading, 10 + indentation)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Colors.accent)
                        .frame(width: 3, height: 16)
                        .padding(.leading, 1 + indentation)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.Colors.accent, lineWidth: isDropTargeted ? 1.5 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        if isActive { return Theme.Colors.accent }
        if isHovering { return Theme.Colors.textPrimary }
        return Theme.Colors.textSecondary
    }

    private var background: Color {
        if isDropTargeted { return Theme.Colors.accentSoft }
        if isActive { return Theme.Colors.accentSoft }
        if isHovering { return Color.white.opacity(0.04) }
        return .clear
    }
}

struct StatusIndicator: View {
    @ObservedObject private var capture = CaptureEngine.shared

    private var tint: Color {
        capture.isCapturing ? Theme.Colors.accent : Theme.Colors.warning
    }

    var body: some View {
        Button {
            capture.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                Text(LocalizedStringKey(capture.isCapturing ? "sidebar.system_live" : "sidebar.capture_paused"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tint)
                Spacer(minLength: 0)
                Image(systemName: capture.isCapturing ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundColor(tint)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(capture.isCapturing ? "Pause capture" : "Resume capture")
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
        if runtime.isAnalyzing { return Theme.Colors.warning }
        switch runtime.reachable {
        case .some(true): return Theme.Colors.accent
        case .some(false): return Theme.Colors.danger
        case .none: return Theme.Colors.textTertiary
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
            HStack(spacing: 8) {
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(tint)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(runtime.lastError.map { "AI error: \($0) - Click to open settings" }
              ?? "Local AI model - Click to open settings")
        .onAppear { runtime.refreshReachability() }
        .onReceive(pollTimer) { _ in
            if !runtime.isAnalyzing { runtime.refreshReachability() }
        }
    }
}

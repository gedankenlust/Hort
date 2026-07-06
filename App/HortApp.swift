import SwiftUI

@main
struct HortApp: App {
    init() {
        print("🚀 Hort Starting...")
        // Initialize engines
        CaptureEngine.shared.start()
        // Backfill semantic-index embeddings for any memories missing one.
        Task { @MainActor in EmbeddingIndexer.shared.backfill() }
        // Snap stale model settings to installed models so AI features work even
        // if the user never opened Settings (default "llama3" may not exist).
        Task { @MainActor in await HortApp.validateModelSettings() }
    }

    /// If the configured chat/embedding models aren't installed, pick sensible
    /// installed ones (a non-embedding model for chat, an embedding model for
    /// embeddings) so analysis, Ask and semantic search don't silently fail.
    @MainActor
    private static func validateModelSettings() async {
        guard let models = try? await OllamaClient.shared.fetchModels(), !models.isEmpty else { return }
        let settings = SettingsStore.shared
        let embeddingHints = ["embed", "bge", "minilm", "gte", "e5", "arctic", "nomic"]
        func isEmbedding(_ name: String) -> Bool {
            let lower = name.lowercased()
            return embeddingHints.contains { lower.contains($0) }
        }
        if !models.contains(settings.aiModel) {
            settings.aiModel = models.first(where: { !isEmbedding($0) }) ?? models.first!
        }
        if !models.contains(settings.embeddingModel) {
            if let embedder = models.first(where: isEmbedding) {
                settings.embeddingModel = embedder
            }
        }
    }
    
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(\.locale, effectiveLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Undo") { app.undoDelete() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!app.undoToastVisible)
            }
            // No multi-window / "New" — Hort is a single dashboard.
            CommandGroup(replacing: .newItem) {}

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.showingSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Navigate") {
                Button("Inbox") { app.navigate(to: .inbox) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("All Memories") { app.navigate(to: .all) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Favorites") { app.navigate(to: .favorites) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Archive") { app.navigate(to: .archive) }
                    .keyboardShortcut("4", modifiers: .command)
            }

            CommandMenu("Memory") {
                Button("Search") { app.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Ask your memory…") { app.showingAsk = true }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(!settings.semanticEnabled)
                Button("Export Shown…") { app.requestExport() }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                // ⌘A is bound in the feed view itself (more reliable than a
                // menu command, which can swallow the first press without focus).
                Button("Select All") { app.selectAll() }
                Button("Delete Selected") { app.deleteSelected() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(app.selectedMemories.isEmpty)
            }
        }

        MenuBarExtra {
            MenuBarContent()
        } label: {
            HortApp.menuBarIcon
        }
        .menuBarExtraStyle(.window)
    }

    /// The status-bar glyph, rendered as a template image so macOS tints it to
    /// match the menu bar's light/dark appearance and highlight state.
    private static var menuBarIcon: Image {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png", subdirectory: "Assets"),
           let nsImage = NSImage(contentsOfFile: url.path) {
            nsImage.size = NSSize(width: 17, height: 16)
            nsImage.isTemplate = true
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "square.stack.3d.up.fill")
    }

    private var effectiveLocale: Locale {
        if settings.language == "system" { return .current }
        return Locale(identifier: settings.language)
    }
}

/// Custom popover content for the menu bar item (`.window` style), styled with
/// the Hort design tokens instead of the plain native NSMenu look.
struct MenuBarContent: View {
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var engine = MemoryEngine.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var app = AppState.shared
    @Environment(\.openWindow) private var openWindow

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().foregroundColor(HortColors.border)

            MenuBarRow(icon: capture.isCapturing ? "pause.fill" : "play.fill",
                       iconColor: capture.isCapturing ? HortColors.warning : HortColors.accent,
                       title: capture.isCapturing ? L("onboarding.stop_capture") : L("onboarding.start_capture")) {
                capture.toggle()
            }

            let recent = Array(engine.recentMemories.prefix(3))
            if !recent.isEmpty {
                Divider().foregroundColor(HortColors.border)
                Text(L("sidebar.inbox"))
                    .font(HortTypography.label(size: 10))
                    .tracking(0.6)
                    .foregroundColor(HortColors.textTertiary)
                    .padding(.horizontal, HortSpacing.md)
                    .padding(.top, HortSpacing.sm)
                    .padding(.bottom, 2)
                ForEach(recent) { memory in
                    MenuBarRow(icon: iconName(for: memory.type),
                               iconColor: iconTint(for: memory.type),
                               title: previewText(memory),
                               subtitle: Self.relativeFormatter.localizedString(for: memory.createdAt, relativeTo: Date())) {
                        showMainWindow()
                        app.reveal(memory.id)
                        closeWindow()
                    }
                }
            }

            Divider().foregroundColor(HortColors.border)

            if settings.semanticEnabled {
                MenuBarRow(icon: "sparkles", iconColor: HortColors.accent, title: L("ask.title")) {
                    showMainWindow()
                    app.showingAsk = true
                    closeWindow()
                }
            }

            MenuBarRow(icon: "gearshape", title: L("settings.title"), shortcut: "⌘,") {
                showMainWindow()
                app.showingSettings = true
                closeWindow()
            }

            Divider().foregroundColor(HortColors.border)

            MenuBarRow(icon: "power", title: L("common.done"), shortcut: "⌘Q", isDestructive: true) {
                NSApp.terminate(nil)
            }
            .padding(.bottom, HortSpacing.xs)
        }
        .frame(width: 280)
        .background(HortColors.surface)
    }

    private var header: some View {
        HStack(spacing: HortSpacing.sm) {
            if let url = Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets"),
               let image = NSImage(contentsOfFile: url.path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Hort")
                    .font(HortTypography.label(size: 13))
                    .foregroundColor(HortColors.textPrimary)
                Text(L(capture.isCapturing ? "sidebar.system_live" : "sidebar.capture_paused"))
                    .font(HortTypography.technical(size: 10))
                    .foregroundColor(capture.isCapturing ? HortColors.accent : HortColors.warning)
            }
            Spacer()
            Circle()
                .fill(capture.isCapturing ? HortColors.accent : HortColors.warning)
                .frame(width: 7, height: 7)
                .shadow(color: (capture.isCapturing ? HortColors.accent : HortColors.warning).opacity(0.7), radius: 3)
        }
        .padding(.horizontal, HortSpacing.md)
        .padding(.vertical, HortSpacing.md)
    }

    private func previewText(_ memory: MemoryObject) -> String {
        if memory.type == .url, let content = memory.content, let url = URL(string: content) {
            return url.host ?? content
        }
        if let content = memory.content, !content.isEmpty {
            return String(content.prefix(48)).components(separatedBy: .newlines).first ?? content
        }
        return memory.type.rawValue.capitalized
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

    private func iconTint(for type: MemoryType) -> Color {
        switch type {
        case .text:       return HortColors.accent
        case .url:        return HortColors.info
        case .image:      return HortColors.success
        case .screenshot: return HortColors.warning
        case .file:       return HortColors.textSecondary
        }
    }

    /// Dismisses the `.window`-style MenuBarExtra popover after a navigational
    /// action, mirroring standard menu behaviour (it doesn't auto-close like
    /// the native `.menu` style would).
    private func closeWindow() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.close()
        }
    }

    /// Brings the main window to front, reopening it via SwiftUI's WindowGroup
    /// if the user had closed it — `NSApp.activate` alone only raises the app,
    /// it doesn't recreate a closed window, so Ask/Settings would silently do
    /// nothing when there's no window left to attach the sheet to.
    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A single row in the menu bar popover: icon, title, optional subtitle/shortcut,
/// with its own hover highlight since this is custom SwiftUI, not a native NSMenu.
private struct MenuBarRow: View {
    let icon: String
    var iconColor: Color = HortColors.textSecondary
    let title: String
    var subtitle: String? = nil
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: HortSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isDestructive ? HortColors.danger : iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(HortTypography.primary(size: 13))
                        .foregroundColor(isDestructive ? HortColors.danger : HortColors.textPrimary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(HortTypography.technical(size: 10))
                            .foregroundColor(HortColors.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: HortSpacing.sm)
                if let shortcut {
                    Text(shortcut)
                        .font(HortTypography.technical(size: 11))
                        .foregroundColor(HortColors.textTertiary)
                }
            }
            .padding(.horizontal, HortSpacing.md)
            .padding(.vertical, 7)
            .background(isHovering ? HortColors.elevatedHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HortSpacing.xs)
        .onHover { isHovering = $0 }
    }
}

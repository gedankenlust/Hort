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
        WindowGroup {
            ContentView()
                .environment(\.locale, effectiveLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 820)
        .commands {
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
    }

    private var effectiveLocale: Locale {
        if settings.language == "system" { return .current }
        return Locale(identifier: settings.language)
    }
}

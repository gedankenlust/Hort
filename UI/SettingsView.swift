import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var indexer = EmbeddingIndexer.shared
    @Environment(\.dismiss) private var dismiss

    @State private var newBundleID = ""
    @State private var confirmClear = false

    @State private var availableModels: [String] = []
    @State private var loadingModels = false
    @State private var ollamaOnline = false

    enum Tab: String, CaseIterable, Identifiable {
        case general = "slider.horizontal.3"
        case privacy = "hand.raised.fill"
        case ai = "brain"
        
        var id: String { self.rawValue }
        
        var title: LocalizedStringKey {
            switch self {
            case .general: return "settings.tab.general"
            case .privacy: return "settings.tab.privacy"
            case .ai: return "settings.tab.ai"
            }
        }
    }
    
    @State private var selectedTab: Tab = .general

    /// Name fragments of common embedding-model families, so chat models stay
    /// out of the embedding picker while real embedders (incl. ones without
    /// "embed" in the name, like bge-m3 or all-minilm) still show up.
    private static let embeddingModelHints = ["embed", "bge", "minilm", "gte", "e5", "arctic", "nomic"]

    /// Embedding-capable models for the picker. Falls back to the full list if
    /// none match (e.g. an unusually named embedding model).
    private var embeddingModelOptions: [String] {
        let embedding = availableModels.filter { name in
            let lower = name.lowercased()
            return Self.embeddingModelHints.contains { lower.contains($0) }
        }
        return embedding.isEmpty ? availableModels : embedding
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with Segmented Tab Picker and Dismiss button
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.title, systemImage: tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
                .background(Theme.Colors.border)

            // Content Area based on Selected Tab
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .privacy:
                        privacyTab
                    case .ai:
                        aiTab
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 480)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
        .task {
            await loadOllamaModels()
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // General settings
            section("settings.general") {
                Picker(LocalizedStringKey("settings.language"), selection: $settings.language) {
                    Text(LocalizedStringKey("settings.language.system")).tag("system")
                    Text(LocalizedStringKey("settings.language.en")).tag("en")
                    Text(LocalizedStringKey("settings.language.de")).tag("de")
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
            }

            // Capture settings
            section("settings.capture") {
                Toggle(isOn: Binding(
                    get: { capture.isCapturing },
                    set: { $0 ? capture.resume() : capture.pause() }
                )) {
                    Text(LocalizedStringKey("settings.capture.enabled"))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(Theme.Colors.accent)
            }

            Divider()
                .background(Theme.Colors.border)
                .padding(.vertical, 4)

            // Danger Zone
            section("settings.danger_zone") {
                Button(role: .destructive, action: { confirmClear = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text(LocalizedStringKey("settings.clear_all"))
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.12))
                    .foregroundColor(.red)
                    .cornerRadius(Theme.Layout.cornerRadius)
                }
                .buttonStyle(.plain)
                .confirmationDialog(LocalizedStringKey("settings.clear_all_confirm"),
                                    isPresented: $confirmClear, titleVisibility: .visible) {
                    Button(LocalizedStringKey("common.delete"), role: .destructive) { MemoryEngine.shared.deleteAll() }
                    Button(LocalizedStringKey("common.cancel"), role: .cancel) {}
                }
            }
        }
    }

    @ViewBuilder
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("settings.privacy") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.ignoreConcealed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey("settings.privacy.ignore_passwords"))
                                .foregroundColor(Theme.Colors.textPrimary)
                            Text(LocalizedStringKey("settings.privacy.ignore_passwords_desc"))
                                .font(Theme.Fonts.technical(size: 9))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.Colors.accent)
                    
                    Text(LocalizedStringKey("settings.privacy.screenshot_warning"))
                        .font(Theme.Fonts.technical(size: 9))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("settings.excluded_apps") {
                excludedAppsEditor
            }
        }
    }

    @ViewBuilder
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Local AI
            section("settings.ai.title") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.aiEnabled) {
                        Text(LocalizedStringKey("settings.ai.enabled"))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.Colors.accent)

                    if settings.aiEnabled {
                        Toggle(isOn: $settings.aiAutopilot) {
                            Text(LocalizedStringKey("settings.ai.autopilot"))
                                .foregroundColor(Theme.Colors.textPrimary)
                        }
                        .toggleStyle(.switch)
                        .tint(Theme.Colors.accent)
                        
                        if loadingModels {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(LocalizedStringKey("settings.ai.loading"))
                                    .font(Theme.Fonts.technical(size: 10))
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }
                        } else if ollamaOnline {
                            Picker(LocalizedStringKey("settings.ai.model"), selection: $settings.aiModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.Colors.accent)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField(LocalizedStringKey("settings.ai.model"), text: $settings.aiModel)
                                    .textFieldStyle(.plain)
                                    .font(Theme.Fonts.technical(size: 11))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(6)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(6)
                                
                                Text(LocalizedStringKey("settings.ai.offline"))
                                    .font(Theme.Fonts.technical(size: 9))
                                    .foregroundColor(Theme.Colors.warning)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }

            // Semantic search & Ask
            section("settings.semantic.title") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.semanticEnabled) {
                        Text(LocalizedStringKey("settings.semantic.enabled"))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.Colors.accent)
                    .onChange(of: settings.semanticEnabled) { _, on in
                        if on { EmbeddingIndexer.shared.backfill() }
                    }

                    Text(LocalizedStringKey("settings.semantic.desc"))
                        .font(Theme.Fonts.technical(size: 9))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.semanticEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            if ollamaOnline {
                                Picker(LocalizedStringKey("settings.semantic.model"), selection: $settings.embeddingModel) {
                                    ForEach(embeddingModelOptions, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Theme.Colors.accent)
                            } else {
                                TextField(LocalizedStringKey("settings.semantic.model"), text: $settings.embeddingModel)
                                    .textFieldStyle(.plain)
                                    .font(Theme.Fonts.technical(size: 11))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .padding(6)
                                    .background(Theme.Colors.surface)
                                    .cornerRadius(6)
                            }
                            
                            Text(LocalizedStringKey("settings.semantic.model_warning"))
                                .font(Theme.Fonts.technical(size: 9))
                                .foregroundColor(Theme.Colors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                        .onChange(of: settings.embeddingModel) { _, _ in
                            MemoryEngine.shared.clearEmbeddings()
                            EmbeddingIndexer.shared.backfill()
                        }
                    }

                    if settings.semanticEnabled, indexer.isIndexing || indexer.pending > 0 {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(String(format: L("settings.semantic.indexing"),
                                        "\(indexer.pending + (indexer.isIndexing ? 1 : 0))"))
                                .font(Theme.Fonts.technical(size: 10))
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func loadOllamaModels() async {
        loadingModels = true
        do {
            let models = try await OllamaClient.shared.fetchModels()
            availableModels = models
            ollamaOnline = true
            if !models.isEmpty && !models.contains(settings.aiModel) {
                settings.aiModel = models.first!
            }
        } catch {
            ollamaOnline = false
        }
        loadingModels = false
    }

    @ViewBuilder
    private var excludedAppsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.excludedBundleIDs.isEmpty {
                Text(LocalizedStringKey("settings.excluded_apps.empty"))
                    .font(Theme.Fonts.technical(size: 10))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(settings.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                            HStack {
                                Text(bundleID)
                                    .font(Theme.Fonts.technical(size: 11))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                Spacer()
                                Button(action: { settings.excludedBundleIDs.remove(bundleID) }) {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(Theme.Colors.surface)
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            HStack {
                TextField(LocalizedStringKey("settings.excluded_apps.placeholder"), text: $newBundleID)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.technical(size: 11))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(6)
                    .background(Theme.Colors.surface)
                    .cornerRadius(6)
                    .onSubmit(addBundleID)
                Button(action: addBundleID) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func addBundleID() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.excludedBundleIDs.insert(trimmed)
        newBundleID = ""
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(Theme.Fonts.technical(size: 10))
                .foregroundColor(Theme.Colors.textSecondary)
            content()
        }
    }
}

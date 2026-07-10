import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var indexer = EmbeddingIndexer.shared
    @Environment(\.dismiss) private var dismiss
    /// Same UserDefaults key as `HortApp.showMenuBarIcon` — kept as a separate
    /// `@AppStorage` rather than a `SettingsStore` property so toggling it can't
    /// cascade through `SettingsStore`'s shared `objectWillChange` (see the note
    /// on `HortApp.showMenuBarIcon`).
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    @State private var newBundleID = ""
    @State private var confirmClear = false

    @State private var availableModels: [String] = []
    @State private var loadingModels = false
    @State private var ollamaOnline = false
    @State private var storageSize: String?

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case privacy
        case ai

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
            toolbarHeader

            Divider()
                .background(HortColors.border)

            // Segmented tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .padding(.vertical, HortSpacing.md)

            Divider()
                .background(HortColors.border)

            // Content Area based on Selected Tab
            ScrollView {
                VStack(alignment: .leading, spacing: HortSpacing.xl) {
                    switch selectedTab {
                    case .general:
                        generalTab
                    case .privacy:
                        privacyTab
                    case .ai:
                        aiTab
                    }
                }
                .padding(HortSpacing.xl)
            }
        }
        .frame(width: 600, height: 650)
        .background(HortColors.background)
        .preferredColorScheme(.dark)
        .task {
            await loadOllamaModels()
            let root = FileSystemManager.shared.rootURL
            storageSize = await Task.detached { Self.folderSizeString(root) }.value
        }
    }

    // MARK: - Toolbar header

    private var toolbarHeader: some View {
        HStack {
            Text("settings.title")
                .font(HortTypography.label(size: HortTypography.Size.title))
                .foregroundColor(HortColors.textPrimary)

            Spacer()

            Button(action: { dismiss() }) {
                Text(LocalizedStringKey("common.done"))
                    .font(HortTypography.label(weight: .medium))
                    .padding(.horizontal, HortSpacing.md)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(HortColors.accent)
            .foregroundColor(HortColors.background)
            .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, HortSpacing.xl)
        .padding(.vertical, HortSpacing.md)
    }

    // MARK: - Tabs

    @ViewBuilder
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: HortSpacing.xl) {
            // General settings
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.general")

                Picker(LocalizedStringKey("settings.language"), selection: $settings.language) {
                    Text(LocalizedStringKey("settings.language.system")).tag("system")
                    Text(LocalizedStringKey("settings.language.en")).tag("en")
                    Text(LocalizedStringKey("settings.language.de")).tag("de")
                }
                .pickerStyle(.menu)
                .tint(HortColors.accent)
            }
            .settingsCard()

            // Capture settings
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.capture")

                Toggle(isOn: Binding(
                    get: { capture.isCapturing },
                    set: { $0 ? capture.resume() : capture.pause() }
                )) {
                    Text(LocalizedStringKey("settings.capture.enabled"))
                        .foregroundColor(HortColors.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(HortColors.accent)

                Toggle(isOn: $showMenuBarIcon) {
                    Text(LocalizedStringKey("settings.menubar_icon"))
                        .foregroundColor(HortColors.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(HortColors.accent)

                Toggle(isOn: $settings.launchAtLogin) {
                    Text(LocalizedStringKey("settings.launch_at_login"))
                        .foregroundColor(HortColors.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(HortColors.accent)
            }
            .settingsCard()

            // Danger Zone
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.danger_zone")

                HortButton(
                    title: "settings.clear_all",
                    icon: "trash",
                    style: .destructive
                ) { confirmClear = true }
                .confirmationDialog(LocalizedStringKey("settings.clear_all_confirm"),
                                    isPresented: $confirmClear, titleVisibility: .visible) {
                    Button(LocalizedStringKey("common.delete"), role: .destructive) { MemoryEngine.shared.deleteAll() }
                    Button(LocalizedStringKey("common.cancel"), role: .cancel) {}
                }
            }
            .settingsCard()
        }
    }

    @ViewBuilder
    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: HortSpacing.xl) {
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.privacy")

                VStack(alignment: .leading, spacing: HortSpacing.md) {
                    Toggle(isOn: $settings.ignoreConcealed) {
                        VStack(alignment: .leading, spacing: HortSpacing.xs) {
                            Text(LocalizedStringKey("settings.privacy.ignore_passwords"))
                                .foregroundColor(HortColors.textPrimary)
                            Text(LocalizedStringKey("settings.privacy.ignore_passwords_desc"))
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(HortColors.accent)

                    Text(LocalizedStringKey("settings.privacy.screenshot_warning"))
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .foregroundColor(HortColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.excluded_apps")
                excludedAppsEditor
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.storage")

                VStack(alignment: .leading, spacing: HortSpacing.sm) {
                    Text(storagePathDisplay)
                        .font(HortTypography.technical(size: HortTypography.Size.bodySmall))
                        .foregroundColor(HortColors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(HortSpacing.sm)
                        .background(HortColors.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))

                    HStack(spacing: HortSpacing.sm) {
                        HortButton(
                            title: "settings.storage.reveal",
                            icon: "folder",
                            style: .ghost
                        ) { revealStorage() }

                        Spacer()

                        if let storageSize {
                            Text(storageSize)
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.textTertiary)
                        }
                    }
                }
            }
            .settingsCard()
        }
    }

    private var storagePathDisplay: String {
        FileSystemManager.shared.rootURL.path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func revealStorage() {
        NSWorkspace.shared.activateFileViewerSelecting([FileSystemManager.shared.rootURL])
    }

    /// Total size of a folder, formatted (e.g. "12.3 MB"). Runs off the main
    /// thread because it walks the whole tree.
    nonisolated private static func folderSizeString(_ url: URL) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return nil
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    @ViewBuilder
    private var aiTab: some View {
        VStack(alignment: .leading, spacing: HortSpacing.xl) {
            // Local AI
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.ai.title")

                VStack(alignment: .leading, spacing: HortSpacing.md) {
                    Toggle(isOn: $settings.aiEnabled) {
                        Text(LocalizedStringKey("settings.ai.enabled"))
                            .foregroundColor(HortColors.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(HortColors.accent)

                    if settings.aiEnabled {
                        Toggle(isOn: $settings.aiAutopilot) {
                            Text(LocalizedStringKey("settings.ai.autopilot"))
                                .foregroundColor(HortColors.textPrimary)
                        }
                        .toggleStyle(.switch)
                        .tint(HortColors.accent)

                        if loadingModels {
                            HStack(spacing: HortSpacing.sm) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(LocalizedStringKey("settings.ai.loading"))
                                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                                    .foregroundColor(HortColors.textSecondary)
                            }
                        } else if ollamaOnline {
                            ModelPicker(
                                label: "settings.ai.model",
                                selection: $settings.aiModel,
                                options: availableModels
                            )
                        } else {
                            VStack(alignment: .leading, spacing: HortSpacing.xs) {
                                HortTextField(
                                    placeholder: "settings.ai.model",
                                    text: $settings.aiModel
                                )

                                Text(LocalizedStringKey("settings.ai.offline"))
                                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                                    .foregroundColor(HortColors.warning)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .settingsCard()

            // Semantic search & Ask
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                HortSectionHeader(title: "settings.semantic.title")

                VStack(alignment: .leading, spacing: HortSpacing.md) {
                    Toggle(isOn: $settings.semanticEnabled) {
                        Text(LocalizedStringKey("settings.semantic.enabled"))
                            .foregroundColor(HortColors.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(HortColors.accent)
                    .onChange(of: settings.semanticEnabled) { _, on in
                        if on { EmbeddingIndexer.shared.backfill() }
                    }

                    Text(LocalizedStringKey("settings.semantic.desc"))
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .foregroundColor(HortColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.semanticEnabled {
                        VStack(alignment: .leading, spacing: HortSpacing.sm) {
                            if ollamaOnline {
                                ModelPicker(
                                    label: "settings.semantic.model",
                                    selection: $settings.embeddingModel,
                                    options: embeddingModelOptions
                                )
                            } else {
                                HortTextField(
                                    placeholder: "settings.semantic.model",
                                    text: $settings.embeddingModel
                                )
                            }

                            Text(LocalizedStringKey("settings.semantic.model_warning"))
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, HortSpacing.xs)
                        .onChange(of: settings.embeddingModel) { _, _ in
                            MemoryEngine.shared.clearEmbeddings()
                            EmbeddingIndexer.shared.backfill()
                        }
                    }

                    if settings.semanticEnabled, indexer.isIndexing || indexer.pending > 0 {
                        HStack(spacing: HortSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text(String(format: L("settings.semantic.indexing"),
                                        "\(indexer.pending + (indexer.isIndexing ? 1 : 0))"))
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.textSecondary)
                        }
                    }
                }
            }
            .settingsCard()
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
        VStack(alignment: .leading, spacing: HortSpacing.md) {
            if settings.excludedBundleIDs.isEmpty {
                Text(LocalizedStringKey("settings.excluded_apps.empty"))
                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                    .foregroundColor(HortColors.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: HortSpacing.xs) {
                        ForEach(settings.excludedBundleIDs.sorted(), id: \.self) { bundleID in
                            HStack {
                                Text(bundleID)
                                    .font(HortTypography.technical(size: HortTypography.Size.bodySmall))
                                    .foregroundColor(HortColors.textPrimary)
                                Spacer()
                                HortIconButton(
                                    icon: "minus.circle",
                                    help: "common.delete"
                                ) { settings.excludedBundleIDs.remove(bundleID) }
                            }
                            .padding(.vertical, HortSpacing.xs)
                            .padding(.horizontal, HortSpacing.sm)
                            .background(HortColors.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            HStack(spacing: HortSpacing.sm) {
                HortTextField(
                    placeholder: "settings.excluded_apps.placeholder",
                    text: $newBundleID,
                    onSubmit: addBundleID
                )

                HortIconButton(
                    icon: "plus",
                    help: "common.add"
                ) { addBundleID() }
            }
        }
    }

    private func addBundleID() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.excludedBundleIDs.insert(trimmed)
        newBundleID = ""
    }

}

// MARK: - Model Picker

private struct ModelPicker: View {
    let label: LocalizedStringKey
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Picker(label, selection: $selection) {
            ForEach(options, id: \.self) { model in
                Text(model).tag(model)
            }
        }
        .pickerStyle(.menu)
        .tint(HortColors.accent)
    }
}

// MARK: - View Modifiers

struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(HortSpacing.lg)
            .background(HortColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                    .strokeBorder(HortColors.border, lineWidth: 1)
            )
    }
}

extension View {
    func settingsCard() -> some View {
        self.modifier(SettingsCardModifier())
    }
}

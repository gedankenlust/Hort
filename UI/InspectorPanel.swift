import SwiftUI
import AppKit

struct InspectorPanel: View {
    @Binding var selectedMemories: Set<UUID>
    @State private var memory: MemoryObject? = nil

    @ObservedObject private var engine = MemoryEngine.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var exportedURL: URL?
    @State private var newTag = ""
    @State private var analyzing = false
    @State private var streamingSummary = ""
    @State private var aiError: String? = nil

    var body: some View {
        Group {
            if selectedMemories.count > 1 {
                multiSelectState
            } else if let memory = memory, selectedMemories.count == 1 {
                detail(for: memory)
            } else {
                emptyState
            }
        }
        .frame(minWidth: HortSizing.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(HortColors.surface)
        .onChange(of: selectedMemories) { _, newSelection in
            if newSelection.count == 1, let id = newSelection.first {
                memory = engine.fetch(id: id)
            } else {
                memory = nil
            }
        }
        .onChange(of: engine.dataVersion) { _, _ in
            if selectedMemories.count == 1, let id = selectedMemories.first {
                memory = engine.fetch(id: id)
            }
        }
    }

    @ViewBuilder
    private func detail(for memory: MemoryObject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HortSpacing.xl) {
                // Header
                HStack(spacing: HortSpacing.md) {
                    Image(systemName: iconName(for: memory.type))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(HortColors.accent)
                        .frame(width: 32, height: 32)
                        .background(HortColors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(memory.type.rawValue.capitalized)
                            .font(HortTypography.label(size: HortTypography.Size.headline))
                            .foregroundColor(HortColors.textPrimary)
                        Text(memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(HortTypography.primary(size: HortTypography.Size.caption))
                            .foregroundColor(HortColors.textTertiary)
                    }
                    Spacer()
                    Button(action: { toggleFavorite(memory) }) {
                        Image(systemName: memory.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(memory.isFavorite ? HortColors.accent : HortColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey("inspector.favorite"))
                }

                VStack(spacing: HortSpacing.sm) {
                    metaRow(LocalizedStringKey("inspector.source"), memory.sourceApp ?? "Unknown")
                    if let board = memory.board { metaRow(LocalizedStringKey("inspector.board"), board) }
                    if let folder = memory.folder { metaRow(LocalizedStringKey("inspector.folder"), folder) }
                    metaRow(LocalizedStringKey("inspector.id"), String(memory.id.uuidString.prefix(8)).lowercased())
                }

                if let path = filePath(memory) {
                    section(LocalizedStringKey("inspector.path")) {
                        HStack(spacing: HortSpacing.sm) {
                            Text(path)
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            HortIconButton(icon: "doc.on.doc",
                                           help: LocalizedStringKey("inspector.copy")) {
                                ClipboardMonitor.shared.writeWithoutCapture(path)
                            }
                        }
                        .padding(HortSpacing.md)
                        .background(HortColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                    }
                }

                if let content = memory.content, !content.isEmpty, memory.type != .image, memory.type != .screenshot {
                    section(LocalizedStringKey("inspector.content")) {
                        SelectableText(text: content)
                            .frame(minHeight: 80, idealHeight: 150, maxHeight: 240)
                            .padding(HortSpacing.md)
                            .background(HortColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                    }
                }

                if (memory.type == .image || memory.type == .screenshot),
                   let ocrText = memory.metadata["ocrText"], !ocrText.isEmpty {
                    section(LocalizedStringKey("inspector.ocr_text")) {
                        SelectableText(text: ocrText)
                            .frame(minHeight: 80, idealHeight: 150, maxHeight: 240)
                            .padding(HortSpacing.md)
                            .background(HortColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                    }
                }

                if settings.aiEnabled {
                    aiAnalysisSection(for: memory)
                }

                section(LocalizedStringKey("inspector.tags")) { tagEditor(for: memory) }

                section(LocalizedStringKey("inspector.actions")) {
                    VStack(spacing: HortSpacing.sm) {
                        HortButton(title: LocalizedStringKey("inspector.copy"),
                                   icon: "doc.on.doc",
                                   style: .secondary) {
                            if let content = memory.content {
                                ClipboardMonitor.shared.writeWithoutCapture(content)
                            }
                        }
                        HortButton(title: LocalizedStringKey("inspector.export"),
                                   icon: "square.and.arrow.up",
                                   style: .secondary) {
                            exportedURL = try? ExportEngine.shared.exportToMarkdown(memory)
                        }
                        HortButton(title: LocalizedStringKey(memory.isArchived ? "inspector.unarchive" : "inspector.archive"),
                                   icon: memory.isArchived ? "tray.and.arrow.up" : "archivebox",
                                   style: .secondary) {
                            let value = !memory.isArchived
                            engine.update(memory) { $0.isArchived = value }
                            selectedMemories.removeAll()
                        }
                        HortButton(title: LocalizedStringKey("inspector.delete"),
                                   icon: "trash",
                                   style: .destructive) {
                            engine.delete(memory)
                            selectedMemories.removeAll()
                        }
                    }
                    if let url = exportedURL {
                        Text("Exported → \(url.lastPathComponent)")
                            .font(HortTypography.primary(size: HortTypography.Size.caption))
                            .foregroundColor(HortColors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(HortSpacing.xl)
        }
    }

    /// The on-disk path worth showing: the original file path for Finder
    /// captures and screenshots, or the stored asset location for images.
    private func filePath(_ memory: MemoryObject) -> String? {
        if let p = memory.metadata["sourcePath"], !p.isEmpty { return p }
        switch memory.type {
        case .file, .screenshot, .image:
            if let c = memory.content, !c.isEmpty, c != "Image" { return c }
        default:
            break
        }
        return nil
    }

    private func runAIAnalysis(for memory: MemoryObject) {
        guard let content = memory.content, !content.isEmpty else { return }
        analyzing = true
        streamingSummary = ""
        aiError = nil

        Task {
            do {
                let model = settings.aiModel
                try await OllamaClient.shared.analyze(content: content, model: model) { result in
                    DispatchQueue.main.async {
                        guard result.done else {
                            // Stream the summary live for feedback, but don't
                            // persist yet — tags are still half-parsed.
                            streamingSummary = result.summary
                            return
                        }
                        var updatedMemory = memory
                        updatedMemory.metadata["aiSummary"] = result.summary
                        for tag in result.tags where !updatedMemory.tags.contains(tag) {
                            updatedMemory.tags.append(tag)
                        }
                        self.memory = engine.update(updatedMemory) { _ in }
                    }
                }
                await MainActor.run {
                    analyzing = false
                    streamingSummary = ""
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    analyzing = false
                    streamingSummary = ""
                }
            }
        }
    }

    private var multiSelectState: some View {
        VStack(spacing: HortSpacing.xl) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 32))
                .foregroundColor(HortColors.textTertiary)

            Text("\(selectedMemories.count) " + L("inspector.selected"))
                .font(HortTypography.label(size: HortTypography.Size.body))
                .foregroundColor(HortColors.textPrimary)

            multiSelectPreviews

            VStack(spacing: HortSpacing.sm) {
                Menu {
                    Button(LocalizedStringKey("inspector.move_to_inbox")) { moveSelected(toBoard: nil) }
                    if !settings.boards.isEmpty { Divider() }
                    ForEach(settings.boards) { board in
                        Button(board.name) { moveSelected(toBoard: board.name) }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "tray.full").font(.system(size: 12)).frame(width: 16)
                        Text("inspector.move_to_board").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 11)
                    .background(HortColors.elevated)
                    .foregroundColor(HortColors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                HortButton(title: LocalizedStringKey("inspector.favorite_all"),
                           icon: "star",
                           style: .secondary) {
                    engine.update(ids: Array(selectedMemories)) { $0.isFavorite = true }
                    selectedMemories.removeAll()
                }
                HortButton(title: LocalizedStringKey("inspector.unfavorite_all"),
                           icon: "star.slash",
                           style: .secondary) {
                    engine.update(ids: Array(selectedMemories)) { $0.isFavorite = false }
                    selectedMemories.removeAll()
                }
                if AppState.shared.selection == .archive {
                    HortButton(title: LocalizedStringKey("inspector.unarchive_all"),
                               icon: "tray.and.arrow.up",
                               style: .secondary) {
                        engine.update(ids: Array(selectedMemories)) { $0.isArchived = false }
                        selectedMemories.removeAll()
                    }
                } else {
                    HortButton(title: LocalizedStringKey("inspector.archive_all"),
                               icon: "archivebox",
                               style: .secondary) {
                        engine.update(ids: Array(selectedMemories)) { $0.isArchived = true }
                        selectedMemories.removeAll()
                    }
                }
                HortButton(title: LocalizedStringKey("inspector.delete_all"),
                           icon: "trash",
                           style: .destructive) {
                    engine.delete(ids: selectedMemories)
                    selectedMemories.removeAll()
                }
                HortButton(title: LocalizedStringKey("inspector.clear_selection"),
                           icon: "xmark.circle",
                           style: .ghost) {
                    selectedMemories.removeAll()
                }
            }
            .padding(.horizontal, HortSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var multiSelectPreviews: some View {
        let objects = selectedMemoryObjects
        let previews = Array(objects.prefix(4))
        let remaining = objects.count - previews.count

        if !previews.isEmpty {
            HStack(spacing: -HortSpacing.sm) {
                ForEach(previews) { memory in
                    thumbnailPreview(for: memory)
                        .overlay(
                            RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous)
                                .strokeBorder(HortColors.border, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, HortSpacing.sm)

            if remaining > 0 {
                Text(String(format: L("inspector.and_more"), remaining))
                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                    .foregroundColor(HortColors.textTertiary)
            }
        }
    }

    private var selectedMemoryObjects: [MemoryObject] {
        selectedMemories.compactMap { engine.fetch(id: $0) }
    }

    private func thumbnailPreview(for memory: MemoryObject) -> some View {
        Group {
            if let path = memory.thumbnailPath ?? memory.content,
               (memory.type == .image || memory.type == .screenshot),
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: iconName(for: memory.type))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(HortColors.accent)
            }
        }
        .frame(width: 44, height: 44)
        .background(HortColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
    }

    /// Moves every selected memory to `board` (nil = back to Inbox) and unarchives it.
    private func moveSelected(toBoard board: String?) {
        engine.update(ids: Array(selectedMemories)) { $0.board = board; $0.isArchived = false }
        selectedMemories.removeAll()
    }

    private var emptyState: some View {
        HortEmptyState(
            icon: "rectangle.righthalf.inset.filled",
            title: LocalizedStringKey("inspector.select_memory")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metaRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(HortTypography.label(size: HortTypography.Size.caption, weight: .medium))
                .foregroundColor(HortColors.textTertiary)
            Spacer()
            Text(value)
                .font(HortTypography.technical())
                .foregroundColor(HortColors.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: HortSpacing.sm) {
            HortSectionHeader(title: title)
            content()
        }
    }

    @ViewBuilder
    private func aiAnalysisSection(for memory: MemoryObject) -> some View {
        section(LocalizedStringKey("inspector.ai_analysis")) {
            VStack(alignment: .leading, spacing: HortSpacing.md) {
                if analyzing {
                    if !streamingSummary.isEmpty {
                        Text(streamingSummary)
                            .font(HortTypography.primary(size: HortTypography.Size.caption))
                            .lineSpacing(3)
                            .foregroundColor(HortColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: HortSpacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L("inspector.analyzing"))
                            .font(HortTypography.technical(size: HortTypography.Size.caption))
                            .foregroundColor(HortColors.textSecondary)
                    }
                } else if let errorMsg = aiError {
                    Text(String(format: L("inspector.analysis_error"), errorMsg))
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .foregroundColor(HortColors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let aiSummary = memory.metadata["aiSummary"], !aiSummary.isEmpty {
                    Text(aiSummary)
                        .font(HortTypography.primary(size: HortTypography.Size.caption))
                        .lineSpacing(3)
                        .foregroundColor(HortColors.accent)
                        .padding(HortSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HortColors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous)
                                .strokeBorder(HortColors.accent.opacity(0.2), lineWidth: 1)
                        )
                    HortButton(title: LocalizedStringKey("inspector.reanalyze"),
                               icon: "sparkles",
                               style: .secondary) {
                        runAIAnalysis(for: memory)
                    }
                } else {
                    HortButton(title: LocalizedStringKey("inspector.analyze"),
                               icon: "sparkles",
                               style: .primary) {
                        runAIAnalysis(for: memory)
                    }
                }
            }
        }
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

    private func toggleFavorite(_ memory: MemoryObject) {
        let updated = engine.update(memory) { $0.isFavorite.toggle() }
        self.memory = updated
    }

    @ViewBuilder
    private func tagEditor(for memory: MemoryObject) -> some View {
        if !memory.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HortSpacing.xs) {
                    ForEach(memory.tags, id: \.self) { tag in
                        HortTagChip(text: tag) { removeTag(tag, from: memory) }
                    }
                }
            }
        }
        HortTextField(
            placeholder: LocalizedStringKey("inspector.add_tag"),
            text: $newTag,
            onSubmit: { addTag(to: memory) },
            leadingIcon: "number",
            trailingView: AnyView(
                Button(action: { addTag(to: memory) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(HortColors.accent)
                }
                .buttonStyle(.plain)
            )
        )
    }

    private func addTag(to memory: MemoryObject) {
        guard let tag = Tag.normalize(newTag), !memory.tags.contains(tag) else {
            newTag = ""
            return
        }
        self.memory = engine.update(memory) { $0.tags.append(tag) }
        newTag = ""
    }

    private func removeTag(_ tag: String, from memory: MemoryObject) {
        self.memory = engine.update(memory) { $0.tags.removeAll { $0 == tag } }
    }
}

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
        .frame(minWidth: 260)
        .frame(maxHeight: .infinity)
        .background(Theme.Colors.surface)
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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 11) {
                    Image(systemName: iconName(for: memory.type))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.Colors.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.Colors.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(memory.type.rawValue.capitalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Text(memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    Button(action: { toggleFavorite(memory) }) {
                        Image(systemName: memory.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(memory.isFavorite ? Theme.Colors.accent
                                                               : Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle favourite")
                }

                VStack(spacing: 9) {
                    metaRow(LocalizedStringKey("inspector.source"), memory.sourceApp ?? "Unknown")
                    if let board = memory.board { metaRow("Board", board) }
                    if let folder = memory.folder { metaRow("Folder", folder) }
                    metaRow(LocalizedStringKey("inspector.id"), String(memory.id.uuidString.prefix(8)).lowercased())
                }

                if let content = memory.content, !content.isEmpty, memory.type != .image, memory.type != .screenshot {
                    section("inspector.content") {
                        ScrollView {
                            Text(content)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 150)
                        .padding(10)
                        .background(Theme.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if (memory.type == .image || memory.type == .screenshot),
                   let ocrText = memory.metadata["ocrText"], !ocrText.isEmpty {
                    section("inspector.ocr_text") {
                        ScrollView {
                            Text(ocrText)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 150)
                        .padding(10)
                        .background(Theme.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                if settings.aiEnabled {
                    section("inspector.ai_analysis") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let aiSummary = memory.metadata["aiSummary"], !aiSummary.isEmpty {
                                Text(aiSummary)
                                    .font(.system(size: 11))
                                    .lineSpacing(3)
                                    .foregroundColor(Theme.Colors.accent)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.Colors.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            
                            if analyzing {
                                if !streamingSummary.isEmpty {
                                    Text(streamingSummary)
                                        .font(.system(size: 11))
                                        .lineSpacing(3)
                                        .foregroundColor(Theme.Colors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("inspector.analyzing")
                                        .font(Theme.Fonts.technical(size: 10))
                                        .foregroundColor(Theme.Colors.textSecondary)
                                }
                                .padding(.vertical, 4)
                            } else {
                                Button(action: { runAIAnalysis(for: memory) }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 11))
                                        Text(memory.metadata["aiSummary"] != nil ? "inspector.reanalyze" : "inspector.analyze")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(Theme.Colors.background)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 12)
                                    .background(Theme.Colors.accent)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let errorMsg = aiError {
                                Text(errorMsg)
                                    .font(Theme.Fonts.technical(size: 9))
                                    .foregroundColor(Theme.Colors.danger)
                            }
                        }
                    }
                }

                section("inspector.tags") { tagEditor(for: memory) }

                section("inspector.actions") {
                    VStack(spacing: 6) {
                        ActionButton(icon: "doc.on.doc", title: "inspector.copy") {
                            if let content = memory.content {
                                ClipboardMonitor.shared.writeWithoutCapture(content)
                            }
                        }
                        ActionButton(icon: "square.and.arrow.up", title: "inspector.export") {
                            exportedURL = try? ExportEngine.shared.exportToMarkdown(memory)
                        }
                        ActionButton(icon: memory.isArchived ? "tray.and.arrow.up" : "archivebox",
                                     title: memory.isArchived ? "inspector.unarchive" : "inspector.archive") {
                            let value = !memory.isArchived
                            engine.update(memory) { $0.isArchived = value }
                            selectedMemories.removeAll()
                        }
                        ActionButton(icon: "trash", title: "inspector.delete", tint: Theme.Colors.danger) {
                            engine.delete(memory)
                            selectedMemories.removeAll()
                        }
                    }
                    if let url = exportedURL {
                        Text("Exported → \(url.lastPathComponent)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(18)
        }
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
                    aiError = "Fehler: \(error.localizedDescription)"
                    analyzing = false
                    streamingSummary = ""
                }
            }
        }
    }

    private var multiSelectState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("\(selectedMemories.count) " + L("inspector.selected"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: 8) {
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
                    .background(Theme.Colors.elevated)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                ActionButton(icon: "star", title: "inspector.favorite_all") {
                    engine.update(ids: Array(selectedMemories)) { $0.isFavorite = true }
                    selectedMemories.removeAll()
                }
                ActionButton(icon: "star.slash", title: "inspector.unfavorite_all") {
                    engine.update(ids: Array(selectedMemories)) { $0.isFavorite = false }
                    selectedMemories.removeAll()
                }
                if AppState.shared.selection == .archive {
                    ActionButton(icon: "tray.and.arrow.up", title: "inspector.unarchive_all") {
                        engine.update(ids: Array(selectedMemories)) { $0.isArchived = false }
                        selectedMemories.removeAll()
                    }
                } else {
                    ActionButton(icon: "archivebox", title: "inspector.archive_all") {
                        engine.update(ids: Array(selectedMemories)) { $0.isArchived = true }
                        selectedMemories.removeAll()
                    }
                }
                ActionButton(icon: "trash", title: "inspector.delete_all", tint: Theme.Colors.danger) {
                    engine.delete(ids: selectedMemories)
                    selectedMemories.removeAll()
                }
                ActionButton(icon: "xmark.circle", title: "inspector.clear_selection") {
                    selectedMemories.removeAll()
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Moves every selected memory to `board` (nil = back to Inbox) and unarchives it.
    private func moveSelected(toBoard board: String?) {
        engine.update(ids: Array(selectedMemories)) { $0.board = board; $0.isArchived = false }
        selectedMemories.removeAll()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.righthalf.inset.filled")
                .font(.system(size: 22))
                .foregroundColor(Theme.Colors.textTertiary)
            Text("inspector.select_memory")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metaRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(LocalizedStringKey(title))
                .textCase(.uppercase)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Theme.Colors.textTertiary)
            content()
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
                HStack(spacing: 4) {
                    ForEach(memory.tags, id: \.self) { tag in
                        TagChip(text: tag) { removeTag(tag, from: memory) }
                    }
                }
            }
        }
        HStack(spacing: 7) {
            Image(systemName: "number")
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
            TextField(LocalizedStringKey("inspector.add_tag"), text: $newTag)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textPrimary)
                .onSubmit { addTag(to: memory) }
            Button(action: { addTag(to: memory) }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

struct ActionButton: View {
    let icon: String
    let title: String
    var tint: Color = Theme.Colors.textSecondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(isHovering ? tint.opacity(0.16) : Theme.Colors.elevated)
            .foregroundColor(isHovering ? tint : Theme.Colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

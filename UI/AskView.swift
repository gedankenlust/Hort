import SwiftUI

/// "Ask your memory" — a question box over your captures with a streamed,
/// source-cited answer from the local model. Fully local via Ollama.
struct AskView: View {
    @ObservedObject private var rag = RAGEngine.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: HortSpacing.lg) {
            header
            inputRow

            ScrollView {
                VStack(alignment: .leading, spacing: HortSpacing.lg) {
                    if let error = rag.errorMessage {
                        Text(error)
                            .font(HortTypography.primary(size: HortTypography.Size.caption))
                            .foregroundColor(HortColors.danger)
                    }

                    if rag.isAnswering && rag.answer.isEmpty {
                        HStack(spacing: HortSpacing.sm) {
                            ProgressView().controlSize(.small)
                            Text("ask.thinking")
                                .font(HortTypography.technical(size: HortTypography.Size.caption))
                                .foregroundColor(HortColors.textSecondary)
                        }
                    }

                    if !rag.answer.isEmpty {
                        answerBox
                    }

                    if !rag.sources.isEmpty {
                        sourcesSection
                    }

                    if rag.answer.isEmpty && rag.sources.isEmpty && !rag.isAnswering && rag.errorMessage == nil {
                        emptyHint
                    }
                }
                .padding(.bottom, HortSpacing.md)
            }
        }
        .padding(HortSpacing.xl)
        .frame(minWidth: 420, idealWidth: 560, maxWidth: .infinity,
               minHeight: 360, idealHeight: 640, maxHeight: .infinity)
        .background(HortColors.surface)
        .onAppear {
            inputFocused = true
            validateModel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(HortColors.accent)
            Text("ask.title")
                .font(HortTypography.technical(size: HortTypography.Size.headline))
                .foregroundColor(HortColors.accent)
            Spacer()
            HortIconButton(icon: "xmark", help: "common.cancel") { dismiss() }
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: HortSpacing.sm) {
            HortTextField(
                placeholder: "ask.placeholder",
                text: $rag.question,
                onSubmit: { rag.ask() },
                leadingIcon: "magnifyingglass",
                focus: Binding(get: { inputFocused }, set: { inputFocused = $0 })
            )

            HortIconButton(
                icon: "arrow.up",
                help: "ask.help",
                disabled: !canAsk
            ) { rag.ask() }
        }
    }

    private var canAsk: Bool {
        !rag.isAnswering && !rag.question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Answer

    private var answerBox: some View {
        Group {
            if let attributed = attributedAnswer(from: rag.answer) {
                Text(attributed)
            } else {
                Text(rag.answer)
                    .font(HortTypography.primary())
                    .lineSpacing(3)
                    .foregroundColor(HortColors.textPrimary)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HortSpacing.md)
        .background(HortColors.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                .strokeBorder(HortColors.accent.opacity(0.2), lineWidth: 1)
        )
    }

    private func attributedAnswer(from markdown: String) -> AttributedString? {
        guard !markdown.isEmpty else { return nil }

        // Try full Markdown first so paragraphs and lists render properly.
        do {
            return try AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .full),
                baseURL: nil
            )
        } catch {
            // Streaming answers may be incomplete; fall back to inline-only
            // formatting that at least preserves whitespace.
            do {
                return try AttributedString(
                    markdown: markdown,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
                    baseURL: nil
                )
            } catch {
                return plainAttributedAnswer(from: markdown)
            }
        }
    }

    private func plainAttributedAnswer(from text: String) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = HortTypography.primary()
        attributed.foregroundColor = HortColors.textPrimary
        return attributed
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: HortSpacing.sm) {
            HortSectionHeader(title: "ask.sources")

            ForEach(Array(rag.sources.enumerated()), id: \.element.id) { index, memory in
                Button(action: {
                    AppState.shared.reveal(memory.id)
                    dismiss()
                }) {
                    HortCard(isSelected: false, isHovering: false, cornerRadius: HortRadius.medium) {
                        HStack(alignment: .center, spacing: HortSpacing.sm) {
                            sourceThumbnail(memory)

                            VStack(alignment: .leading, spacing: HortSpacing.xs) {
                                HStack(spacing: HortSpacing.xs) {
                                    Image(systemName: iconName(for: memory.type))
                                        .font(.system(size: 10))
                                        .foregroundColor(HortColors.accent)

                                    if let app = memory.sourceApp, !app.isEmpty {
                                        Text(app)
                                            .font(HortTypography.technical(size: HortTypography.Size.caption))
                                            .foregroundColor(HortColors.textTertiary)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    Text(sourceDate(memory))
                                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                                        .foregroundColor(HortColors.textTertiary)
                                }

                                Text(sourceTitle(memory))
                                    .font(HortTypography.primary(size: HortTypography.Size.bodySmall))
                                    .foregroundColor(HortColors.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundColor(HortColors.textTertiary)
                        }
                        .padding(HortSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func sourceThumbnail(_ memory: MemoryObject) -> some View {
        if let path = imagePath(for: memory), let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous)
                    .fill(HortColors.accentSoft)
                    .frame(width: 44, height: 44)
                Image(systemName: iconName(for: memory.type))
                    .font(.system(size: 16))
                    .foregroundColor(HortColors.accent)
            }
        }
    }

    private func sourceTitle(_ memory: MemoryObject) -> String {
        if memory.type != .image, memory.type != .screenshot,
           let content = memory.content,
           let line = content.split(whereSeparator: \.isNewline).first, !line.isEmpty {
            return String(line.prefix(80))
        }
        if let ocr = memory.metadata["ocrText"], !ocr.isEmpty {
            return String(ocr.prefix(80))
        }
        return memory.type.rawValue.capitalized
    }

    private func sourceDate(_ memory: MemoryObject) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: memory.createdAt, relativeTo: Date())
    }

    private func imagePath(for memory: MemoryObject) -> String? {
        if let thumb = memory.thumbnailPath, FileManager.default.fileExists(atPath: thumb) {
            return thumb
        }
        if memory.type == .image || memory.type == .screenshot || memory.type == .file,
           let content = memory.content, FileManager.default.fileExists(atPath: content) {
            return content
        }
        return nil
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

    // MARK: - Empty hint

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: HortSpacing.sm) {
            Text("ask.hint_title")
                .font(HortTypography.label(size: HortTypography.Size.bodySmall))
                .foregroundColor(HortColors.textSecondary)
            Text("ask.hint_body")
                .font(HortTypography.primary(size: HortTypography.Size.caption))
                .foregroundColor(HortColors.textTertiary)
        }
        .padding(.top, HortSpacing.sm)
    }

    /// Mirrors SettingsView: if the configured generation model isn't installed,
    /// snap to the first available one so Ask works out of the box.
    private func validateModel() {
        Task {
            if let models = try? await OllamaClient.shared.fetchModels(),
               !models.isEmpty, !models.contains(settings.aiModel) {
                await MainActor.run { settings.aiModel = models.first! }
            }
        }
    }
}

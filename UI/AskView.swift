import SwiftUI

/// "Ask your memory" — a question box over your captures with a streamed,
/// source-cited answer from the local model. Fully local via Ollama.
struct AskView: View {
    @ObservedObject private var rag = RAGEngine.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            inputRow

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = rag.errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.danger)
                    }

                    if rag.isAnswering && rag.answer.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("ask.thinking")
                                .font(Theme.Fonts.technical(size: 11))
                                .foregroundColor(Theme.Colors.textSecondary)
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
                .padding(.bottom, 8)
            }
        }
        .padding(20)
        .frame(width: 560, height: 640)
        .background(Theme.Colors.surface)
        .onAppear {
            inputFocused = true
            validateModel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(Theme.Colors.accent)
            Text("ask.title")
                .font(Theme.Fonts.technical(size: 16))
                .foregroundColor(Theme.Colors.accent)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("ask.placeholder", text: $rag.question)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textPrimary)
                .focused($inputFocused)
                .onSubmit { rag.ask() }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: { rag.ask() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(canAsk ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(!canAsk)
        }
    }

    private var canAsk: Bool {
        !rag.isAnswering && !rag.question.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Answer

    private var answerBox: some View {
        Text(rag.answer)
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundColor(Theme.Colors.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.Colors.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.2), lineWidth: 1)
            )
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ask.sources")
                .font(Theme.Fonts.label(11, weight: .bold))
                .foregroundColor(Theme.Colors.textSecondary)

            ForEach(Array(rag.sources.enumerated()), id: \.element.id) { index, memory in
                Button(action: {
                    AppState.shared.reveal(memory.id)
                    dismiss()
                }) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(index + 1)]")
                            .font(.system(size: 11, weight: .semibold).monospaced())
                            .foregroundColor(Theme.Colors.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sourceTitle(memory))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let app = memory.sourceApp {
                                Text(app)
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.Colors.textTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.Colors.textTertiary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

    // MARK: - Empty hint

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ask.hint_title")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.textSecondary)
            Text("ask.hint_body")
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.top, 8)
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

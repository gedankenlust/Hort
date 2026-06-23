import Foundation
import Combine

/// Builds and maintains the local semantic index. Embeddings are computed one
/// at a time on a serial task chain (like AIRuntime) so a burst of captures or
/// a backfill can't flood Ollama. Publishes lightweight progress for the UI.
@MainActor
final class EmbeddingIndexer: ObservableObject {
    static let shared = EmbeddingIndexer()

    /// Number of memories waiting to be embedded (excludes the running one).
    @Published private(set) var pending = 0
    /// True while an embedding is being computed.
    @Published private(set) var isIndexing = false

    private var tail: Task<Void, Never> = Task {}

    private init() {}

    /// Queues a memory for embedding. No-op when semantic search is disabled.
    func enqueue(_ id: UUID) {
        guard SettingsStore.shared.semanticEnabled else { return }
        pending += 1
        let previous = tail
        tail = Task { [weak self] in
            await previous.value
            await self?.run(id)
        }
    }

    /// Embeds every memory that doesn't have a vector yet — pre-existing data,
    /// or captures made while semantic search was off. Safe to call on launch
    /// and whenever the user turns the feature on.
    func backfill() {
        guard SettingsStore.shared.semanticEnabled else { return }
        for id in MemoryEngine.shared.idsMissingEmbedding() {
            enqueue(id)
        }
    }

    private func run(_ id: UUID) async {
        pending -= 1
        isIndexing = true
        defer { isIndexing = false }

        guard let object = MemoryEngine.shared.fetch(id: id) else { return }
        let text = MemoryEngine.shared.embeddingText(for: object)
        guard !text.isEmpty else { return } // e.g. an image with no OCR yet

        do {
            let model = SettingsStore.shared.embeddingModel
            let vector = try await OllamaClient.shared.embed(text, model: model)
            MemoryEngine.shared.storeEmbedding(id: id, vector: vector, model: model)
        } catch {
            // Non-fatal: the row stays missing and is retried by the next
            // backfill (e.g. once Ollama is reachable again).
            print("Embedding failed for \(id): \(error)")
        }
    }
}

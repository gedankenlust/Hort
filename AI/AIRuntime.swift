import Foundation
import Combine

/// Coordinates background (Autopilot) AI analyses and exposes observable status
/// for the UI. All analyses run strictly one at a time so a burst of captures
/// can't spawn a stampede of concurrent 120s Ollama requests on the local box.
@MainActor
final class AIRuntime: ObservableObject {
    static let shared = AIRuntime()

    /// True while an Autopilot analysis is in flight.
    @Published private(set) var isAnalyzing = false
    /// Number of analyses waiting in the serial queue (excludes the running one).
    @Published private(set) var queuedCount = 0
    /// Whether the local Ollama instance was reachable at the last check.
    /// `nil` means "not checked yet".
    @Published private(set) var reachable: Bool?
    /// Human-readable description of the last Autopilot failure, if any.
    @Published private(set) var lastError: String?

    /// Tail of the serial task chain. Each enqueued job awaits the previous one,
    /// which guarantees at most one analysis runs at a time.
    private var tail: Task<Void, Never> = Task {}

    private init() {}

    /// Queues an Autopilot analysis for the given memory. Returns immediately;
    /// the work runs in order behind any analysis already queued or running.
    func enqueueAutopilot(objectID: UUID, content: String, model: String, imagePath: String? = nil) {
        guard !content.isEmpty || imagePath != nil else { return }
        queuedCount += 1
        let previous = tail
        tail = Task { [weak self] in
            await previous.value
            await self?.run(objectID: objectID, content: content, model: model, imagePath: imagePath)
        }
    }

    private func run(objectID: UUID, content: String, model: String, imagePath: String? = nil) async {
        queuedCount -= 1
        isAnalyzing = true
        defer { isAnalyzing = false }

        let handler: ((summary: String, tags: [String], done: Bool)) -> Void = { result in
            guard result.done else { return }
            DispatchQueue.main.async {
                MemoryEngine.shared.update(id: objectID) { mut in
                    mut.metadata["aiSummary"] = result.summary
                    for tag in result.tags where !mut.tags.contains(tag) {
                        mut.tags.append(tag)
                    }
                }
            }
        }

        do {
            if let path = imagePath, FileManager.default.fileExists(atPath: path) {
                try await OllamaClient.shared.analyzeImage(imagePath: path, model: model, onUpdate: handler)
            } else {
                try await OllamaClient.shared.analyze(content: content, model: model, onUpdate: handler)
            }
            reachable = true
            lastError = nil
            await reembed(objectID: objectID)
        } catch {
            reachable = false
            lastError = error.localizedDescription
            print("Autopilot AI analysis failed: \(error)")
        }
    }

    private func reembed(objectID: UUID) async {
        guard SettingsStore.shared.semanticEnabled,
              let object = MemoryEngine.shared.fetch(id: objectID) else { return }
        let text = MemoryEngine.shared.embeddingText(for: object)
        guard !text.isEmpty else { return }
        let embeddingModel = SettingsStore.shared.embeddingModel
        do {
            let vector = try await OllamaClient.shared.embed(text, model: embeddingModel)
            MemoryEngine.shared.storeEmbedding(id: objectID, vector: vector, model: embeddingModel)
        } catch {
            print("Re-embedding after analysis failed: \(error)")
        }
    }

    /// Pings the local Ollama instance and updates `reachable`. Cheap (3s
    /// fail-fast) and safe to call from `.onAppear`/timers.
    func refreshReachability() {
        Task { [weak self] in
            let online = (try? await OllamaClient.shared.fetchModels()) != nil
            self?.reachable = online
        }
    }
}

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
    func enqueueAutopilot(objectID: UUID, content: String, model: String) {
        guard !content.isEmpty else { return }
        queuedCount += 1
        let previous = tail
        tail = Task { [weak self] in
            await previous.value
            await self?.run(objectID: objectID, content: content, model: model)
        }
    }

    private func run(objectID: UUID, content: String, model: String) async {
        queuedCount -= 1
        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            try await OllamaClient.shared.analyze(content: content, model: model) { result in
                // Persist once, when streaming completes — mid-stream tags are
                // half-parsed and would leak fragments into the tag list.
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
            reachable = true
            lastError = nil
        } catch {
            reachable = false
            lastError = error.localizedDescription
            print("Autopilot AI analysis failed: \(error)")
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

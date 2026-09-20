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
    /// True while a board/folder organize pass is in flight (post-analyze or backfill).
    @Published private(set) var isOrganizing = false
    /// Organize-only jobs waiting in the serial queue (excludes the running one).
    @Published private(set) var organizePending = 0
    /// Items completed in the current backfill/tidy wave.
    @Published private(set) var organizeBatchDone = 0
    /// Total items enqueued for the current backfill/tidy wave (capped).
    @Published private(set) var organizeBatchTotal = 0
    /// Unfiled Inbox items left *outside* the current capped batch (honest remainder).
    @Published private(set) var organizeInboxOutstanding = 0
    /// User paused the organize backfill queue (current item may finish).
    @Published private(set) var isOrganizePaused = false
    /// Last privacy-safe organize result the UI can show.
    @Published private(set) var lastOrganizeOutcome: OrganizeOutcome?
    /// Whether the local Ollama instance was reachable at the last check.
    /// `nil` means "not checked yet".
    @Published private(set) var reachable: Bool?
    /// Human-readable description of the last Autopilot failure, if any.
    @Published private(set) var lastError: String?

    /// Tail of the serial task chain. Each enqueued job awaits the previous one,
    /// which guarantees at most one analysis / organize runs at a time.
    private var tail: Task<Void, Never> = Task {}
    /// IDs already waiting for an organize-only pass (dedupe backfill + tidy).
    private var organizeQueuedIDs = Set<UUID>()
    /// Bumped on cancel so already-chained organize tasks become no-ops.
    private var organizeGeneration = 0

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

    /// Queues classify→assign for an existing unfiled memory (Inbox backfill / tidy).
    /// Shares the same serial queue as analysis so a large Inbox can't stampede Ollama.
    /// Prefer organize-only: never re-runs full Autopilot analyze when `aiSummary` exists.
    /// Returns `true` when the id was newly queued.
    @discardableResult
    func enqueueOrganize(objectID: UUID) -> Bool {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return false }
        guard let object = MemoryEngine.shared.fetch(id: objectID),
              object.board == nil, !object.isArchived else { return false }
        guard !organizeQueuedIDs.contains(objectID) else { return false }

        let generation = organizeGeneration
        organizeQueuedIDs.insert(objectID)
        organizePending += 1
        let previous = tail
        tail = Task { [weak self] in
            await previous.value
            await self?.runOrganizeOnly(objectID: objectID, generation: generation)
        }
        return true
    }

    /// Enqueues a capped batch of Inbox items through organize. Call when the user
    /// turns Autopilot organize on, or taps "Tidy Inbox" / "Tidy more".
    /// Never dumps the entire Inbox into the Ollama queue in one go.
    func backfillOrganize() {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return }

        // Resume if the user hit Pause then Tidy again.
        isOrganizePaused = false

        let inbox = MemoryEngine.shared.fetchMemories(for: .inbox)
        let totalUnfiled = AutopilotOrganizer.unfiledInboxCount(from: inbox)
        let ids = AutopilotOrganizer.unfiledInboxIDs(
            from: inbox,
            limit: AutopilotOrganizer.maxBackfillBatch
        )
        let fresh = ids.filter { !organizeQueuedIDs.contains($0) }
        guard !fresh.isEmpty else {
            refreshOrganizeOutstanding()
            return
        }

        let startingFreshWave = !isOrganizeBusy
        var added = 0
        for id in fresh {
            if enqueueOrganize(objectID: id) { added += 1 }
        }
        guard added > 0 else {
            refreshOrganizeOutstanding()
            return
        }

        if startingFreshWave {
            organizeBatchTotal = added
            organizeBatchDone = 0
        } else {
            organizeBatchTotal += added
        }
        // Honest remainder: everything unfiled that is not part of this wave.
        organizeInboxOutstanding = max(0, totalUnfiled - organizeBatchTotal)
    }

    /// Pauses the organize backfill queue. The in-flight item may finish;
    /// further queued items wait until resume or cancel.
    func pauseOrganize() {
        guard isOrganizeBusy || organizePending > 0 else { return }
        isOrganizePaused = true
    }

    /// Resumes a paused organize backfill.
    func resumeOrganize() {
        isOrganizePaused = false
    }

    /// Cancels queued organize-only work. The in-flight classify may finish;
    /// everything else is dropped. Inbox remainder stays available for "Tidy more".
    func cancelOrganize() {
        organizeGeneration += 1
        organizeQueuedIDs.removeAll()
        organizePending = 0
        isOrganizePaused = false
        organizeBatchTotal = 0
        organizeBatchDone = 0
        refreshOrganizeOutstanding()
    }

    /// Live count of unfiled Inbox items (for idle "Tidy more" labels).
    func refreshOrganizeOutstanding() {
        let inbox = MemoryEngine.shared.fetchMemories(for: .inbox)
        let total = AutopilotOrganizer.unfiledInboxCount(from: inbox)
        if isOrganizeBusy {
            organizeInboxOutstanding = max(0, total - organizeRemaining)
        } else {
            organizeInboxOutstanding = total
        }
    }

    private func run(objectID: UUID, content: String, model: String, imagePath: String? = nil) async {
        queuedCount -= 1
        isAnalyzing = true
        defer { isAnalyzing = false }

        // Captured by the streaming callback; read only after `analyze` returns.
        let box = AnalysisResultBox()

        let handler: ((summary: String, tags: [String], done: Bool)) -> Void = { result in
            guard result.done else { return }
            box.summary = result.summary
            box.tags = result.tags
        }

        do {
            if let path = imagePath, FileManager.default.fileExists(atPath: path) {
                try await OllamaClient.shared.analyzeImage(imagePath: path, model: model, onUpdate: handler)
            } else {
                try await OllamaClient.shared.analyze(content: content, model: model, onUpdate: handler)
            }
            reachable = true
            lastError = nil

            let finalSummary = box.summary
            let finalTags = box.tags
            MemoryEngine.shared.update(id: objectID) { mut in
                if !finalSummary.isEmpty {
                    mut.metadata["aiSummary"] = finalSummary
                }
                for tag in finalTags where !mut.tags.contains(tag) {
                    mut.tags.append(tag)
                }
            }

            await reembed(objectID: objectID)
            await organizeIfEnabled(
                objectID: objectID,
                summary: finalSummary,
                tags: finalTags,
                content: content,
                model: model
            )
        } catch {
            reachable = false
            lastError = error.localizedDescription
            print("Autopilot AI analysis failed: \(error)")
        }
    }

    private func runOrganizeOnly(objectID: UUID, generation: Int) async {
        // Dropped by cancelOrganize — accounting already cleared.
        guard generation == organizeGeneration else { return }

        while isOrganizePaused && generation == organizeGeneration {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard generation == organizeGeneration else { return }

        organizePending = max(0, organizePending - 1)
        organizeQueuedIDs.remove(objectID)
        defer {
            if generation == organizeGeneration {
                organizeBatchDone += 1
                if organizePending == 0 && !isOrganizing {
                    isOrganizePaused = false
                    refreshOrganizeOutstanding()
                }
            }
        }

        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return }
        guard let object = MemoryEngine.shared.fetch(id: objectID) else { return }
        guard object.board == nil, !object.isArchived else {
            lastOrganizeOutcome = .alreadyFiled
            return
        }

        // Organize-only: reuse existing summary/tags — do not re-run full analyze.
        let summary = object.metadata["aiSummary"] ?? ""
        let tags = object.tags
        let content = object.content
            ?? object.metadata["ocrText"]
            ?? summary
        let model = settings.aiModel

        await organizeIfEnabled(
            objectID: objectID,
            summary: summary,
            tags: tags,
            content: content,
            model: model
        )

        // Thermal cool-down between capped backfill classify calls.
        if generation == organizeGeneration {
            try? await Task.sleep(nanoseconds: AutopilotOrganizer.organizeCooldownNanoseconds)
        }
    }

    /// Classifies the memory into a board/folder after analysis when the user
    /// has opted into Autopilot Organize. Never logs capture content.
    private func organizeIfEnabled(
        objectID: UUID,
        summary: String,
        tags: [String],
        content: String,
        model: String
    ) async {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return }

        // Skip if the user (or a prior pass) already filed this memory.
        guard let object = MemoryEngine.shared.fetch(id: objectID), object.board == nil else {
            lastOrganizeOutcome = .alreadyFiled
            return
        }

        let effectiveTags = tags.isEmpty ? object.tags : tags
        let effectiveSummary = summary.isEmpty ? (object.metadata["aiSummary"] ?? "") : summary
        let preview: String = {
            if !content.isEmpty { return content }
            if let ocr = object.metadata["ocrText"], !ocr.isEmpty { return ocr }
            return effectiveSummary
        }()

        isOrganizing = true
        defer { isOrganizing = false }

        do {
            guard let proposal = try await OllamaClient.shared.classifyOrganization(
                summary: effectiveSummary,
                tags: effectiveTags,
                contentPreview: preview,
                existingBoards: settings.boards,
                model: model
            ) else {
                lastOrganizeOutcome = .leftInbox
                #if DEBUG
                print("Autopilot organize: model left item in Inbox")
                #endif
                return
            }

            let inbox = MemoryEngine.shared.fetchMemories(for: .inbox)
                .filter { $0.id != objectID }
            let relatedIDs = AutopilotOrganizer.relatedInboxIDs(
                proposal: proposal,
                tags: effectiveTags,
                inbox: inbox
            )
            let decision = AutopilotOrganizer.decide(
                proposal: proposal,
                existingBoards: settings.boards,
                relatedInboxCount: relatedIDs.count
            )

            if decision.applied {
                let applied = AutopilotOrganizer.apply(
                    decision: decision,
                    to: objectID,
                    relatedInboxIDs: relatedIDs
                )
                if applied, let board = decision.board {
                    lastOrganizeOutcome = .filed(board: board, folder: decision.folder)
                    #if DEBUG
                    print("Autopilot organize: \(decision.reason) → \(board)/\(decision.folder ?? "-")")
                    #endif
                } else {
                    lastOrganizeOutcome = .alreadyFiled
                }
            } else if proposal.createBoard,
                      AutopilotOrganizer.isValidName(AutopilotOrganizer.normalizeName(proposal.board)),
                      proposal.confidence >= AutopilotOrganizer.minAssignConfidence {
                // Defer: remember the suggestion so a later related capture can
                // tip the related-count gate and create the board together.
                AutopilotOrganizer.rememberSuggestion(objectID: objectID, board: proposal.board)
                lastOrganizeOutcome = .deferred
                #if DEBUG
                print("Autopilot organize: deferred (\(decision.reason))")
                #endif
            } else {
                lastOrganizeOutcome = .skipped(reason: decision.reason)
                #if DEBUG
                print("Autopilot organize: skipped (\(decision.reason))")
                #endif
            }
            reachable = true
        } catch {
            lastOrganizeOutcome = .failed
            // Organize is best-effort — don't surface as a hard Autopilot failure
            // when analysis already succeeded.
            #if DEBUG
            print("Autopilot organize failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Running organize job + queued organize-only jobs (for progress labels).
    var organizeRemaining: Int {
        organizePending + (isOrganizing ? 1 : 0)
    }

    /// True while organize work is active or still queued (includes paused waits).
    var isOrganizeBusy: Bool {
        isOrganizing || organizePending > 0
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

/// Tiny mutable box so the streaming analyze callback can stash the final
/// summary/tags without fighting MainActor isolation on local vars.
private final class AnalysisResultBox: @unchecked Sendable {
    var summary = ""
    var tags: [String] = []
}

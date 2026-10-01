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
    /// Mac thermal pressure forced a pause (Ollama skipped until cooler).
    @Published private(set) var isOrganizeThermalPaused = false
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
    /// True when the user explicitly hit Pause (thermal auto-resume must not clear it).
    private var organizePausedByUser = false

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

    /// Enqueues a micro-batch for one Ollama classify prompt (or heuristic-only apply).
    @discardableResult
    private func enqueueOrganizeBatch(objectIDs: [UUID]) -> Int {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return 0 }

        let fresh = objectIDs.filter { id in
            guard !organizeQueuedIDs.contains(id) else { return false }
            guard let object = MemoryEngine.shared.fetch(id: id),
                  object.board == nil, !object.isArchived else { return false }
            return true
        }
        guard !fresh.isEmpty else { return 0 }

        let generation = organizeGeneration
        for id in fresh {
            organizeQueuedIDs.insert(id)
        }
        organizePending += fresh.count
        let previous = tail
        let batch = fresh
        tail = Task { [weak self] in
            await previous.value
            await self?.runOrganizeBatch(objectIDs: batch, generation: generation)
        }
        return fresh.count
    }

    /// Enqueues a capped batch of Inbox items through organize. Call when the user
    /// turns Autopilot organize on, or taps "Tidy Inbox" / "Tidy more".
    /// Files locally via heuristics first; only unmatched items hit Ollama (batched).
    func backfillOrganize() {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return }

        // Resume if the user hit Pause then Tidy again.
        organizePausedByUser = false
        isOrganizePaused = false
        isOrganizeThermalPaused = false

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
        if startingFreshWave {
            organizeBatchTotal = 0
            organizeBatchDone = 0
        }

        // Fast local pass: file anything we can without waking Ollama.
        var needsLLM: [UUID] = []
        var heuristicFiled = 0
        for id in fresh {
            if applyHeuristicOrganize(objectID: id) {
                heuristicFiled += 1
                organizeBatchDone += 1
            } else if let object = MemoryEngine.shared.fetch(id: id),
                      object.board == nil, !object.isArchived {
                needsLLM.append(id)
            } else {
                // Already filed / gone — still counts toward the wave.
                organizeBatchDone += 1
            }
        }
        organizeBatchTotal += heuristicFiled + needsLLM.count

        // Honest remainder: everything unfiled that is not part of this wave.
        let waveSize = heuristicFiled + needsLLM.count
        organizeInboxOutstanding = max(0, totalUnfiled - waveSize)

        guard !needsLLM.isEmpty else {
            refreshOrganizeOutstanding()
            return
        }

        // One Ollama prompt per micro-batch instead of N round-trips.
        var added = 0
        for chunk in AutopilotOrganizer.chunkIDs(needsLLM, size: AutopilotOrganizer.maxClassifyBatch) {
            added += enqueueOrganizeBatch(objectIDs: chunk)
        }
        if added == 0 {
            refreshOrganizeOutstanding()
        }
    }

    /// Pauses the organize backfill queue. The in-flight item may finish;
    /// further queued items wait until resume or cancel.
    func pauseOrganize() {
        guard isOrganizeBusy || organizePending > 0 else { return }
        organizePausedByUser = true
        isOrganizePaused = true
        isOrganizeThermalPaused = false
    }

    /// Resumes a paused organize backfill.
    func resumeOrganize() {
        organizePausedByUser = false
        isOrganizePaused = false
        isOrganizeThermalPaused = false
    }

    /// Cancels queued organize-only work. The in-flight classify may finish;
    /// everything else is dropped. Inbox remainder stays available for "Tidy more".
    func cancelOrganize() {
        organizeGeneration += 1
        organizeQueuedIDs.removeAll()
        organizePending = 0
        organizePausedByUser = false
        isOrganizePaused = false
        isOrganizeThermalPaused = false
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

        await waitWhileUserPaused(generation: generation)
        guard generation == organizeGeneration else { return }

        organizePending = max(0, organizePending - 1)
        organizeQueuedIDs.remove(objectID)
        defer {
            if generation == organizeGeneration {
                organizeBatchDone += 1
                if organizePending == 0 && !isOrganizing {
                    if !organizePausedByUser {
                        isOrganizePaused = false
                        isOrganizeThermalPaused = false
                    }
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

        let usedLLM = await organizeIfEnabled(
            objectID: objectID,
            summary: summary,
            tags: tags,
            content: content,
            model: model
        )

        // Thermal cool-down only after an actual Ollama classify.
        if usedLLM, generation == organizeGeneration {
            await sleepOrganizeCooldown()
        }
    }

    /// Processes a micro-batch: heuristics first, then one Ollama prompt for the rest.
    private func runOrganizeBatch(objectIDs: [UUID], generation: Int) async {
        guard generation == organizeGeneration else { return }

        await waitWhileUserPaused(generation: generation)
        guard generation == organizeGeneration else { return }

        let count = objectIDs.count
        organizePending = max(0, organizePending - count)
        for id in objectIDs {
            organizeQueuedIDs.remove(id)
        }
        defer {
            if generation == organizeGeneration {
                organizeBatchDone += count
                if organizePending == 0 && !isOrganizing {
                    if !organizePausedByUser {
                        isOrganizePaused = false
                        isOrganizeThermalPaused = false
                    }
                    refreshOrganizeOutstanding()
                }
            }
        }

        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return }

        var llmItems: [OrganizationBatchItem] = []
        for id in objectIDs {
            guard let object = MemoryEngine.shared.fetch(id: id),
                  object.board == nil, !object.isArchived else {
                lastOrganizeOutcome = .alreadyFiled
                continue
            }
            if applyHeuristicOrganize(objectID: id) {
                continue
            }
            let summary = object.metadata["aiSummary"] ?? ""
            let preview = object.content
                ?? object.metadata["ocrText"]
                ?? summary
            llmItems.append(OrganizationBatchItem(
                id: id,
                summary: summary,
                tags: object.tags,
                contentPreview: preview
            ))
        }

        guard !llmItems.isEmpty else { return }

        await waitForThermalClearance(generation: generation)
        guard generation == organizeGeneration else { return }

        isOrganizing = true
        var didCallLLM = false
        defer { isOrganizing = false }

        do {
            let proposals = try await OllamaClient.shared.classifyOrganizationBatch(
                items: llmItems,
                existingBoards: settings.boards,
                model: settings.aiModel
            )
            didCallLLM = true
            reachable = true

            for item in llmItems {
                guard generation == organizeGeneration else { return }
                guard let object = MemoryEngine.shared.fetch(id: item.id),
                      object.board == nil else {
                    lastOrganizeOutcome = .alreadyFiled
                    continue
                }
                applyOrganizeProposal(
                    proposals[item.id] ?? nil,
                    objectID: item.id,
                    tags: item.tags
                )
            }
        } catch {
            lastOrganizeOutcome = .failed
            #if DEBUG
            print("Autopilot organize batch failed: \(error.localizedDescription)")
            #endif
        }

        if didCallLLM, generation == organizeGeneration {
            await sleepOrganizeCooldown()
        }
    }

    /// Classifies the memory into a board/folder after analysis when the user
    /// has opted into Autopilot Organize. Never logs capture content.
    /// Returns `true` when an Ollama classify call ran (for cooldown accounting).
    @discardableResult
    private func organizeIfEnabled(
        objectID: UUID,
        summary: String,
        tags: [String],
        content: String,
        model: String
    ) async -> Bool {
        let settings = SettingsStore.shared
        guard settings.aiEnabled, settings.aiAutopilot, settings.aiAutopilotOrganize else { return false }

        // Skip if the user (or a prior pass) already filed this memory.
        guard let object = MemoryEngine.shared.fetch(id: objectID), object.board == nil else {
            lastOrganizeOutcome = .alreadyFiled
            return false
        }

        let effectiveTags = tags.isEmpty ? object.tags : tags
        let effectiveSummary = summary.isEmpty ? (object.metadata["aiSummary"] ?? "") : summary
        let preview: String = {
            if !content.isEmpty { return content }
            if let ocr = object.metadata["ocrText"], !ocr.isEmpty { return ocr }
            return effectiveSummary
        }()

        // Local-first: reuse tags / summary / deferred suggestion — no Ollama.
        if applyHeuristicOrganize(
            objectID: objectID,
            tags: effectiveTags,
            summary: effectiveSummary,
            suggestedBoard: object.metadata["autopilotSuggestedBoard"]
        ) {
            return false
        }

        await waitForThermalClearance(generation: organizeGeneration)
        guard MemoryEngine.shared.fetch(id: objectID)?.board == nil else {
            lastOrganizeOutcome = .alreadyFiled
            return false
        }

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
                return true
            }

            applyOrganizeProposal(proposal, objectID: objectID, tags: effectiveTags)
            reachable = true
            return true
        } catch {
            lastOrganizeOutcome = .failed
            // Organize is best-effort — don't surface as a hard Autopilot failure
            // when analysis already succeeded.
            #if DEBUG
            print("Autopilot organize failed: \(error.localizedDescription)")
            #endif
            return true
        }
    }

    /// Files via heuristics when possible. Returns `true` if the item was handled locally.
    @discardableResult
    private func applyHeuristicOrganize(
        objectID: UUID,
        tags: [String]? = nil,
        summary: String? = nil,
        suggestedBoard: String? = nil
    ) -> Bool {
        guard let object = MemoryEngine.shared.fetch(id: objectID),
              object.board == nil, !object.isArchived else {
            return false
        }
        let boards = SettingsStore.shared.boards
        let proposal = AutopilotOrganizer.heuristicProposal(
            tags: tags ?? object.tags,
            summary: summary ?? (object.metadata["aiSummary"] ?? ""),
            suggestedBoard: suggestedBoard ?? object.metadata["autopilotSuggestedBoard"],
            existingBoards: boards
        )
        guard let proposal else { return false }

        let decision = AutopilotOrganizer.decide(
            proposal: proposal,
            existingBoards: boards,
            relatedInboxCount: 0
        )
        guard decision.applied else { return false }

        let applied = AutopilotOrganizer.apply(decision: decision, to: objectID)
        if applied, let board = decision.board {
            lastOrganizeOutcome = .filed(board: board, folder: decision.folder)
            #if DEBUG
            print("Autopilot organize: heuristic (\(decision.reason)) → \(board)/\(decision.folder ?? "-")")
            #endif
            return true
        }
        return false
    }

    private func applyOrganizeProposal(
        _ proposal: OrganizationProposal?,
        objectID: UUID,
        tags: [String]
    ) {
        guard let proposal else {
            lastOrganizeOutcome = .leftInbox
            return
        }

        let inbox = MemoryEngine.shared.fetchMemories(for: .inbox)
            .filter { $0.id != objectID }
        let relatedIDs = AutopilotOrganizer.relatedInboxIDs(
            proposal: proposal,
            tags: tags,
            inbox: inbox
        )
        let decision = AutopilotOrganizer.decide(
            proposal: proposal,
            existingBoards: SettingsStore.shared.boards,
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
    }

    /// Waits only for an explicit user Pause (thermal pause uses its own loop).
    private func waitWhileUserPaused(generation: Int) async {
        while organizePausedByUser && generation == organizeGeneration {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Blocks organize LLM work while thermal state is serious/critical.
    private func waitForThermalClearance(generation: Int) async {
        while generation == organizeGeneration {
            // Honour an explicit user pause first.
            await waitWhileUserPaused(generation: generation)
            guard generation == organizeGeneration else { return }

            switch AutopilotOrganizer.thermalAction(for: ProcessInfo.processInfo.thermalState) {
            case .proceed:
                if isOrganizeThermalPaused && !organizePausedByUser {
                    isOrganizeThermalPaused = false
                    isOrganizePaused = false
                }
                return
            case .pauseForHeat:
                isOrganizeThermalPaused = true
                isOrganizePaused = true
                try? await Task.sleep(nanoseconds: AutopilotOrganizer.thermalPollNanoseconds)
            }
        }
    }

    private func sleepOrganizeCooldown() async {
        let ns: UInt64
        switch AutopilotOrganizer.thermalAction(for: ProcessInfo.processInfo.thermalState) {
        case .proceed(let cooldown):
            ns = cooldown
        case .pauseForHeat:
            ns = AutopilotOrganizer.organizeCooldownFairNanoseconds
        }
        try? await Task.sleep(nanoseconds: ns)
    }

    /// Running organize job + queued organize-only jobs (for progress labels).
    var organizeRemaining: Int {
        organizePending + (isOrganizing ? 1 : 0)
    }

    /// True while organize work is active or still queued (includes paused waits).
    var isOrganizeBusy: Bool {
        isOrganizing || organizePending > 0 || isOrganizeThermalPaused
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

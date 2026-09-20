import Foundation

/// A board/folder placement suggestion from the local model (or tests).
struct OrganizationProposal: Equatable {
    var board: String
    var folder: String?
    /// 0…1 model confidence. Below thresholds the proposal is ignored.
    var confidence: Double
    /// Model asks to create a board that isn't in the catalog yet.
    var createBoard: Bool
    /// Model asks to create a folder under the chosen board.
    var createFolder: Bool
}

/// Result of applying a proposal against the current board catalog + inbox.
struct OrganizationDecision: Equatable {
    /// Canonical board name to assign, or nil to leave the memory in Inbox.
    var board: String?
    var folder: String?
    var createdBoard: Bool
    var createdFolder: Bool
    var applied: Bool
    var reason: String
}

/// Privacy-safe outcome of one organize pass (no capture content).
enum OrganizeOutcome: Equatable {
    case filed(board: String, folder: String?)
    case leftInbox
    case deferred
    case skipped(reason: String)
    case alreadyFiled
    case failed
}

/// Pure organization logic: normalize names, reuse existing boards/folders,
/// and only create new ones when confidence and related-item gates pass.
/// Kept free of Ollama / UI so it can be unit-tested with fabricated proposals.
enum AutopilotOrganizer {
    /// Minimum confidence to assign to an *existing* board/folder.
    static let minAssignConfidence: Double = 0.65
    /// Minimum confidence to create a new folder under an existing board.
    static let minCreateFolderConfidence: Double = 0.75
    /// Minimum confidence to create an entirely new board.
    static let minCreateBoardConfidence: Double = 0.85
    /// How many other inbox items must look related before we mint a new board.
    static let minRelatedForNewBoard: Int = 1
    static let maxBoardNameLength = 40
    static let maxFolderNameLength = 40
    static let minNameLength = 2
    /// Hard cap per tidy/backfill wave — never enqueue the whole Inbox at once.
    static let maxBackfillBatch = 40
    /// Brief pause between organize Ollama calls to ease thermal load.
    static let organizeCooldownNanoseconds: UInt64 = 750_000_000

    /// Unfiled inbox candidates for organize backfill: `board == nil`, not archived.
    /// Stable oldest-first so related clusters tend to land before newer strays.
    /// When `limit` is set, only the oldest `limit` IDs are returned.
    static func unfiledInboxIDs(from memories: [MemoryObject], limit: Int? = nil) -> [UUID] {
        let ids = memories
            .filter { $0.board == nil && !$0.isArchived }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)
        guard let limit, limit >= 0 else { return ids }
        return Array(ids.prefix(limit))
    }

    /// Count of unfiled, non-archived inbox memories.
    static func unfiledInboxCount(from memories: [MemoryObject]) -> Int {
        memories.filter { $0.board == nil && !$0.isArchived }.count
    }

    /// Decides placement without mutating settings or memories.
    /// - Parameters:
    ///   - proposal: Model (or test) suggestion.
    ///   - existingBoards: Current catalog from SettingsStore.
    ///   - relatedInboxCount: Other unfiled memories that look related to this
    ///     proposal (tag/name overlap). Used to gate new-board creation so a
    ///     single stray clip doesn't spawn a junk board.
    static func decide(
        proposal: OrganizationProposal,
        existingBoards: [Board],
        relatedInboxCount: Int = 0
    ) -> OrganizationDecision {
        let boardName = normalizeName(proposal.board)
        let folderName = proposal.folder.map(normalizeName).flatMap { $0.isEmpty ? nil : $0 }

        guard proposal.confidence >= minAssignConfidence else {
            return .skip("confidence \(fmt(proposal.confidence)) below assign threshold")
        }
        guard isValidName(boardName) else {
            return .skip("invalid board name")
        }
        if let folderName, !isValidName(folderName) {
            return .skip("invalid folder name")
        }

        if let match = matchBoard(boardName, in: existingBoards) {
            return decideExistingBoard(
                matched: match,
                folderName: folderName,
                proposal: proposal,
                existingBoards: existingBoards
            )
        }

        // No existing board — only create when the model asked, confidence is
        // high, and at least one related inbox item already exists.
        guard proposal.createBoard else {
            return .skip("no matching board and create not requested")
        }
        guard proposal.confidence >= minCreateBoardConfidence else {
            return .skip("confidence \(fmt(proposal.confidence)) below create-board threshold")
        }
        guard relatedInboxCount >= minRelatedForNewBoard else {
            return .skip("need \(minRelatedForNewBoard)+ related inbox item(s) to create board")
        }

        var createdFolder = false
        var folder: String? = nil
        if let folderName, proposal.createFolder,
           proposal.confidence >= minCreateFolderConfidence {
            folder = folderName
            createdFolder = true
        }

        return OrganizationDecision(
            board: boardName,
            folder: folder,
            createdBoard: true,
            createdFolder: createdFolder,
            applied: true,
            reason: "create board"
        )
    }

    /// Applies a decision: creates board/folder in settings when needed, assigns
    /// the memory, and optionally files related inbox items onto a newly created
    /// board so the first related clips tidy up together.
    @discardableResult
    static func apply(
        decision: OrganizationDecision,
        to objectID: UUID,
        settings: SettingsStore = .shared,
        memory: MemoryEngine = .shared,
        relatedInboxIDs: [UUID] = []
    ) -> Bool {
        guard decision.applied, let board = decision.board else { return false }

        // Don't override a user (or prior) assignment.
        if let existing = memory.fetch(id: objectID), existing.board != nil {
            return false
        }

        if decision.createdBoard {
            settings.addBoard(board)
        }
        if let folder = decision.folder, decision.createdFolder || decision.createdBoard {
            settings.addFolder(to: board, folderName: folder)
        } else if let folder = decision.folder {
            // Ensure folder exists even when reusing (idempotent).
            settings.addFolder(to: board, folderName: folder)
        }

        // Resolve canonical casing from the catalog after create/reuse.
        let canonicalBoard = matchBoard(board, in: settings.boards)?.name ?? board
        let canonicalFolder: String? = {
            guard let folder = decision.folder,
                  let b = matchBoard(canonicalBoard, in: settings.boards) else { return decision.folder }
            return matchFolder(folder, in: b.folders) ?? folder
        }()

        memory.update(id: objectID) { mut in
            mut.board = canonicalBoard
            mut.folder = canonicalFolder
            mut.metadata["autopilotOrganized"] = "1"
        }

        // When we just minted a board for a cluster, file the related inbox
        // siblings onto the same board (folder left nil — they may not share
        // the same sub-topic).
        if decision.createdBoard, !relatedInboxIDs.isEmpty {
            let siblings = relatedInboxIDs.filter { $0 != objectID }
            memory.update(ids: siblings) { mut in
                guard mut.board == nil else { return }
                mut.board = canonicalBoard
                mut.metadata["autopilotOrganized"] = "1"
            }
        }

        return true
    }

    /// Counts how many of `inbox` look related to this proposal via shared tags
    /// or board-name overlap. Used as the "several related items" gate.
    static func relatedInboxCount(
        proposal: OrganizationProposal,
        tags: [String],
        inbox: [MemoryObject]
    ) -> Int {
        relatedInboxIDs(proposal: proposal, tags: tags, inbox: inbox).count
    }

    static func relatedInboxIDs(
        proposal: OrganizationProposal,
        tags: [String],
        inbox: [MemoryObject]
    ) -> [UUID] {
        let boardKey = normalizeKey(proposal.board)
        let tagSet = Set(tags.map { $0.lowercased() }.filter { !$0.isEmpty && !MemoryEngine.isJunkTag($0) })
        guard !boardKey.isEmpty || !tagSet.isEmpty else { return [] }

        return inbox.compactMap { item -> UUID? in
            guard item.board == nil, !item.isArchived else { return nil }
            let itemTags = Set(item.tags.map { $0.lowercased() }.filter { !MemoryEngine.isJunkTag($0) })
            let shared = itemTags.intersection(tagSet)
            if shared.count >= 2 { return item.id }
            // Single strong tag match that equals / contains the proposed board.
            if let strong = shared.first(where: { normalizeKey($0) == boardKey || boardKey.contains(normalizeKey($0)) || normalizeKey($0).contains(boardKey) }) {
                _ = strong
                return item.id
            }
            // Suggested board stored from a prior deferred organize pass.
            if let suggested = item.metadata["autopilotSuggestedBoard"],
               normalizeKey(suggested) == boardKey {
                return item.id
            }
            return nil
        }
    }

    /// Stores a deferred board suggestion when we refused to create yet —
    /// a later related capture can tip the related-count gate.
    static func rememberSuggestion(objectID: UUID, board: String, memory: MemoryEngine = .shared) {
        let name = normalizeName(board)
        guard isValidName(name) else { return }
        memory.update(id: objectID) { mut in
            mut.metadata["autopilotSuggestedBoard"] = name
        }
    }

    // MARK: - Matching / normalization

    static func normalizeName(_ raw: String) -> String {
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        // Title-case short names; leave mixed-case intact if already has caps.
        if collapsed == collapsed.lowercased() || collapsed == collapsed.uppercased() {
            return collapsed.lowercased().capitalized
        }
        return String(collapsed.prefix(maxBoardNameLength))
    }

    static func normalizeKey(_ raw: String) -> String {
        normalizeName(raw)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    static func isValidName(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= minNameLength, t.count <= maxBoardNameLength else { return false }
        if MemoryEngine.isJunkTag(t) { return false }
        // Reject pure punctuation / emoji-only labels.
        let alnum = t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return alnum.count >= minNameLength
    }

    static func matchBoard(_ name: String, in boards: [Board]) -> Board? {
        let key = normalizeKey(name)
        guard !key.isEmpty else { return nil }
        return boards.first { normalizeKey($0.name) == key }
    }

    static func matchFolder(_ name: String, in folders: [String]) -> String? {
        let key = normalizeKey(name)
        guard !key.isEmpty else { return nil }
        return folders.first { normalizeKey($0) == key }
    }

    // MARK: - Private

    private static func decideExistingBoard(
        matched: Board,
        folderName: String?,
        proposal: OrganizationProposal,
        existingBoards: [Board]
    ) -> OrganizationDecision {
        _ = existingBoards
        guard let folderName else {
            return OrganizationDecision(
                board: matched.name,
                folder: nil,
                createdBoard: false,
                createdFolder: false,
                applied: true,
                reason: "reuse board"
            )
        }

        if let existingFolder = matchFolder(folderName, in: matched.folders) {
            return OrganizationDecision(
                board: matched.name,
                folder: existingFolder,
                createdBoard: false,
                createdFolder: false,
                applied: true,
                reason: "reuse board+folder"
            )
        }

        if proposal.createFolder, proposal.confidence >= minCreateFolderConfidence {
            return OrganizationDecision(
                board: matched.name,
                folder: folderName,
                createdBoard: false,
                createdFolder: true,
                applied: true,
                reason: "reuse board, create folder"
            )
        }

        // Folder unknown and create not allowed — still file on the board.
        return OrganizationDecision(
            board: matched.name,
            folder: nil,
            createdBoard: false,
            createdFolder: false,
            applied: true,
            reason: "reuse board, skip unknown folder"
        )
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private extension OrganizationDecision {
    static func skip(_ reason: String) -> OrganizationDecision {
        OrganizationDecision(
            board: nil,
            folder: nil,
            createdBoard: false,
            createdFolder: false,
            applied: false,
            reason: reason
        )
    }
}

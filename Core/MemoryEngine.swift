import Foundation
import Combine
import GRDB

class MemoryEngine: ObservableObject {
    static let shared = MemoryEngine()

    private let dbQueue: DatabaseQueue
    private let fileSystem: FileSystemManager
    private let repository: MemoryRepository
    @Published var recentMemories: [MemoryObject] = []
    @Published var dataVersion: Int = 0

    /// In-memory cache of all stored embeddings so semantic search doesn't reload
    /// every vector from disk on each query. Guarded by `cacheLock` (read from
    /// background search tasks, written from the main-actor indexer).
    private var cachedEmbeddings: [(id: UUID, vector: [Float], model: String)]?
    private let cacheLock = NSLock()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.dbQueue = DatabaseManager.shared.dbQueue
        self.fileSystem = .shared
        self.repository = MemoryRepository(dbQueue: dbQueue)
        MemorySearchIndex.ensurePopulated(dbQueue: dbQueue)
        fetchRecent()
    }

    /// Internal initializer for dependency injection in tests.
    init(dbQueue: DatabaseQueue, fileSystem: FileSystemManager = .shared) {
        self.dbQueue = dbQueue
        self.fileSystem = fileSystem
        self.repository = MemoryRepository(dbQueue: dbQueue)
        MemorySearchIndex.ensurePopulated(dbQueue: dbQueue)
        fetchRecent()
    }

    func fetchRecent() {
        DispatchQueue.main.async {
            do {
                self.recentMemories = try self.dbQueue.read { db in
                    try MemoryObject
                        .order(Column("createdAt").desc)
                        .limit(50)
                        .fetchAll(db)
                }
            } catch {
                print("Error fetching memories: \(error)")
            }
            self.dataVersion &+= 1
        }
    }

    func fetchMemories(for selection: SidebarSelection) -> [MemoryObject] {
        do {
            return try repository.fetchMemories(for: selection)
        } catch {
            print("Error fetching memories for selection: \(error)")
            return []
        }
    }

    /// Inbox size without loading rows — for idle AI status polling.
    func countUnfiledInbox() -> Int {
        do {
            return try repository.countUnfiledInbox()
        } catch {
            print("Error counting unfiled inbox: \(error)")
            return 0
        }
    }

    func fetchSidebarData() -> (inbox: Int, all: Int, favorites: Int, archive: Int, boards: [String: Int], folders: [String: Int], tags: [String], tagCounts: [String: Int]) {
        do {
            return try repository.fetchSidebarData()
        } catch {
            print("Error fetching sidebar data: \(error)")
            return (0, 0, 0, 0, [:], [:], [], [:])
        }
    }

    func save(_ object: MemoryObject) {
        do {
            try repository.save(object)
            fetchRecent()
        } catch {
            print("Error saving memory: \(error)")
        }
    }

    /// Removes the DB row and search/vector indexes, but leaves asset files on
    /// disk so Undo can restore a visual card. Call `purgeAssociatedFiles`
    /// once the undo window closes without restore.
    func delete(_ object: MemoryObject) {
        delete(ids: [object.id])
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            try repository.delete(ids: ids)
            invalidateEmbeddingCache()
            fetchRecent()
        } catch {
            print("Error deleting memories: \(error)")
        }
    }

    /// Permanently removes asset + thumbnail files for a memory. Called after
    /// the undo toast expires or is dismissed — not during soft-delete.
    func purgeAssociatedFiles(for id: UUID) {
        let fm = FileManager.default
        let fileName = "\(id.uuidString).png"
        let assetURL = fileSystem.assetsURL.appendingPathComponent(fileName)
        let thumbURL = fileSystem.thumbnailsURL.appendingPathComponent(fileName)
        try? fm.removeItem(at: assetURL)
        try? fm.removeItem(at: thumbURL)
    }

    /// Files younger than this are never swept. A capture writes its image
    /// before saving the row, so without a grace period a sweep running at that
    /// exact moment could delete a perfectly good asset.
    static let orphanGracePeriod: TimeInterval = 600

    /// Deletes asset/thumbnail files that no longer have a memory row. Soft
    /// delete deliberately leaves files behind so Undo can restore a visual
    /// card; if the app quits during that window the row is gone for good and
    /// the files would otherwise linger forever. Called once at launch.
    func purgeOrphanedFiles(now: Date = Date()) {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Self.orphanGracePeriod)

        let knownIDs: Set<UUID>
        do {
            knownIDs = try dbQueue.read { db in Set(try MemoryObject.fetchAll(db).map(\.id)) }
        } catch {
            print("Error listing memories for orphan sweep: \(error)")
            return
        }

        for directory in [fileSystem.assetsURL, fileSystem.thumbnailsURL] {
            guard let files = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files {
                // Only sweep files we created ourselves ("<uuid>.png"); anything
                // else in the folder is left alone.
                guard file.pathExtension.lowercased() == "png",
                      let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !knownIDs.contains(id) else { continue }

                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                guard let modified, modified < cutoff else { continue }

                try? fm.removeItem(at: file)
            }
        }
    }

    func fetch(id: UUID) -> MemoryObject? {
        do {
            return try dbQueue.read { db in
                try MemoryObject.fetchOne(db, key: id)
            }
        } catch {
            print("Error fetching memory by ID: \(error)")
            return nil
        }
    }

    /// Reassigns every memory on `old` board to `new`. Used by board rename.
    func renameBoard(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return }
        do {
            try self.dbQueue.write { db in
                try db.execute(sql: "UPDATE memoryObject SET board = ? WHERE board = ?",
                               arguments: [trimmed, old])
            }
            fetchRecent()
        } catch {
            print("Error renaming board: \(error)")
        }
    }

    /// Moves every memory on `name` back to Inbox (clears board + folder).
    /// Used when a board is deleted so cards stay reachable.
    func clearBoard(_ name: String) {
        do {
            try self.dbQueue.write { db in
                try db.execute(sql: "UPDATE memoryObject SET board = NULL, folder = NULL WHERE board = ?",
                               arguments: [name])
            }
            fetchRecent()
        } catch {
            print("Error clearing board: \(error)")
        }
    }

    /// Clears the folder field for memories in `board`/`folder`, leaving them
    /// on the board. Used when a folder is deleted.
    func clearFolder(board: String, folder: String) {
        do {
            try self.dbQueue.write { db in
                try db.execute(sql: "UPDATE memoryObject SET folder = NULL WHERE board = ? AND folder = ?",
                               arguments: [board, folder])
            }
            fetchRecent()
        } catch {
            print("Error clearing folder: \(error)")
        }
    }

    /// Deletes every memory and clears the search index. Used by "Clear all".
    func deleteAll() {
        do {
            try self.dbQueue.write { db in
                try MemoryObject.deleteAll(db)
                try db.execute(sql: "DELETE FROM memorySearch")
                try db.execute(sql: "DELETE FROM memoryVector")
            }
            // Clear on-disk assets and thumbnails (they belong to memories).
            // Leave exports/ alone — those are files the user deliberately
            // generated, not raw memory data.
            let fm = FileManager.default
            if let assets = try? fm.contentsOfDirectory(at: fileSystem.assetsURL, includingPropertiesForKeys: nil) {
                assets.forEach { try? fm.removeItem(at: $0) }
            }
            if let thumbs = try? fm.contentsOfDirectory(at: fileSystem.thumbnailsURL, includingPropertiesForKeys: nil) {
                thumbs.forEach { try? fm.removeItem(at: $0) }
            }
            // Reclaim free pages so deleted clipboard text is less recoverable.
            // VACUUM cannot run inside a transaction.
            try? self.dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM")
            }
            invalidateEmbeddingCache()
            fetchRecent()
        } catch {
            print("Error clearing memories: \(error)")
        }
    }

    /// Clears only the local semantic vector index. Used when changing embedding models.
    func clearEmbeddings() {
        do {
            try self.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM memoryVector")
            }
            invalidateEmbeddingCache()
        } catch {
            print("Error clearing embeddings: \(error)")
        }
    }

    /// Persists a mutated copy of the object. `save` performs an upsert, so this
    /// covers favourite/archive/board changes without a dedicated update path.
    @discardableResult
    func update(_ object: MemoryObject, _ mutate: (inout MemoryObject) -> Void) -> MemoryObject {
        var copy = object
        mutate(&copy)
        copy.updatedAt = Date()
        save(copy)
        return copy
    }

    func update(id: UUID, _ mutate: (inout MemoryObject) -> Void) {
        do {
            try self.dbQueue.write { db in
                if var object = try MemoryObject.fetchOne(db, key: id) {
                    mutate(&object)
                    object.updatedAt = Date()
                    try object.save(db)
                    try MemorySearchIndex.index(object, in: db)
                }
            }
            fetchRecent()
        } catch {
            print("Error updating memory by ID: \(error)")
        }
    }

    /// Applies the same mutation to many memories in a single write + refresh.
    /// Used by bulk actions and multi-card drag so 23 moves aren't 23 refreshes.
    func update(ids: [UUID], _ mutate: (inout MemoryObject) -> Void) {
        guard !ids.isEmpty else { return }
        do {
            try self.dbQueue.write { db in
                for id in ids {
                    if var object = try MemoryObject.fetchOne(db, key: id) {
                        mutate(&object)
                        object.updatedAt = Date()
                        try object.save(db)
                        try MemorySearchIndex.index(object, in: db)
                    }
                }
            }
            fetchRecent()
        } catch {
            print("Error updating memories: \(error)")
        }
    }

    /// Renames a tag across all memories that have it.
    func renameTag(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != old else { return }
        do {
            try self.dbQueue.write { db in
                var all = try MemoryObject.fetchAll(db)
                for i in all.indices where all[i].tags.contains(old) {
                    all[i].tags = all[i].tags.map { $0 == old ? trimmed : $0 }
                    if Set(all[i].tags).count < all[i].tags.count {
                        all[i].tags = Array(NSOrderedSet(array: all[i].tags)) as? [String] ?? all[i].tags
                    }
                    all[i].updatedAt = Date()
                    try all[i].save(db)
                    try MemorySearchIndex.index(all[i], in: db)
                }
            }
            fetchRecent()
        } catch {
            print("Error renaming tag: \(error)")
        }
    }

    /// Removes a tag from every memory that has it.
    func deleteTag(_ tag: String) {
        do {
            try self.dbQueue.write { db in
                var all = try MemoryObject.fetchAll(db)
                for i in all.indices where all[i].tags.contains(tag) {
                    all[i].tags.removeAll { $0 == tag }
                    all[i].updatedAt = Date()
                    try all[i].save(db)
                    try MemorySearchIndex.index(all[i], in: db)
                }
            }
            fetchRecent()
        } catch {
            print("Error deleting tag: \(error)")
        }
    }

    /// Forwards to `TagPolicy` so existing call sites keep compiling.
    static func isJunkTag(_ tag: String) -> Bool {
        TagPolicy.isJunkTag(tag)
    }

    // MARK: - Search

    /// Full-text search over the FTS5 index. Returns matches in rank order.
    /// By default archived items are excluded; pass `includeArchived: true`
    /// when searching from the Archive section.
    /// Matching is done in Swift against the UUID string because MemoryObject
    /// ids are persisted as blobs, which don't join cleanly to the text
    /// `memoryId` column in the FTS table.
    func keywordSearch(_ query: String, includeArchived: Bool = false) -> [MemoryObject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\"\"")
        let pattern = "\"\(escaped)\"*" // treat input as a prefix phrase query

        do {
            return try self.dbQueue.read { db in
                let matchedIDs = try String.fetchAll(db, sql: """
                    SELECT memoryId FROM memorySearch
                    WHERE memorySearch MATCH ? ORDER BY rank
                    """, arguments: [pattern])
                guard !matchedIDs.isEmpty else { return [] }

                let rank = Dictionary(uniqueKeysWithValues: matchedIDs.enumerated().map { ($1, $0) })
                let uuids = matchedIDs.compactMap { UUID(uuidString: $0) }
                let allMatched = try MemoryObject.fetchAll(db, keys: uuids)
                
                return allMatched
                    .filter { includeArchived ? $0.isArchived : !$0.isArchived }
                    .sorted { (rank[$0.id.uuidString] ?? 0) < (rank[$1.id.uuidString] ?? 0) }
            }
        } catch {
            print("Search error: \(error)")
            return []
        }
    }

    /// Hybrid search: keyword (FTS5) fused with semantic (embeddings) via
    /// reciprocal rank fusion. Degrades to keyword-only when semantic search is
    /// off or Ollama can't produce an embedding, so search never breaks.
    func search(_ query: String, includeArchived: Bool = false) async -> [MemoryObject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let keyword = keywordSearch(trimmed, includeArchived: includeArchived)

        guard SettingsStore.shared.semanticEnabled,
              let semanticIDs = await semanticSearch(trimmed), !semanticIDs.isEmpty else {
            return keyword
        }

        let fusedIDs = VectorMath.reciprocalRankFusion([keyword.map(\.id), semanticIDs])
        let rank = Dictionary(uniqueKeysWithValues: fusedIDs.enumerated().map { ($1, $0) })

        do {
            return try await dbQueue.read { db in
                try MemoryObject.fetchAll(db, keys: fusedIDs)
                    .filter { includeArchived ? $0.isArchived : !$0.isArchived }
                    .sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
            }
        } catch {
            print("Hybrid search error: \(error)")
            return keyword
        }
    }

    /// Top matches for a query used by Ask/RAG. Prefers semantic retrieval when
    /// available; falls back to keyword search so Ask still works when embeddings
    /// are off, incomplete, or Ollama can't embed.
    func retrieve(for query: String, limit: Int = 6) async -> [MemoryObject] {
        if SettingsStore.shared.semanticEnabled,
           let ids = await semanticSearch(query, limit: limit), !ids.isEmpty {
            let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
            do {
                let semantic = try await dbQueue.read { db in
                    try MemoryObject.fetchAll(db, keys: ids)
                        .filter { !$0.isArchived }
                        .sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
                }
                if !semantic.isEmpty { return Array(semantic.prefix(limit)) }
            } catch {
                print("Retrieve error: \(error)")
            }
        }
        return Array(keywordSearch(query).prefix(limit))
    }

    /// Ranks memory ids by cosine similarity to the query's embedding. Returns
    /// nil when no embedding can be produced (e.g. Ollama unreachable), which
    /// signals the caller to fall back to keyword-only results.
    private func semanticSearch(_ query: String, limit: Int = 50) async -> [UUID]? {
        let model = SettingsStore.shared.embeddingModel
        guard let queryVector = try? await OllamaClient.shared.embed(query, model: model) else {
            return nil
        }
        let normalizedQuery = VectorMath.normalize(queryVector)
        // Only compare vectors of the same dimensionality as the query — after an
        // embedding-model switch the index may briefly hold mixed dimensions
        // until the rebuild completes.
        let dim = normalizedQuery.count
        // Same dim AND same model — mixed embedding models must not fuse.
        let all = allEmbeddings().filter { $0.vector.count == dim && $0.model == model }
        guard !all.isEmpty else { return nil }

        return all
            .map { (id: $0.id, score: VectorMath.dot(normalizedQuery, $0.vector)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.id)
    }


    // MARK: - Semantic index

    /// The text fed to the embedding model for a memory: its content, plus OCR
    /// text and an AI summary when present, plus tags — capped so very long
    /// captures stay within the model's context.
    func embeddingText(for object: MemoryObject) -> String {
        var parts: [String] = []
        if object.type != .image, object.type != .screenshot,
           let content = object.content, !content.isEmpty {
            parts.append(content)
        }
        if let ocr = object.metadata["ocrText"], !ocr.isEmpty { parts.append(ocr) }
        if let summary = object.metadata["aiSummary"], !summary.isEmpty { parts.append(summary) }
        if !object.tags.isEmpty { parts.append(object.tags.joined(separator: " ")) }
        return String(parts.joined(separator: "\n").prefix(2000))
    }

    /// Stores (or replaces) the normalized embedding for a memory.
    func storeEmbedding(id: UUID, vector: [Float], model: String) {
        let normalized = VectorMath.normalize(vector)
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO memoryVector (memoryId, embedding, model, dims, updatedAt)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(memoryId) DO UPDATE SET
                        embedding = excluded.embedding,
                        model = excluded.model,
                        dims = excluded.dims,
                        updatedAt = excluded.updatedAt
                    """, arguments: [id.uuidString, normalized.blob, model, normalized.count, Date()])
            }
            invalidateEmbeddingCache()
        } catch {
            print("Error storing embedding: \(error)")
        }
    }

    /// Ids that need (re)embedding: missing vector, wrong model, or memory
    /// updated after the vector was written (e.g. AI summary/tags arrived).
    /// Computed in Swift rather than a SQL join: MemoryObject.id is a UUID blob,
    /// while memoryVector.memoryId is the uuid string.
    func idsMissingEmbedding(currentModel: String = SettingsStore.shared.embeddingModel) -> [UUID] {
        do {
            return try dbQueue.read { db in
                let objects = try MemoryObject.fetchAll(db)
                let rows = try Row.fetchAll(db, sql: "SELECT memoryId, model, updatedAt FROM memoryVector")
                var byID: [UUID: (model: String, updatedAt: Date)] = [:]
                for row in rows {
                    guard let idString: String = row["memoryId"],
                          let id = UUID(uuidString: idString),
                          let model: String = row["model"],
                          let updatedAt: Date = row["updatedAt"] else { continue }
                    byID[id] = (model, updatedAt)
                }
                return objects.compactMap { object in
                    guard let existing = byID[object.id] else { return object.id }
                    if existing.model != currentModel { return object.id }
                    if object.updatedAt > existing.updatedAt { return object.id }
                    return nil
                }
            }
        } catch {
            print("Error listing missing embeddings: \(error)")
            return []
        }
    }

    /// Loads every stored embedding (already normalized) for in-memory search,
    /// caching the result so repeated searches don't re-read the table.
    func allEmbeddings() -> [(id: UUID, vector: [Float], model: String)] {
        cacheLock.lock()
        if let cached = cachedEmbeddings {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let loaded: [(id: UUID, vector: [Float], model: String)]
        do {
            loaded = try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT memoryId, embedding, model FROM memoryVector")
                return rows.compactMap { row in
                    guard let idString: String = row["memoryId"],
                          let id = UUID(uuidString: idString),
                          let blob: Data = row["embedding"],
                          let model: String = row["model"] else { return nil }
                    return (id, [Float](blob: blob), model)
                }
            }
        } catch {
            print("Error loading embeddings: \(error)")
            return []
        }

        cacheLock.lock()
        cachedEmbeddings = loaded
        cacheLock.unlock()
        return loaded
    }

    /// Drops the cached vectors so the next search reloads them. Called whenever
    /// the vector table changes.
    private func invalidateEmbeddingCache() {
        cacheLock.lock()
        cachedEmbeddings = nil
        cacheLock.unlock()
    }
}

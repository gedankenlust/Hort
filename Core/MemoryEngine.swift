import Foundation
import Combine
import GRDB

class MemoryEngine: ObservableObject {
    static let shared = MemoryEngine()

    private let dbQueue: DatabaseQueue
    @Published var recentMemories: [MemoryObject] = []
    @Published var dataVersion: Int = 0

    /// In-memory cache of all stored embeddings so semantic search doesn't reload
    /// every vector from disk on each query. Guarded by `cacheLock` (read from
    /// background search tasks, written from the main-actor indexer).
    private var cachedEmbeddings: [(id: UUID, vector: [Float])]?
    private let cacheLock = NSLock()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.dbQueue = DatabaseManager.shared.dbQueue
        rebuildSearchIndex()
        fetchRecent()
    }

    /// Internal initializer for dependency injection in tests.
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        rebuildSearchIndex()
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
            return try dbQueue.read { db in
                switch selection {
                case .inbox:
                    return try MemoryObject.filter(sql: "isArchived = 0 AND board IS NULL")
                        .order(Column("createdAt").desc).fetchAll(db)
                case .all:
                    return try MemoryObject.filter(sql: "isArchived = 0")
                        .order(Column("createdAt").desc).fetchAll(db)
                case .favorites:
                    return try MemoryObject.filter(sql: "isArchived = 0 AND isFavorite = 1")
                        .order(Column("createdAt").desc).fetchAll(db)
                case .archive:
                    return try MemoryObject.filter(sql: "isArchived = 1")
                        .order(Column("createdAt").desc).fetchAll(db)
                case .board(let name):
                    return try MemoryObject.filter(sql: "isArchived = 0 AND board = ?", arguments: [name])
                        .order(Column("createdAt").desc).fetchAll(db)
                case .folder(let board, let folder):
                    return try MemoryObject.filter(sql: "isArchived = 0 AND board = ? AND folder = ?", arguments: [board, folder])
                        .order(Column("createdAt").desc).fetchAll(db)
                case .tag(let name):
                    let allNotArchived = try MemoryObject.filter(sql: "isArchived = 0")
                        .order(Column("createdAt").desc).fetchAll(db)
                    return allNotArchived.filter { $0.tags.contains(name) }
                }
            }
        } catch {
            print("Error fetching memories for selection: \(error)")
            return []
        }
    }

    func fetchSidebarData() -> (inbox: Int, all: Int, favorites: Int, archive: Int, boards: [String: Int], folders: [String: Int], tags: [String]) {
        do {
            return try dbQueue.read { db in
                let inbox = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memoryObject WHERE isArchived = 0 AND board IS NULL") ?? 0
                let all = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memoryObject WHERE isArchived = 0") ?? 0
                let favorites = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memoryObject WHERE isArchived = 0 AND isFavorite = 1") ?? 0
                let archive = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memoryObject WHERE isArchived = 1") ?? 0
                
                let rows = try Row.fetchAll(db, sql: "SELECT board, folder, tags FROM memoryObject WHERE isArchived = 0")
                var boardCounts: [String: Int] = [:]
                var folderCounts: [String: Int] = [:]
                
                var tagCounts: [String: Int] = [:]
                for row in rows {
                    if let board: String = row["board"] {
                        boardCounts[board, default: 0] += 1
                        if let folder: String = row["folder"] {
                            let key = "\(board)||\(folder)"
                            folderCounts[key, default: 0] += 1
                        }
                    }
                    if let tagsJSON: String = row["tags"], let data = tagsJSON.data(using: .utf8), let tags = try? JSONDecoder().decode([String].self, from: data) {
                        for tag in tags { tagCounts[tag, default: 0] += 1 }
                    }
                }
                let filtered = tagCounts
                    .filter { $0.value >= 2 && !Self.isJunkTag($0.key) }
                    .map(\.key)
                    .sorted()
                return (inbox, all, favorites, archive, boardCounts, folderCounts, filtered)
            }
        } catch {
            print("Error fetching sidebar data: \(error)")
            return (0, 0, 0, 0, [:], [:], [])
        }
    }

    func save(_ object: MemoryObject) {
        do {
            try self.dbQueue.write { db in
                try object.save(db)
                try indexObject(object, in: db)
            }
            fetchRecent()
        } catch {
            print("Error saving memory: \(error)")
        }
    }

    func delete(_ object: MemoryObject) {
        do {
            _ = try self.dbQueue.write { db in
                try object.delete(db)
                try deindex(object.id, in: db)
                try deindexVector(object.id, in: db)
            }
            deleteAssociatedFiles(for: object.id)
            invalidateEmbeddingCache()
            fetchRecent()
        } catch {
            print("Error deleting memory: \(error)")
        }
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            _ = try self.dbQueue.write { db in
                for id in ids {
                    try MemoryObject.deleteOne(db, key: id)
                    try deindex(id, in: db)
                    try deindexVector(id, in: db)
                }
            }
            for id in ids {
                deleteAssociatedFiles(for: id)
            }
            invalidateEmbeddingCache()
            fetchRecent()
        } catch {
            print("Error deleting memories: \(error)")
        }
    }

    private func deleteAssociatedFiles(for id: UUID) {
        let fm = FileManager.default
        let fileName = "\(id.uuidString).png"
        let assetURL = FileSystemManager.shared.assetsURL.appendingPathComponent(fileName)
        let thumbURL = FileSystemManager.shared.thumbnailsURL.appendingPathComponent(fileName)
        try? fm.removeItem(at: assetURL)
        try? fm.removeItem(at: thumbURL)
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
            if let assets = try? fm.contentsOfDirectory(at: FileSystemManager.shared.assetsURL, includingPropertiesForKeys: nil) {
                assets.forEach { try? fm.removeItem(at: $0) }
            }
            if let thumbs = try? fm.contentsOfDirectory(at: FileSystemManager.shared.thumbnailsURL, includingPropertiesForKeys: nil) {
                thumbs.forEach { try? fm.removeItem(at: $0) }
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
                    try self.indexObject(object, in: db)
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
                        try self.indexObject(object, in: db)
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
                }
            }
            fetchRecent()
        } catch {
            print("Error deleting tag: \(error)")
        }
    }

    /// Tags that are purely numeric, date-like, single characters, or
    /// measurement units are noise from AI analysis and clutter the sidebar.
    /// Number+short-suffix tags that are meaningful keywords, not units/codes,
    /// and should survive the junk filter below.
    private static let numericTagWhitelist: Set<String> = [
        "3d", "4k", "8k", "2fa", "5g", "4g", "3g", "1080p", "720p", "2d", "3ds", "ios", "y2k",
    ]

    static func isJunkTag(_ tag: String) -> Bool {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 1 { return true }
        if numericTagWhitelist.contains(t.lowercased()) { return false }
        if Double(t) != nil { return true }
        let junkPatterns = [
            #"^\d{1,4}[./-]\d{1,2}([./-]\d{2,4})?$"#,  // dates
            #"^\d+(\.\d+)?\s?[a-z]{1,3}$"#,            // number + short unit suffix (250ml, 12b, 10kg, 30px)
            #"^\d{4}$"#,                                 // bare years
        ]
        for pattern in junkPatterns {
            if t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        }
        return false
    }

    // MARK: - Search

    /// Full-text search over the FTS5 index. Returns non-archived matches in
    /// rank order. Matching is done in Swift against the UUID string because
    /// MemoryObject ids are persisted as blobs, which don't join cleanly to the
    /// text `memoryId` column in the FTS table.
    func keywordSearch(_ query: String) -> [MemoryObject] {
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
                    .filter { !$0.isArchived }
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
    func search(_ query: String) async -> [MemoryObject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let keyword = keywordSearch(trimmed)

        guard SettingsStore.shared.semanticEnabled,
              let semanticIDs = await semanticSearch(trimmed), !semanticIDs.isEmpty else {
            return keyword
        }

        let fusedIDs = VectorMath.reciprocalRankFusion([keyword.map(\.id), semanticIDs])
        let rank = Dictionary(uniqueKeysWithValues: fusedIDs.enumerated().map { ($1, $0) })

        do {
            return try await dbQueue.read { db in
                try MemoryObject.fetchAll(db, keys: fusedIDs)
                    .filter { !$0.isArchived }
                    .sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
            }
        } catch {
            print("Hybrid search error: \(error)")
            return keyword
        }
    }

    /// Top semantic matches (non-archived) for a query, for RAG retrieval.
    /// Empty when semantic search is off, Ollama is down, or nothing is indexed.
    func retrieve(for query: String, limit: Int = 6) async -> [MemoryObject] {
        guard SettingsStore.shared.semanticEnabled,
              let ids = await semanticSearch(query, limit: limit), !ids.isEmpty else {
            return []
        }
        let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        do {
            return try await dbQueue.read { db in
                try MemoryObject.fetchAll(db, keys: ids)
                    .filter { !$0.isArchived }
                    .sorted { (rank[$0.id] ?? Int.max) < (rank[$1.id] ?? Int.max) }
            }
        } catch {
            print("Retrieve error: \(error)")
            return []
        }
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
        let all = allEmbeddings().filter { $0.vector.count == dim } // already normalized
        guard !all.isEmpty else { return nil }

        return all
            .map { (id: $0.id, score: VectorMath.dot(normalizedQuery, $0.vector)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.id)
    }

    /// Rebuilds the FTS index from scratch. The index table is recreated empty
    /// on every launch (see DatabaseManager), so this repopulates it.
    private func rebuildSearchIndex() {
        do {
            try self.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM memorySearch")
                let all = try MemoryObject.fetchAll(db)
                for object in all {
                    try indexObject(object, in: db)
                }
            }
        } catch {
            print("Error rebuilding search index: \(error)")
        }
    }

    private func indexObject(_ object: MemoryObject, in db: Database) throws {
        try deindex(object.id, in: db)
        var searchContent = object.content ?? ""
        if (object.type == .image || object.type == .screenshot), let ocr = object.metadata["ocrText"] {
            searchContent = ocr
        }
        try db.execute(sql: """
            INSERT INTO memorySearch (memoryId, content, preview, sourceApp, tags)
            VALUES (?, ?, ?, ?, ?)
            """, arguments: [
                object.id.uuidString,
                searchContent,
                object.preview,
                object.sourceApp,
                object.tags.joined(separator: " ")
            ])
    }

    private func deindex(_ id: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM memorySearch WHERE memoryId = ?", arguments: [id.uuidString])
    }

    private func deindexVector(_ id: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM memoryVector WHERE memoryId = ?", arguments: [id.uuidString])
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

    /// Ids of memories that don't yet have an embedding. Computed as a set
    /// difference in Swift rather than a SQL join: MemoryObject.id is stored by
    /// GRDB as a 16-byte UUID blob, while memoryVector.memoryId is the uuid
    /// string, so the two don't compare directly in SQL.
    func idsMissingEmbedding() -> [UUID] {
        do {
            return try dbQueue.read { db in
                let allIDs = try MemoryObject.fetchAll(db).map(\.id)
                let indexed = try String.fetchAll(db, sql: "SELECT memoryId FROM memoryVector")
                let have = Set(indexed.compactMap(UUID.init(uuidString:)))
                return allIDs.filter { !have.contains($0) }
            }
        } catch {
            print("Error listing missing embeddings: \(error)")
            return []
        }
    }

    /// Loads every stored embedding (already normalized) for in-memory search,
    /// caching the result so repeated searches don't re-read the table.
    func allEmbeddings() -> [(id: UUID, vector: [Float])] {
        cacheLock.lock()
        if let cached = cachedEmbeddings {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let loaded: [(id: UUID, vector: [Float])]
        do {
            loaded = try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT memoryId, embedding FROM memoryVector")
                return rows.compactMap { row in
                    guard let idString: String = row["memoryId"],
                          let id = UUID(uuidString: idString),
                          let blob: Data = row["embedding"] else { return nil }
                    return (id, [Float](blob: blob))
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

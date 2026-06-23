import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    
    var dbQueue: DatabaseQueue
    
    init(inMemory: Bool = false) {
        dbQueue = DatabaseManager.makeQueue(inMemory: inMemory)
        do {
            try setupSchema()
        } catch {
            // The on-disk database is unusable (e.g. corrupt or a schema clash).
            // Fall back to a fresh in-memory store so the session stays usable
            // instead of crashing; data just won't persist until the file is
            // repaired or removed.
            print("❌ Schema setup failed: \(error). Falling back to in-memory database.")
            dbQueue = DatabaseManager.makeInMemoryQueue()
            try? setupSchema()
        }
    }

    /// Opens the on-disk queue, degrading to in-memory if the disk store can't
    /// be created (missing permissions, full disk, …) rather than crashing.
    private static func makeQueue(inMemory: Bool) -> DatabaseQueue {
        if !inMemory {
            do {
                let fileManager = FileManager.default
                let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let dbFolderURL = appSupportURL
                    .appendingPathComponent("Hort", isDirectory: true)
                    .appendingPathComponent("database", isDirectory: true)

                if !fileManager.fileExists(atPath: dbFolderURL.path) {
                    try fileManager.createDirectory(at: dbFolderURL, withIntermediateDirectories: true)
                }

                let dbURL = dbFolderURL.appendingPathComponent("hort.sqlite")
                return try DatabaseQueue(path: dbURL.path)
            } catch {
                print("❌ Failed to open on-disk database: \(error). Falling back to in-memory.")
            }
        }
        return makeInMemoryQueue()
    }

    /// Last-resort in-memory queue. An in-memory SQLite database only fails to
    /// open under genuine resource exhaustion, in which case the app cannot
    /// function at all — so a clearly-labelled crash is the honest outcome.
    private static func makeInMemoryQueue() -> DatabaseQueue {
        do {
            return try DatabaseQueue()
        } catch {
            fatalError("Hort could not create an in-memory database: \(error)")
        }
    }

    static func makeInMemory() -> DatabaseManager {
        return DatabaseManager(inMemory: true)
    }
    
    private func setupSchema() throws {
        try dbQueue.write { db in
            try db.create(table: "memoryObject", options: [.ifNotExists]) { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("sourceApp", .text)
                t.column("sourceWindow", .text)
                t.column("content", .text)
                t.column("preview", .text)
                t.column("thumbnailPath", .text)
                t.column("board", .text)
                t.column("folder", .text)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("isArchived", .boolean).notNull().defaults(to: false)
                t.column("securityLevel", .integer).notNull().defaults(to: 0)
                t.column("version", .integer).notNull().defaults(to: 1)
                // Collection fields persisted as JSON text by GRDB.
                t.column("attachments", .text)
                t.column("tags", .text)
                t.column("metadata", .text)
                t.column("relatedObjectIDs", .text)
            }

            // Backfill the collection columns for databases created by older
            // builds that predate them. ADD COLUMN keeps existing data and
            // avoids a full DatabaseMigrator at this early stage.
            let existing = try Set(db.columns(in: "memoryObject").map(\.name))
            for column in ["attachments", "tags", "metadata", "relatedObjectIDs"] where !existing.contains(column) {
                try db.execute(sql: "ALTER TABLE memoryObject ADD COLUMN \(column) TEXT")
            }

            // FTS5 search index, rebuilt as a standalone (non external-content)
            // table. The previous external-content config pointed content_rowid
            // at the TEXT `id` column, which FTS5 cannot use as a rowid. The
            // index is currently unused, so dropping it loses nothing.
            try db.execute(sql: "DROP TABLE IF EXISTS memorySearch")
            try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS memorySearch USING fts5(memoryId UNINDEXED, content, preview, sourceApp, tags)")

            // Local semantic index: one normalized embedding per memory. Unlike
            // the FTS table this is expensive to regenerate (one model call per
            // row), so it persists across launches and is only backfilled for
            // rows that are missing a vector.
            try db.create(table: "memoryVector", options: [.ifNotExists]) { t in
                t.column("memoryId", .text).primaryKey()
                t.column("embedding", .blob).notNull()
                t.column("model", .text).notNull()
                t.column("dims", .integer).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
    }
}

// Mark MemoryObject for GRDB persistence
extension MemoryObject: FetchableRecord, PersistableRecord {
    static let databaseTableName = "memoryObject"
}

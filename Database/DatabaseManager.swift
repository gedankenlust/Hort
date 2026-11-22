import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()
    
    var dbQueue: DatabaseQueue
    /// True when the session is on a temporary in-memory store (disk open or
    /// schema setup failed). Captures will not survive quit.
    private(set) var isUsingEphemeralStore = false
    
    init(inMemory: Bool = false) {
        if inMemory {
            isUsingEphemeralStore = true
            dbQueue = DatabaseManager.makeInMemoryQueue()
            try? migrate()
            return
        }
        let opened = DatabaseManager.openOnDiskQueue()
        dbQueue = opened.queue
        isUsingEphemeralStore = opened.ephemeral
        do {
            try migrate()
        } catch {
            // The on-disk database is unusable (e.g. corrupt or a schema clash).
            // Fall back to a fresh in-memory store so the session stays usable
            // instead of crashing — but flag it so the UI can warn the user.
            print("❌ Schema setup failed: \(error). Falling back to in-memory database.")
            dbQueue = DatabaseManager.makeInMemoryQueue()
            isUsingEphemeralStore = true
            try? migrate()
        }
    }

    /// Opens the on-disk queue, or an in-memory one if the disk store can't
    /// be created (missing permissions, full disk, …).
    private static func openOnDiskQueue() -> (queue: DatabaseQueue, ephemeral: Bool) {
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
            // Restrict directory permissions so other local users can't browse captures.
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dbFolderURL.path)
            var config = Configuration()
            config.prepareDatabase { db in
                // Overwrite deleted page contents instead of leaving clipboard
                // text in free pages until a VACUUM.
                try db.execute(sql: "PRAGMA secure_delete = ON")
            }
            return (try DatabaseQueue(path: dbURL.path, configuration: config), false)
        } catch {
            print("❌ Failed to open on-disk database: \(error). Falling back to in-memory.")
            return (makeInMemoryQueue(), true)
        }
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

    /// Versioned schema migrations. Existing installs without a migrator history
    /// still work: v1 uses ifNotExists / additive ALTER so re-running is safe.
    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_baseline") { db in
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
                t.column("attachments", .text)
                t.column("tags", .text)
                t.column("metadata", .text)
                t.column("relatedObjectIDs", .text)
            }

            let existing = try Set(db.columns(in: "memoryObject").map(\.name))
            for column in ["attachments", "tags", "metadata", "relatedObjectIDs"] where !existing.contains(column) {
                try db.execute(sql: "ALTER TABLE memoryObject ADD COLUMN \(column) TEXT")
            }

            // Persistent FTS5 index — no longer dropped on every launch.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memorySearch
                USING fts5(memoryId UNINDEXED, content, preview, sourceApp, tags)
                """)

            try db.create(table: "memoryVector", options: [.ifNotExists]) { t in
                t.column("memoryId", .text).primaryKey()
                t.column("embedding", .blob).notNull()
                t.column("model", .text).notNull()
                t.column("dims", .integer).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "memoryObject_createdAt", on: "memoryObject", columns: ["createdAt"], ifNotExists: true)
            try db.create(index: "memoryObject_isArchived", on: "memoryObject", columns: ["isArchived"], ifNotExists: true)
            try db.create(index: "memoryObject_board", on: "memoryObject", columns: ["board"], ifNotExists: true)
            try db.create(index: "memoryObject_isFavorite", on: "memoryObject", columns: ["isFavorite"], ifNotExists: true)
        }

        try migrator.migrate(dbQueue)
    }
}

// Mark MemoryObject for GRDB persistence
extension MemoryObject: FetchableRecord, PersistableRecord {
    static let databaseTableName = "memoryObject"
}

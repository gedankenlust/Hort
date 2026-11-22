import Foundation
import GRDB

/// FTS5 + vector deindex helpers. Owned by `MemoryEngine` but separated so
/// indexing policy can evolve without growing the facade further.
enum MemorySearchIndex {
    static func ensurePopulated(dbQueue: DatabaseQueue) {
        do {
            let needsRebuild = try dbQueue.read { db -> Bool in
                let memories = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memoryObject") ?? 0
                guard memories > 0 else { return false }
                let indexed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memorySearch") ?? 0
                return indexed == 0
            }
            if needsRebuild {
                rebuild(dbQueue: dbQueue)
            }
        } catch {
            print("Error checking search index: \(error)")
            rebuild(dbQueue: dbQueue)
        }
    }

    static func rebuild(dbQueue: DatabaseQueue) {
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM memorySearch")
                let all = try MemoryObject.fetchAll(db)
                for object in all {
                    try index(object, in: db)
                }
            }
        } catch {
            print("Error rebuilding search index: \(error)")
        }
    }

    static func index(_ object: MemoryObject, in db: Database) throws {
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

    static func deindex(_ id: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM memorySearch WHERE memoryId = ?", arguments: [id.uuidString])
    }

    static func deindexVector(_ id: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM memoryVector WHERE memoryId = ?", arguments: [id.uuidString])
    }
}

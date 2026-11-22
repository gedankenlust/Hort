import Foundation
import GRDB

/// CRUD and selection queries for `MemoryObject`. `MemoryEngine` remains the
/// Observable facade and owns refresh/cache side effects.
struct MemoryRepository {
    let dbQueue: DatabaseQueue

    /// Cheap COUNT for the Ollama indicator poll — never materialize inbox rows.
    func countUnfiledInbox() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM memoryObject WHERE isArchived = 0 AND board IS NULL"
            ) ?? 0
        }
    }

    func fetchMemories(for selection: SidebarSelection) throws -> [MemoryObject] {
        try dbQueue.read { db in
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
    }

    func fetchSidebarData() throws -> (inbox: Int, all: Int, favorites: Int, archive: Int, boards: [String: Int], folders: [String: Int], tags: [String], tagCounts: [String: Int]) {
        try dbQueue.read { db in
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
                if let tagsJSON: String = row["tags"],
                   let data = tagsJSON.data(using: .utf8),
                   let tags = try? JSONDecoder().decode([String].self, from: data) {
                    for tag in tags { tagCounts[tag, default: 0] += 1 }
                }
            }
            let filtered = tagCounts
                .filter { $0.value >= 2 && !TagPolicy.isJunkTag($0.key) }
                .map(\.key)
                .sorted()
            return (inbox, all, favorites, archive, boardCounts, folderCounts, filtered, tagCounts)
        }
    }

    func save(_ object: MemoryObject) throws {
        try dbQueue.write { db in
            try object.save(db)
            try MemorySearchIndex.index(object, in: db)
        }
    }

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                try MemoryObject.deleteOne(db, key: id)
                try MemorySearchIndex.deindex(id, in: db)
                try MemorySearchIndex.deindexVector(id, in: db)
            }
        }
    }
}

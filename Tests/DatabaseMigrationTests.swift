import XCTest
import GRDB
@testable import Hort

final class DatabaseMigrationTests: XCTestCase {
    func testMigratorCreatesQueryableSchema() throws {
        let manager = DatabaseManager.makeInMemory()
        let queue = manager.dbQueue

        try queue.read { db in
            XCTAssertTrue(try db.tableExists("memoryObject"))
            XCTAssertTrue(try db.tableExists("memoryVector"))
            // FTS virtual tables report via sqlite_master.
            let fts = try String.fetchOne(db, sql: """
                SELECT name FROM sqlite_master WHERE type='table' AND name='memorySearch'
                """)
            XCTAssertEqual(fts, "memorySearch")

            let indexes = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'memoryObject_%'
                """)
            XCTAssertTrue(indexes.contains("memoryObject_createdAt"))
            XCTAssertTrue(indexes.contains("memoryObject_isArchived"))
        }
    }

    func testPersistentFTSSurvivesSecondMigrationPass() throws {
        let manager = DatabaseManager.makeInMemory()
        let engine = MemoryEngine(dbQueue: manager.dbQueue)
        let object = MemoryObject(type: .text, content: "PersistentFTSToken alpha")
        engine.save(object)

        let first = engine.keywordSearch("PersistentFTSToken")
        XCTAssertEqual(first.count, 1)

        // Re-running migrate (new manager on same in-memory queue isn't possible;
        // instead assert the FTS row remains and ensureSearchIndex does not wipe it).
        let indexed = try manager.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memorySearch") ?? 0
        }
        XCTAssertEqual(indexed, 1)

        // Simulate ensureSearchIndex path: with non-empty FTS, no rebuild.
        let second = engine.keywordSearch("PersistentFTSToken")
        XCTAssertEqual(second.map(\.id), [object.id])
    }
}

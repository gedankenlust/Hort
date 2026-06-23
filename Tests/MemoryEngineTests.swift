import XCTest
@testable import Hort

final class MemoryEngineTests: XCTestCase {
    var dbManager: DatabaseManager!
    var engine: MemoryEngine!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dbManager = DatabaseManager.makeInMemory()
        engine = MemoryEngine(dbQueue: dbManager.dbQueue)
    }

    override func tearDownWithError() throws {
        engine = nil
        dbManager = nil
        try super.tearDownWithError()
    }

    func testSaveAndFetchMemory() throws {
        let textObj = MemoryObject(type: .text, content: "Test Memory Content")
        engine.save(textObj)

        let memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.content, "Test Memory Content")
        XCTAssertEqual(memories.first?.type, .text)
    }

    func testDeleteMemory() throws {
        let textObj = MemoryObject(type: .text, content: "Delete Me")
        engine.save(textObj)

        var memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 1)

        engine.delete(textObj)

        memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 0)
    }

    func testDeleteAssociatedFiles() throws {
        let id = UUID()
        let fm = FileManager.default
        let fileName = "\(id.uuidString).png"
        let assetURL = FileSystemManager.shared.assetsURL.appendingPathComponent(fileName)
        let thumbURL = FileSystemManager.shared.thumbnailsURL.appendingPathComponent(fileName)
        
        // Write dummy files
        try "dummy-asset".data(using: .utf8)?.write(to: assetURL)
        try "dummy-thumb".data(using: .utf8)?.write(to: thumbURL)
        
        XCTAssertTrue(fm.fileExists(atPath: assetURL.path))
        XCTAssertTrue(fm.fileExists(atPath: thumbURL.path))
        
        let imgObj = MemoryObject(id: id, type: .image, content: assetURL.path)
        engine.save(imgObj)
        
        engine.delete(imgObj)
        
        XCTAssertFalse(fm.fileExists(atPath: assetURL.path))
        XCTAssertFalse(fm.fileExists(atPath: thumbURL.path))
    }

    func testRenameBoard() throws {
        var obj1 = MemoryObject(type: .text, content: "Board Item 1")
        obj1.board = "OldBoard"
        engine.save(obj1)

        var obj2 = MemoryObject(type: .text, content: "Board Item 2")
        obj2.board = "AnotherBoard"
        engine.save(obj2)

        var memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 2)

        engine.renameBoard("OldBoard", to: "NewBoard")

        memories = engine.fetchMemories(for: .all)

        let oldBoardCount = memories.filter { $0.board == "OldBoard" }.count
        let newBoardCount = memories.filter { $0.board == "NewBoard" }.count
        let unchangedCount = memories.filter { $0.board == "AnotherBoard" }.count

        XCTAssertEqual(oldBoardCount, 0)
        XCTAssertEqual(newBoardCount, 1)
        XCTAssertEqual(unchangedCount, 1)
    }

    func testDeleteAll() throws {
        let obj1 = MemoryObject(type: .text, content: "Item 1")
        let obj2 = MemoryObject(type: .text, content: "Item 2")
        engine.save(obj1)
        engine.save(obj2)

        var memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 2)

        engine.deleteAll()

        memories = engine.fetchMemories(for: .all)
        XCTAssertEqual(memories.count, 0)
    }

    func testFTS5Search() throws {
        var obj1 = MemoryObject(type: .text, content: "Special Agent Antigravity is coding")
        obj1.tags = ["swift", "test"]
        let obj2 = MemoryObject(type: .text, content: "Ordinary text content")
        
        engine.save(obj1)
        engine.save(obj2)

        // Search for word in content
        let results1 = engine.keywordSearch("Antigravity")
        XCTAssertEqual(results1.count, 1)
        XCTAssertEqual(results1.first?.id, obj1.id)

        // Search for tag
        let results2 = engine.keywordSearch("swift")
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(results2.first?.id, obj1.id)

        // Search for something that doesn't exist
        let results3 = engine.keywordSearch("unknown-word")
        XCTAssertEqual(results3.count, 0)
    }

    func testFTS5SearchOCR() throws {
        var imageObj = MemoryObject(type: .image, content: "/path/to/image.png")
        imageObj.metadata["ocrText"] = "This is recognized text from a screenshot with Swift Vision"
        
        engine.save(imageObj)
        
        // Search for word in OCR text
        let results = engine.keywordSearch("Vision")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, imageObj.id)
    }

    func testClearEmbeddings() throws {
        let textObj = MemoryObject(type: .text, content: "Test data")
        engine.save(textObj)
        
        let vector: [Float] = [1.0, 0.0, 0.0] // Must normalize to non-zero
        engine.storeEmbedding(id: textObj.id, vector: vector, model: "test-model")
        
        var missing = engine.idsMissingEmbedding()
        XCTAssertFalse(missing.contains(textObj.id))
        
        engine.clearEmbeddings()
        
        let allVecs = engine.allEmbeddings()
        XCTAssertTrue(allVecs.isEmpty)
        
        missing = engine.idsMissingEmbedding()
        XCTAssertTrue(missing.contains(textObj.id))
    }
}

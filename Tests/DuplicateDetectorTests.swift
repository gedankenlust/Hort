import XCTest
@testable import Hort

final class DuplicateDetectorTests: XCTestCase {

    func testTextDuplicatesNormalizeWhitespace() {
        var a = MemoryObject(type: .text, content: "hello  world")
        a.createdAt = Date(timeIntervalSince1970: 100)
        var b = MemoryObject(type: .text, content: " hello world ")
        b.createdAt = Date(timeIntervalSince1970: 200)
        var unique = MemoryObject(type: .text, content: "other")
        unique.createdAt = Date(timeIntervalSince1970: 300)

        let plan = DuplicateDetector.selectionPlan(in: [a, b, unique], policy: .newest)
        XCTAssertEqual(plan.groupCount, 1)
        XCTAssertEqual(plan.keeperCount, 1)
        XCTAssertEqual(plan.duplicateCount, 1)
        XCTAssertEqual(plan.duplicateIDs, [a.id], "oldest extra selected; newest kept")
        XCTAssertFalse(plan.duplicateIDs.contains(b.id))
        XCTAssertFalse(plan.duplicateIDs.contains(unique.id))
    }

    func testURLDuplicatesIgnoreTrailingSlashAndCase() {
        var a = MemoryObject(type: .url, content: "https://Example.com/path/")
        a.createdAt = Date(timeIntervalSince1970: 1)
        var b = MemoryObject(type: .url, content: "https://example.com/path")
        b.createdAt = Date(timeIntervalSince1970: 2)

        let groups = DuplicateDetector.findGroups(in: [a, b], policy: .newest)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].keeperID, b.id)
        XCTAssertEqual(groups[0].duplicateIDs, [a.id])
    }

    func testDifferentTypesDoNotCollide() {
        let text = MemoryObject(type: .text, content: "https://example.com")
        let url = MemoryObject(type: .url, content: "https://example.com")
        let plan = DuplicateDetector.selectionPlan(in: [text, url])
        XCTAssertFalse(plan.hasDuplicates)
    }

    func testImageDuplicatesMatchFileContentHash() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HortDup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bytes = Data("same-png-bytes".utf8)
        let pathA = dir.appendingPathComponent("a.png")
        let pathB = dir.appendingPathComponent("b.png")
        try bytes.write(to: pathA)
        try bytes.write(to: pathB)

        var a = MemoryObject(type: .image, content: pathA.path)
        a.createdAt = Date(timeIntervalSince1970: 10)
        var b = MemoryObject(type: .image, content: pathB.path)
        b.createdAt = Date(timeIntervalSince1970: 20)

        let plan = DuplicateDetector.selectionPlan(in: [a, b], policy: .oldest)
        XCTAssertEqual(plan.duplicateCount, 1)
        XCTAssertEqual(plan.duplicateIDs, [b.id], "newest is the extra when keeping oldest")
    }

    func testKeepOldestPolicy() {
        var a = MemoryObject(type: .text, content: "same")
        a.createdAt = Date(timeIntervalSince1970: 1)
        var b = MemoryObject(type: .text, content: "same")
        b.createdAt = Date(timeIntervalSince1970: 2)
        var c = MemoryObject(type: .text, content: "same")
        c.createdAt = Date(timeIntervalSince1970: 3)

        let groups = DuplicateDetector.findGroups(in: [a, b, c], policy: .oldest)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].keeperID, a.id)
        XCTAssertEqual(Set(groups[0].duplicateIDs), [b.id, c.id])
    }

    func testEmptyContentSkipped() {
        let empty = MemoryObject(type: .text, content: "   ")
        let also = MemoryObject(type: .text, content: "")
        XCTAssertNil(DuplicateDetector.fingerprint(for: empty))
        XCTAssertNil(DuplicateDetector.fingerprint(for: also))
        XCTAssertFalse(DuplicateDetector.selectionPlan(in: [empty, also]).hasDuplicates)
    }
}

import XCTest
@testable import Hort

final class AutopilotOrganizerTests: XCTestCase {

    // MARK: - Normalization

    func testNormalizeNameCollapsesWhitespaceAndTitleCases() {
        XCTAssertEqual(AutopilotOrganizer.normalizeName("  recipes  book "), "Recipes Book")
        XCTAssertEqual(AutopilotOrganizer.normalizeName("RECIPES"), "Recipes")
    }

    func testNormalizeKeyIgnoresPunctuationAndCase() {
        XCTAssertEqual(
            AutopilotOrganizer.normalizeKey("Work / Projects!"),
            AutopilotOrganizer.normalizeKey("work-projects")
        )
    }

    func testRejectsJunkNames() {
        XCTAssertFalse(AutopilotOrganizer.isValidName(""))
        XCTAssertFalse(AutopilotOrganizer.isValidName("a"))
        XCTAssertFalse(AutopilotOrganizer.isValidName("42"))
        XCTAssertFalse(AutopilotOrganizer.isValidName("!!!"))
        XCTAssertTrue(AutopilotOrganizer.isValidName("Recipes"))
        XCTAssertTrue(AutopilotOrganizer.isValidName("AI"))
    }

    // MARK: - Reuse existing boards

    func testReusesExistingBoardCaseInsensitively() {
        let boards = [Board(name: "Recipes", folders: ["Baking"])]
        let proposal = OrganizationProposal(
            board: "recipes",
            folder: "baking",
            confidence: 0.9,
            createBoard: false,
            createFolder: false
        )
        let decision = AutopilotOrganizer.decide(proposal: proposal, existingBoards: boards)
        XCTAssertTrue(decision.applied)
        XCTAssertEqual(decision.board, "Recipes")
        XCTAssertEqual(decision.folder, "Baking")
        XCTAssertFalse(decision.createdBoard)
        XCTAssertFalse(decision.createdFolder)
    }

    func testCreatesFolderUnderExistingBoardWhenAllowed() {
        let boards = [Board(name: "Work", folders: [])]
        let proposal = OrganizationProposal(
            board: "Work",
            folder: "Design Reviews",
            confidence: 0.8,
            createBoard: false,
            createFolder: true
        )
        let decision = AutopilotOrganizer.decide(proposal: proposal, existingBoards: boards)
        XCTAssertTrue(decision.applied)
        XCTAssertEqual(decision.board, "Work")
        XCTAssertEqual(decision.folder, "Design Reviews")
        XCTAssertTrue(decision.createdFolder)
    }

    func testSkipsUnknownFolderWhenCreateNotAllowed() {
        let boards = [Board(name: "Work", folders: ["Eng"])]
        let proposal = OrganizationProposal(
            board: "Work",
            folder: "Mystery",
            confidence: 0.9,
            createBoard: false,
            createFolder: false
        )
        let decision = AutopilotOrganizer.decide(proposal: proposal, existingBoards: boards)
        XCTAssertTrue(decision.applied)
        XCTAssertEqual(decision.board, "Work")
        XCTAssertNil(decision.folder)
    }

    // MARK: - Confidence / create gates

    func testLowConfidenceLeavesInbox() {
        let boards = [Board(name: "Recipes")]
        let proposal = OrganizationProposal(
            board: "Recipes",
            folder: nil,
            confidence: 0.4,
            createBoard: false,
            createFolder: false
        )
        let decision = AutopilotOrganizer.decide(proposal: proposal, existingBoards: boards)
        XCTAssertFalse(decision.applied)
        XCTAssertNil(decision.board)
    }

    func testDoesNotCreateBoardWithoutRelatedItems() {
        let proposal = OrganizationProposal(
            board: "Travel Japan",
            folder: nil,
            confidence: 0.95,
            createBoard: true,
            createFolder: false
        )
        let decision = AutopilotOrganizer.decide(
            proposal: proposal,
            existingBoards: [],
            relatedInboxCount: 0
        )
        XCTAssertFalse(decision.applied)
        XCTAssertTrue(decision.reason.contains("related"))
    }

    func testCreatesBoardWhenRelatedItemsExist() {
        let proposal = OrganizationProposal(
            board: "Travel Japan",
            folder: "Kyoto",
            confidence: 0.92,
            createBoard: true,
            createFolder: true
        )
        let decision = AutopilotOrganizer.decide(
            proposal: proposal,
            existingBoards: [],
            relatedInboxCount: 1
        )
        XCTAssertTrue(decision.applied)
        XCTAssertEqual(decision.board, "Travel Japan")
        XCTAssertEqual(decision.folder, "Kyoto")
        XCTAssertTrue(decision.createdBoard)
        XCTAssertTrue(decision.createdFolder)
    }

    func testRelatedInboxDetectsSharedTagsAndSuggestions() {
        var a = MemoryObject(type: .text, content: "ramen recipe")
        a.tags = ["japan", "food", "travel"]

        var b = MemoryObject(type: .text, content: "tokyo tips")
        b.metadata["autopilotSuggestedBoard"] = "Travel Japan"

        var filed = MemoryObject(type: .text, content: "already filed")
        filed.board = "Elsewhere"
        filed.tags = ["japan", "food", "travel"]

        let proposal = OrganizationProposal(
            board: "Travel Japan",
            folder: nil,
            confidence: 0.9,
            createBoard: true,
            createFolder: false
        )
        let ids = AutopilotOrganizer.relatedInboxIDs(
            proposal: proposal,
            tags: ["japan", "food", "travel"],
            inbox: [a, b, filed]
        )
        XCTAssertEqual(Set(ids), Set([a.id, b.id]))
    }

    // MARK: - Inbox backfill candidates

    func testUnfiledInboxIDsSkipsFiledAndArchivedAndOrdersOldestFirst() {
        var older = MemoryObject(type: .text, content: "old")
        older.createdAt = Date(timeIntervalSince1970: 100)

        var newer = MemoryObject(type: .text, content: "new")
        newer.createdAt = Date(timeIntervalSince1970: 200)

        var filed = MemoryObject(type: .text, content: "filed")
        filed.board = "Recipes"
        filed.createdAt = Date(timeIntervalSince1970: 50)

        var archived = MemoryObject(type: .text, content: "archived")
        archived.isArchived = true
        archived.createdAt = Date(timeIntervalSince1970: 10)

        let ids = AutopilotOrganizer.unfiledInboxIDs(from: [newer, archived, older, filed])
        XCTAssertEqual(ids, [older.id, newer.id])
    }

    func testUnfiledInboxIDsRespectsLimit() {
        let memories = (0..<10).map { i -> MemoryObject in
            var m = MemoryObject(type: .text, content: "item \(i)")
            m.createdAt = Date(timeIntervalSince1970: TimeInterval(i))
            return m
        }
        let ids = AutopilotOrganizer.unfiledInboxIDs(from: memories, limit: 3)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids, Array(memories.prefix(3).map(\.id)))
        XCTAssertEqual(AutopilotOrganizer.unfiledInboxCount(from: memories), 10)
        XCTAssertEqual(AutopilotOrganizer.maxBackfillBatch, 40)
    }

    // MARK: - Ollama response parsing

    func testParseOrganizationResponse() {
        let raw = """
        Board: Work
        Folder: Design Reviews
        Confidence: 0.88
        CreateBoard: false
        CreateFolder: true
        """
        let proposal = OllamaClient.shared.parseOrganization(raw)
        XCTAssertEqual(proposal?.board, "Work")
        XCTAssertEqual(proposal?.folder, "Design Reviews")
        XCTAssertEqual(proposal?.confidence ?? 0, 0.88, accuracy: 0.001)
        XCTAssertEqual(proposal?.createBoard, false)
        XCTAssertEqual(proposal?.createFolder, true)
    }

    func testParseOrganizationInboxMeansNil() {
        let raw = """
        Board: Inbox
        Folder: none
        Confidence: 0.2
        CreateBoard: false
        CreateFolder: false
        """
        XCTAssertNil(OllamaClient.shared.parseOrganization(raw))
    }
}

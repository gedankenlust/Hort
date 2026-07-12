import XCTest
@testable import Hort

final class ExportEngineTests: XCTestCase {
    private var engine: ExportEngine!
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("HortExportTests-\(UUID().uuidString)", isDirectory: true)
        engine = ExportEngine(fileSystem: FileSystemManager(rootURL: temporaryRoot))
    }

    override func tearDownWithError() throws {
        engine = nil
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testExportBundleCreatesZipWithMarkdownAndFrontmatter() throws {
        var text = MemoryObject(type: .text, content: "Hello Export\nsecond line")
        text.tags = ["alpha", "beta"]
        let link = MemoryObject(type: .url, content: "https://example.com")

        let zipURL = tempURL("zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try engine.exportBundle([text, link], to: zipURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path), "zip should exist")

        let out = try unzip(zipURL)
        defer { try? FileManager.default.removeItem(at: out) }

        let mdFiles = try FileManager.default.contentsOfDirectory(atPath: out.path)
            .filter { $0.hasSuffix(".md") }
        XCTAssertEqual(mdFiles.count, 2, "one markdown file per memory")

        let combined = try mdFiles
            .map { try String(contentsOf: out.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n---FILE---\n")
        XCTAssertTrue(combined.contains("Hello Export"))
        XCTAssertTrue(combined.contains("tags: [\"alpha\",\"beta\"]"))
        XCTAssertTrue(combined.contains("https://example.com"))
        XCTAssertTrue(combined.contains("type: \"text\""))
    }

    func testFrontmatterSafelyEncodesUnicodeAndPunctuation() throws {
        var memory = MemoryObject(type: .text, content: "Grüße aus Wien")
        memory.sourceApp = "Browser: \"Private\""
        memory.board = "Research [2026]"
        memory.tags = ["ümlaut", "a: b", "quote\"tag"]

        let fileURL = try engine.exportToMarkdown(memory)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let markdown = try String(contentsOf: fileURL, encoding: .utf8)

        let source: String = try decodeFrontmatterValue("source_app", from: markdown)
        let board: String = try decodeFrontmatterValue("board", from: markdown)
        let tags: [String] = try decodeFrontmatterValue("tags", from: markdown)

        XCTAssertEqual(source, memory.sourceApp)
        XCTAssertEqual(board, memory.board)
        XCTAssertEqual(tags, memory.tags)
        XCTAssertTrue(markdown.contains("Grüße aus Wien"))
    }

    func testExportBundleCopiesImageAssetRelatively() throws {
        let png = tempURL("png")
        try makeTinyPNG().write(to: png)
        defer { try? FileManager.default.removeItem(at: png) }

        let image = MemoryObject(type: .image, content: png.path)

        let zipURL = tempURL("zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try engine.exportBundle([image], to: zipURL)

        let out = try unzip(zipURL)
        defer { try? FileManager.default.removeItem(at: out) }

        let assets = (try? FileManager.default.contentsOfDirectory(
            atPath: out.appendingPathComponent("assets").path)) ?? []
        XCTAssertEqual(assets.count, 1, "image content should be copied into assets/")

        let md = try FileManager.default.contentsOfDirectory(atPath: out.path)
            .filter { $0.hasSuffix(".md") }
            .map { try String(contentsOf: out.appendingPathComponent($0), encoding: .utf8) }
            .joined()
        XCTAssertTrue(md.contains("](assets/"), "markdown should link the asset relatively")
    }

    // MARK: - Helpers

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("odtest-\(UUID().uuidString).\(ext)")
    }

    private func unzip(_ zip: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("odout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zip.path, "-d", dir.path]
        try process.run()
        process.waitUntilExit()
        return dir
    }

    private func makeTinyPNG() throws -> Data {
        // 1x1 transparent PNG.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64)!
    }

    private func decodeFrontmatterValue<T: Decodable>(_ key: String, from markdown: String) throws -> T {
        let prefix = "\(key): "
        guard let line = markdown.components(separatedBy: .newlines).first(where: { $0.hasPrefix(prefix) }),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

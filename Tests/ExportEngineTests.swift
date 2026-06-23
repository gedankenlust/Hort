import XCTest
@testable import Hort

final class ExportEngineTests: XCTestCase {

    func testExportBundleCreatesZipWithMarkdownAndFrontmatter() throws {
        var text = MemoryObject(type: .text, content: "Hello Export\nsecond line")
        text.tags = ["alpha", "beta"]
        let link = MemoryObject(type: .url, content: "https://example.com")

        let zipURL = tempURL("zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try ExportEngine.shared.exportBundle([text, link], to: zipURL)

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
        XCTAssertTrue(combined.contains("tags: [alpha, beta]"))
        XCTAssertTrue(combined.contains("https://example.com"))
        XCTAssertTrue(combined.contains("type: text"))
    }

    func testExportBundleCopiesImageAssetRelatively() throws {
        let png = tempURL("png")
        try makeTinyPNG().write(to: png)
        defer { try? FileManager.default.removeItem(at: png) }

        let image = MemoryObject(type: .image, content: png.path)

        let zipURL = tempURL("zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }
        try ExportEngine.shared.exportBundle([image], to: zipURL)

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
}

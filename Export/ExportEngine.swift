import Foundation

class ExportEngine {
    static let shared = ExportEngine()

    private init() {}

    enum ExportError: Error { case zipFailed(Int32) }

    /// Single-memory markdown export to the app's exports folder (Inspector action).
    @discardableResult
    func exportToMarkdown(_ object: MemoryObject) throws -> URL {
        let fileURL = FileSystemManager.shared.exportsURL
            .appendingPathComponent(fileName(for: object))
        try markdown(for: object).write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    /// Exports a set of memories as an Obsidian-friendly ZIP: one markdown file
    /// per memory plus an `assets/` folder with copied images and attachments,
    /// linked relatively so the bundle is portable.
    func exportBundle(_ memories: [MemoryObject], to zipURL: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("HortExport-\(UUID().uuidString)", isDirectory: true)
        let assetsDir = staging.appendingPathComponent("assets", isDirectory: true)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for object in memories {
            var assetRename: [String: String] = [:]

            // Files referenced by this memory: image/screenshot/file content + attachments.
            var assetPaths: [String] = []
            if object.type == .image || object.type == .screenshot || object.type == .file,
               let content = object.content, fm.fileExists(atPath: content) {
                assetPaths.append(content)
            }
            assetPaths.append(contentsOf: object.attachments.filter { fm.fileExists(atPath: $0) })

            for path in assetPaths where assetRename[path] == nil {
                let dest = uniqueAssetURL(in: assetsDir,
                                          preferredName: URL(fileURLWithPath: path).lastPathComponent)
                try? fm.copyItem(at: URL(fileURLWithPath: path), to: dest)
                assetRename[path] = "assets/\(dest.lastPathComponent)"
            }

            let fileURL = staging.appendingPathComponent(fileName(for: object))
            try markdown(for: object, assetRename: assetRename)
                .write(to: fileURL, atomically: true, encoding: .utf8)
        }

        if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-r", "-q", zipURL.path, "."]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExportError.zipFailed(process.terminationStatus)
        }
    }

    // MARK: - Markdown building

    private func markdown(for object: MemoryObject, assetRename: [String: String] = [:]) -> String {
        let tags = object.tags.joined(separator: ", ")
        var md = """
        ---
        id: \(object.id.uuidString)
        type: \(object.type.rawValue)
        created: \(ISO8601DateFormatter().string(from: object.createdAt))
        source_app: \(object.sourceApp ?? "Unknown")
        board: \(object.board ?? "")
        tags: [\(tags)]
        ---

        # \(title(for: object))

        """

        // Body: embed the image for visual types, else the textual content.
        if (object.type == .image || object.type == .screenshot),
           let content = object.content, let rel = assetRename[content] {
            md += "![\(object.type.rawValue)](\(rel))\n"
        } else if object.type == .text || object.type == .url,
                  let content = object.content, !content.isEmpty {
            md += "\(content)\n"
        }

        let attachments = assetRename.filter { $0.key != object.content }
        if !attachments.isEmpty {
            md += "\n## Attachments\n"
            for rel in attachments.values.sorted() {
                md += "- [\(URL(fileURLWithPath: rel).lastPathComponent)](\(rel))\n"
            }
        }
        return md
    }

    private func title(for object: MemoryObject) -> String {
        if object.type == .text || object.type == .url,
           let line = object.content?.split(whereSeparator: \.isNewline).first,
           !line.isEmpty {
            return String(line.prefix(80))
        }
        return object.type.rawValue.capitalized
    }

    // MARK: - File naming

    private func fileName(for object: MemoryObject) -> String {
        let base: String
        switch object.type {
        case .text, .url: base = slug(from: object.content) ?? object.type.rawValue
        default: base = object.type.rawValue
        }
        return "\(base)_\(object.id.uuidString.prefix(8)).md"
    }

    private func slug(from content: String?) -> String? {
        guard let first = content?.split(whereSeparator: \.isNewline).first else { return nil }
        let mapped = first.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(mapped).prefix(40).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? nil : slug
    }

    private func uniqueAssetURL(in dir: URL, preferredName: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent(preferredName)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 1
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = dir.appendingPathComponent(name)
            index += 1
        }
        return candidate
    }
}

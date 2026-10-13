import Foundation
import CryptoKit

/// Exact duplicate grouping for memories. Groups share a type-scoped fingerprint;
/// one keeper is retained per group and the rest are extras eligible for delete.
enum DuplicateDetector {

    enum KeeperPolicy {
        /// Keep the most recently created memory in each group.
        case newest
        /// Keep the earliest created memory in each group.
        case oldest
    }

    struct Group: Equatable {
        let keeperID: UUID
        let duplicateIDs: [UUID]

        var allIDs: [UUID] { [keeperID] + duplicateIDs }
    }

    struct SelectionPlan: Equatable {
        /// Memories to select for deletion (extras only — never keepers).
        let duplicateIDs: Set<UUID>
        let groupCount: Int
        let keeperCount: Int
        let duplicateCount: Int

        var hasDuplicates: Bool { duplicateCount > 0 }
    }

    /// Finds exact-duplicate groups within `memories`. Singleton fingerprints are ignored.
    static func findGroups(
        in memories: [MemoryObject],
        policy: KeeperPolicy = .newest
    ) -> [Group] {
        var buckets: [String: [MemoryObject]] = [:]
        for memory in memories {
            guard let key = fingerprint(for: memory) else { continue }
            buckets[key, default: []].append(memory)
        }

        return buckets.values.compactMap { members -> Group? in
            guard members.count >= 2 else { return nil }
            let sorted = members.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            let keeper = policy == .newest ? sorted[0] : sorted[sorted.count - 1]
            let extras = sorted.filter { $0.id != keeper.id }.map(\.id)
            return Group(keeperID: keeper.id, duplicateIDs: extras)
        }
        .sorted { $0.keeperID.uuidString < $1.keeperID.uuidString }
    }

    /// Selects every extra in duplicate groups; keepers stay unselected.
    static func selectionPlan(
        in memories: [MemoryObject],
        policy: KeeperPolicy = .newest
    ) -> SelectionPlan {
        let groups = findGroups(in: memories, policy: policy)
        let extras = Set(groups.flatMap(\.duplicateIDs))
        return SelectionPlan(
            duplicateIDs: extras,
            groupCount: groups.count,
            keeperCount: groups.count,
            duplicateCount: extras.count
        )
    }

    /// Type-scoped fingerprint for exact matching. Returns nil when content is
    /// missing/empty so incomplete rows never falsely collide.
    static func fingerprint(for memory: MemoryObject) -> String? {
        switch memory.type {
        case .text:
            guard let normalized = normalizeText(memory.content) else { return nil }
            return "text:\(sha256Hex(normalized))"
        case .url:
            guard let normalized = normalizeURL(memory.content) else { return nil }
            return "url:\(sha256Hex(normalized))"
        case .image, .screenshot:
            if let fileKey = fileFingerprint(path: memory.content) {
                return "\(memory.type.rawValue):\(fileKey)"
            }
            // Fallback when the asset is gone: identical stored path + size metadata,
            // or identical preview text for placeholder "Image" rows.
            if let path = memory.content?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, path != "Image" {
                let size = memory.metadata["fileSize"] ?? ""
                return "\(memory.type.rawValue)-path:\(sha256Hex("\(path)|\(size)"))"
            }
            if let preview = normalizeText(memory.preview), preview != "image" {
                return "\(memory.type.rawValue)-preview:\(sha256Hex(preview))"
            }
            return nil
        case .file:
            if let fileKey = fileFingerprint(path: memory.content) {
                return "file:\(fileKey)"
            }
            guard let path = memory.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return nil }
            let size = memory.metadata["fileSize"] ?? ""
            return "file-path:\(sha256Hex("\(path)|\(size)"))"
        }
    }

    // MARK: - Normalization

    static func normalizeText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func normalizeURL(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        // Drop trailing slash on the path so https://a.com and https://a.com/ match.
        let path = components.path
        if path.count > 1, path.hasSuffix("/") {
            components.path = String(path.dropLast())
        }
        components.fragment = nil
        return (components.string ?? trimmed).lowercased()
    }

    // MARK: - File hashing

    /// Content hash of the file, falling back to path + byte size when hashing fails.
    private static func fileFingerprint(path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty, path != "Image" else { return nil }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              !isDir.boolValue else { return nil }

        if let hash = sha256File(at: url) {
            return "sha256:\(hash)"
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "meta:\(sha256Hex("\(path)|\(size)"))"
    }

    private static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256File(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            } catch {
                return nil
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

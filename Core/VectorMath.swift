import Foundation

/// Pure vector helpers for the local semantic index — no database or network,
/// so they stay trivially unit-testable. Embeddings are stored normalized, so
/// at query time cosine similarity reduces to a dot product.
enum VectorMath {

    /// Returns the unit-length version of `v`. A zero vector is returned as-is.
    static func normalize(_ v: [Float]) -> [Float] {
        var sum: Float = 0
        for x in v { sum += x * x }
        let norm = sum.squareRoot()
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    /// Dot product. Returns 0 for mismatched lengths rather than crashing.
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var sum: Float = 0
        for i in 0..<a.count { sum += a[i] * b[i] }
        return sum
    }

    /// Cosine similarity in [-1, 1] for arbitrary (non-normalized) vectors.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        dot(normalize(a), normalize(b))
    }

    /// Reciprocal Rank Fusion: merges several ranked id lists into one ranking.
    /// Each list contributes 1/(k + rank) per id; higher combined score ranks
    /// first. `k` damps the weight of top positions (60 is the common default).
    static func reciprocalRankFusion(_ rankings: [[UUID]], k: Double = 60) -> [UUID] {
        var score: [UUID: Double] = [:]
        for list in rankings {
            for (index, id) in list.enumerated() {
                score[id, default: 0] += 1.0 / (k + Double(index + 1))
            }
        }
        return score.sorted { $0.value > $1.value }.map(\.key)
    }
}

extension Array where Element == Float {
    /// Raw little-endian Float32 bytes for BLOB storage. Endianness is fine to
    /// ignore because the data never leaves the machine that wrote it.
    var blob: Data {
        withUnsafeBytes { Data($0) }
    }

    /// Reconstructs a Float array from a `blob` produced above.
    init(blob: Data) {
        self = blob.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}

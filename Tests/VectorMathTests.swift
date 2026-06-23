import XCTest
@testable import Hort

final class VectorMathTests: XCTestCase {

    func testCosineIdenticalIsOne() {
        let v: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(VectorMath.cosine(v, v), 1.0, accuracy: 1e-5)
    }

    func testCosineOrthogonalIsZero() {
        XCTAssertEqual(VectorMath.cosine([1, 0], [0, 1]), 0.0, accuracy: 1e-6)
    }

    func testCosineOppositeIsNegativeOne() {
        XCTAssertEqual(VectorMath.cosine([1, 1], [-1, -1]), -1.0, accuracy: 1e-6)
    }

    func testCosineMismatchedLengthsIsSafe() {
        XCTAssertEqual(VectorMath.cosine([1, 2, 3], [1, 2]), 0.0, accuracy: 1e-6)
    }

    func testNormalizeProducesUnitLength() {
        let n = VectorMath.normalize([3, 4]) // length 5
        XCTAssertEqual(n[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(n[1], 0.8, accuracy: 1e-6)
    }

    func testNormalizeZeroVectorUnchanged() {
        XCTAssertEqual(VectorMath.normalize([0, 0, 0]), [0, 0, 0])
    }

    func testBlobRoundTrip() {
        let v: [Float] = [0.5, -1.25, 3.0, 0.0, 768.5]
        let restored = [Float](blob: v.blob)
        XCTAssertEqual(restored, v)
    }

    func testReciprocalRankFusionPrefersConsensus() {
        let a = UUID(), b = UUID(), c = UUID()
        // `a` tops both lists -> clear winner. `c` appears in only one list at
        // the lowest rank -> clear loser. `b` is in both, so it beats `c`.
        let fused = VectorMath.reciprocalRankFusion([[a, b, c], [a, b]])
        XCTAssertEqual(fused, [a, b, c])
    }

    func testReciprocalRankFusionMergesDisjointLists() {
        let a = UUID(), b = UUID()
        let fused = VectorMath.reciprocalRankFusion([[a], [b]])
        XCTAssertEqual(Set(fused), Set([a, b]))
    }
}

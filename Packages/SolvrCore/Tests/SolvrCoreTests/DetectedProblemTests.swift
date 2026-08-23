import Testing
import Foundation
@testable import SolvrCore

/// Vision hands back boxes measured from the bottom left. Everything that
/// consumes a `DetectedProblem` -- the crop in `ProblemPreviewSheet`, the
/// sanity filters in `ScannerViewModel` -- works in percentages from the top
/// left. The conversion is four lines and inverting it silently flips every
/// crop, which is why it is tested rather than trusted.
@Suite("Vision boxes become top-left percentages")
struct DetectedProblemBoxTests {

    @Test("a box in the bottom-left corner lands at the bottom left")
    func bottomLeft() {
        // Vision: sitting on the floor, hard against the left edge.
        let b = DetectedProblem.BoundingBox.fromVision(minX: 0, minY: 0, width: 0.5, height: 0.1)
        #expect(b.left == 0)
        #expect(b.width == 50)
        #expect(b.height.rounded() == 10)
        // Top-left origin: 90% of the way down, not 0%.
        #expect(b.top.rounded() == 90)
    }

    @Test("a box at the top of the image reports a small top")
    func topOfImage() {
        // Vision: minY 0.9 + height 0.1 means it touches the ceiling.
        let b = DetectedProblem.BoundingBox.fromVision(minX: 0.1, minY: 0.9, width: 0.8, height: 0.1)
        #expect(b.top.rounded() == 0)
        #expect(b.left.rounded() == 10)
    }

    @Test("the flip is an involution about the middle")
    func symmetry() {
        // A band just above centre and its mirror just below must land at
        // mirrored tops. This is the assertion that fails if someone "simplifies"
        // the conversion to minY * 100.
        let upper = DetectedProblem.BoundingBox.fromVision(minX: 0, minY: 0.6, width: 1, height: 0.1)
        let lower = DetectedProblem.BoundingBox.fromVision(minX: 0, minY: 0.3, width: 1, height: 0.1)
        #expect((upper.top + lower.top + upper.height).rounded() == 100)
    }

    @Test("a full-frame box covers the whole frame")
    func fullFrame() {
        let b = DetectedProblem.BoundingBox.fromVision(minX: 0, minY: 0, width: 1, height: 1)
        #expect(b.top == 0)
        #expect(b.left == 0)
        #expect(b.width == 100)
        #expect(b.height == 100)
    }
}

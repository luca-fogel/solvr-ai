import Foundation

public struct DetectedProblem: Codable, Identifiable, Sendable {
    public var id: String { "\(bbox.left)-\(bbox.top)-\(latex)" }
    public let bbox: BoundingBox
    public let latex: String

    public init(bbox: BoundingBox, latex: String) {
        self.bbox = bbox
        self.latex = latex
    }

    public struct BoundingBox: Codable, Sendable {
        public let top: Double
        public let left: Double
        public let width: Double
        public let height: Double

        public init(top: Double, left: Double, width: Double, height: Double) {
            self.top = top
            self.left = left
            self.width = width
            self.height = height
        }
    }
}


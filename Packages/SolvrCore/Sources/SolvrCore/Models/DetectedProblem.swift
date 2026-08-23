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

        /// Convert one of Vision's normalised boxes.
        ///
        /// Vision measures from the **bottom** left in the unit square; every
        /// consumer here works in percentages from the **top** left. Getting it
        /// wrong flips the crop vertically, which reads as a detection bug rather
        /// than a coordinate one -- so the conversion lives here, next to the type
        /// it produces, instead of inline in a Vision callback the tests cannot
        /// reach.
        ///
        /// `minX`/`minY` are the box's lower-left corner and `width`/`height` its
        /// size, all in 0...1 -- i.e. exactly the fields of `CGRect` as Vision
        /// hands it over.
        public static func fromVision(minX: Double, minY: Double,
                                      width: Double, height: Double) -> BoundingBox {
            BoundingBox(top: (1 - (minY + height)) * 100,
                        left: minX * 100,
                        width: width * 100,
                        height: height * 100)
        }
    }
}


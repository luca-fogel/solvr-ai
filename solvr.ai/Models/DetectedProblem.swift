import Foundation

struct DetectedProblem: Codable, Identifiable {
    var id: String { "\(bbox.left)-\(bbox.top)-\(latex)" }
    let bbox: BoundingBox
    let latex: String

    struct BoundingBox: Codable {
        let top: Double
        let left: Double
        let width: Double
        let height: Double
    }
}


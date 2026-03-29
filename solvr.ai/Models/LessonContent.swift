import Foundation

struct LessonContent: Codable {
    let title: String
    let topic: String
    let introduction: String
    let sections: [LessonSection]
    let keyTakeaway: String?

    struct LessonSection: Codable, Identifiable {
        var id: String { heading }
        let heading: String
        let content: String
        let formula: String?
        let note: String?
        let steps: [String]?
    }
}

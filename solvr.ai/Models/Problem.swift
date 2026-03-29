import Foundation
import SwiftData

@Model
final class Problem {
    var id: UUID
    var text: String
    var topic: String
    var createdAt: Date
    var formulasJSON: String?
    var stepsJSON: String?
    var videosJSON: String?

    // V2: structured JSON instead of HTML
    var lessonJSON: String?

    // Source image from camera scanner (cropped handwritten math)
    var sourceImageData: Data?

    // Chat messages
    var chatMessagesJSON: String?

    init(
        text: String,
        topic: String = "",
        createdAt: Date = .now,
        formulasJSON: String? = nil,
        stepsJSON: String? = nil,
        videosJSON: String? = nil,
        lessonJSON: String? = nil,
        sourceImageData: Data? = nil,
        chatMessagesJSON: String? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.topic = topic
        self.createdAt = createdAt
        self.formulasJSON = formulasJSON
        self.stepsJSON = stepsJSON
        self.videosJSON = videosJSON
        self.lessonJSON = lessonJSON
        self.sourceImageData = sourceImageData
        self.chatMessagesJSON = chatMessagesJSON
    }
}

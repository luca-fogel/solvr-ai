import Foundation
import SwiftData

@Model
final class Problem {
    var id: UUID

    /// What to show in a list. For a typed problem this is the problem; for a
    /// photographed one it is what was read from it.
    var text: String

    /// **What the model was actually asked.**
    ///
    /// Separate from `text` because they were the same field once, and that
    /// field held whatever happened to be on screen -- "Scanning...", a
    /// model-written title -- so re-opening a photographed problem and touching
    /// a tab that had not been generated asked the model about the label. A
    /// lesson about flatbed scanners is what that looks like from the outside.
    ///
    /// Optional only for entries saved before this existed. `nil` means the
    /// question is gone and cannot be recovered, and the honest thing to do with
    /// those is refuse to re-ask rather than guess -- see
    /// `SolveCoordinator.restore`.
    var question: String?
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
        question: String? = nil,
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
        self.question = question
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

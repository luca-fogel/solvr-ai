import Foundation

/// The taught concept behind a problem, rather than its answer.
///
/// The strictest model of the set: everything except `keyTakeaway` is required,
/// so a backend that omits `topic` fails to decode at all rather than rendering
/// a lesson with a blank header. That is deliberate -- a lesson missing its
/// framing is not a lesson -- but it does mean this is the shape a weaker model
/// is most likely to fail, which is worth measuring separately.
public struct LessonContent: Codable, Sendable {
    public let title: String
    public let topic: String
    public let introduction: String
    public let sections: [LessonSection]
    public let keyTakeaway: String?

    public init(title: String, topic: String, introduction: String,
                sections: [LessonSection], keyTakeaway: String?) {
        self.title = title
        self.topic = topic
        self.introduction = introduction
        self.sections = sections
        self.keyTakeaway = keyTakeaway
    }

    public struct LessonSection: Codable, Identifiable, Sendable {
        /// Derived from the content rather than from `heading` alone: two
        /// sections given the same heading are a thing models do, and identical
        /// `ForEach` identities mean one of them silently does not render.
        public var id: String { "\(heading)|\(content.prefix(24))" }
        public let heading: String
        public let content: String
        public let formula: String?
        public let note: String?
        public let steps: [String]?

        public init(heading: String, content: String, formula: String? = nil,
                    note: String? = nil, steps: [String]? = nil) {
            self.heading = heading
            self.content = content
            self.formula = formula
            self.note = note
            self.steps = steps
        }
    }
}

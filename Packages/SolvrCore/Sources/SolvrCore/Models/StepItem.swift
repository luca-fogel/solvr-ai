import Foundation

/// One step of a worked solution.
///
/// Lenient on decode, deliberately: a step whose `title` is missing is still
/// worth showing, and losing the whole solution over one field would be worse
/// than a step labelled "Step".
public struct StepItem: Codable, Identifiable, Sendable {
    /// Derived from the content, not from `step`.
    ///
    /// This was `step`, which is the number the model chose. A model that emits
    /// two steps numbered 3 -- and a small local model will -- gives `ForEach`
    /// two rows with the same identity, and SwiftUI renders one of them or
    /// neither. Deriving identity from the content instead means duplicate
    /// numbering is merely wrong on screen rather than structurally broken, and
    /// unlike a stored `UUID` it stays stable when the same steps are re-decoded
    /// from history. Two steps identical in number, title and working still
    /// collide, but at that point they are the same step.
    public var id: String { "\(step)|\(title)|\(math ?? "")" }
    public let step: Int
    public let title: String
    public let explanation: String
    public let math: String?

    /// Whether this step carries the answer.
    ///
    /// The renderer used to assume the last step was the answer and relabel it
    /// "Final Answer", which threw away the model's own heading and asserted a
    /// conclusion even when generation had been cut off mid-working. The
    /// provider now says so explicitly, and says nothing when it does not know.
    public var isFinalAnswer: Bool

    public init(step: Int, title: String, explanation: String, math: String?,
                isFinalAnswer: Bool = false) {
        self.step = step
        self.title = title
        self.explanation = explanation
        self.math = math
        self.isFinalAnswer = isFinalAnswer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step = (try? container.decode(Int.self, forKey: .step)) ?? 1
        title = (try? container.decode(String.self, forKey: .title)) ?? "Step"
        explanation = (try? container.decode(String.self, forKey: .explanation)) ?? ""
        math = try? container.decodeIfPresent(String.self, forKey: .math)
        // Absent in solutions saved before the field existed. False is the safe
        // reading: an unmarked step is one the app will not label as an answer.
        isFinalAnswer = (try? container.decode(Bool.self, forKey: .isFinalAnswer)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case step, title, explanation, math, isFinalAnswer
    }
}

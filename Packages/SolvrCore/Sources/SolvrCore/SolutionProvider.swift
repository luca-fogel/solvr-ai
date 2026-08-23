import Foundation

/// What the user handed us to work on.
///
/// `Data` rather than `UIImage` on purpose. `SolvrCore` is Foundation-only by
/// design -- the moment it imports UIKit it stops being runnable by `swift test`,
/// and the tests are most of the reason this package exists. The bytes are
/// whatever the camera path encoded, in practice JPEG.
public enum ProblemInput: Sendable, Equatable {
    case text(String)
    case image(Data)

    /// The text, when there is text. `nil` for a photograph nobody has read yet.
    public var text: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}

/// One way of turning a maths problem into the four things Solvr shows.
///
/// The point of this protocol is that the view models cannot tell which backend
/// answered. Everything that differs between a hosted API, a model on the local
/// network, and a model on the phone itself is expressed here rather than
/// leaking into the UI:
///
/// - **Prompts belong to the provider.** A 4B needs shorter, more constrained
///   instructions than Opus does. That is a property of the backend, not of the
///   app, so the prompt text lives with the thing that needs it.
/// - **So does concurrency.** Solvr fans out four requests at once, which is
///   right for a hosted API and wrong for an on-device session that throws
///   `concurrentRequests` if you ask it two things at a time.
/// - **So does whether it can see.** Apple's on-device model takes text only --
///   there is no image type anywhere in `FoundationModels`, its `Prompt` is built
///   from `String` and nothing else -- while the hosted API reads a photograph
///   natively. A provider says which it is, and `SightedProvider` closes the gap
///   for the ones that cannot see.
public protocol SolutionProvider: Sendable {
    /// Stable, log-safe name for this backend. Recorded against every
    /// measurement, so it has to identify the *configuration*, not just the
    /// family: `apple-on-device/guided` rather than `apple`.
    var identifier: String { get }

    /// How many requests this backend will genuinely serve at once.
    var maxConcurrentRequests: Int { get }

    /// Whether this backend has everything it needs to be asked a question --
    /// a key, a reachable URL, an eligible device. A backend that is not
    /// configured should be offered to the user but not silently selected.
    var isConfigured: Bool { get }

    /// Whether a photograph can be handed straight to the model.
    ///
    /// `false` is not a failure: it means image input has to be turned into text
    /// first, which `SightedProvider` does. It is recorded per backend because
    /// reading a photograph of a fraction is measurably harder than reading a
    /// typed one, and the comparison is only honest if we know which path a
    /// number came from.
    var acceptsImageInput: Bool { get }

    func lesson(for problem: ProblemInput) async throws -> LessonContent
    func steps(for problem: ProblemInput) async throws -> [StepItem]
    func formulas(for problem: ProblemInput) async throws -> [FormulaItem]
    func videos(for problem: ProblemInput) async throws -> [VideoItem]

    func chatReply(to message: String,
                   about problem: String,
                   history: [ChatMessage]) async throws -> String

    /// Best-effort short label. Deliberately non-throwing: a missing title is a
    /// cosmetic problem and should never fail a solve.
    func title(for problem: ProblemInput) async -> String
}

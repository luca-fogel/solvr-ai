import Foundation

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
/// What is deliberately *not* here any more is anything about images. A
/// provider is handed a question -- a `String`, resolved once by `SolveBuilder`
/// before any of this is called -- and there is no longer an input type that
/// might or might not have been read yet. Apple's on-device model takes no image
/// input at all (`PromptRepresentable` is `String`, `Prompt`, `Array` and
/// `Optional` across the whole framework), so a photograph had to become text
/// somewhere; putting that above the protocol instead of below it is what makes
/// every surface of one solve provably receive the same bytes.
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

    func lesson(for question: String) async throws -> LessonContent
    func steps(for question: String) async throws -> [StepItem]
    func formulas(for question: String) async throws -> [FormulaItem]
    func videos(for question: String) async throws -> [VideoItem]

    func chatReply(to message: String,
                   about question: String,
                   history: [ChatMessage]) async throws -> String
}

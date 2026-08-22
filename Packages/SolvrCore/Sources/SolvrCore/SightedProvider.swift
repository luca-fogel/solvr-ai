import Foundation

/// Lets a text-only backend answer questions about a photograph.
///
/// This exists because of a hard limit rather than a preference: Apple's
/// on-device model takes no images at all. Its `Prompt` is built from `String`,
/// `Prompt`, `Array` and `Optional`, and there is no image, attachment or pixel
/// type anywhere in the framework. A locally served text model is in the same
/// position. So for those backends the photograph has to become text before the
/// model sees it, and the recogniser is injected rather than imported so this
/// stays testable without UIKit or Vision.
///
/// **This is a downgrade, and it should be reported as one.** Native vision reads
/// a fraction as a fraction; text recognition reads it as two numbers with a line
/// between them, and superscripts, integral signs and matrices fare worse. A
/// backend wrapped in this is answering a different, harder question than one
/// that sees the image, which is exactly why `SolutionProvider.acceptsImageInput`
/// is recorded per backend instead of being assumed.
public struct SightedProvider: SolutionProvider {

    /// Photograph bytes in, recognised text out. `OCRService` supplies this in
    /// the app; a test supplies a closure.
    public typealias TextRecogniser = @Sendable (Data) async throws -> String

    private let wrapped: any SolutionProvider
    private let recognise: TextRecogniser
    private let memo = RecognitionMemo()

    public init(wrapping wrapped: any SolutionProvider,
                recognise: @escaping TextRecogniser) {
        self.wrapped = wrapped
        self.recognise = recognise
    }

    public var identifier: String { "\(wrapped.identifier)+ocr" }
    public var maxConcurrentRequests: Int { wrapped.maxConcurrentRequests }
    public var isConfigured: Bool { wrapped.isConfigured }

    /// True because the wrapper handles images, not because the model does.
    public var acceptsImageInput: Bool { true }

    /// Turn a photograph into text, once per photograph rather than once per
    /// request. Four surfaces are fetched for a single solve; recognising the
    /// same image four times would be four times the work for the same answer.
    private func resolve(_ input: ProblemInput) async throws -> ProblemInput {
        guard case .image(let data) = input else { return input }
        if let cached = await memo.text(for: data) { return .text(cached) }
        let text: String
        do {
            text = try await recognise(data)
        } catch {
            throw SolverError.decodingFailed(
                context: "image: could not read the text in this photograph")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SolverError.backendUnavailable(
                reason: "No text could be found in that photo. Try a closer, "
                      + "sharper picture, or type the problem instead.")
        }
        await memo.store(trimmed, for: data)
        return .text(trimmed)
    }

    public func lesson(for problem: ProblemInput) async throws -> LessonContent {
        try await wrapped.lesson(for: try await resolve(problem))
    }

    public func steps(for problem: ProblemInput) async throws -> [StepItem] {
        try await wrapped.steps(for: try await resolve(problem))
    }

    public func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        try await wrapped.formulas(for: try await resolve(problem))
    }

    public func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        try await wrapped.videos(for: try await resolve(problem))
    }

    public func chatReply(to message: String,
                          about problem: String,
                          history: [ChatMessage]) async throws -> String {
        try await wrapped.chatReply(to: message, about: problem, history: history)
    }

    public func title(for problem: ProblemInput) async -> String {
        guard let resolved = try? await resolve(problem) else {
            return "Scanned Problem"
        }
        return await wrapped.title(for: resolved)
    }
}

/// Remembers the last photograph only.
///
/// Single-entry on purpose: the access pattern is four concurrent requests about
/// one image, so one slot serves every hit we care about and nothing accumulates
/// for the life of the process.
private actor RecognitionMemo {
    private var key: Data?
    private var value: String?

    func text(for data: Data) -> String? {
        key == data ? value : nil
    }

    func store(_ text: String, for data: Data) {
        key = data
        value = text
    }
}

#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Solvr on Apple's on-device model, with no network and no key.
///
/// The interesting property of this backend is not that it is free. It is that
/// the JSON repair ladder in `LLMJSON` is **unreachable** from here. Guided
/// generation constrains decoding to a schema, so the framework hands back a
/// typed value and there is never a `String` to mis-parse -- no fence to strip,
/// no prose to slice, and above all no `\frac`-versus-form-feed ambiguity, which
/// is the bug that was silently corrupting every fraction in the hosted path.
///
/// That is worth stating precisely, because the tempting version is wrong.
/// Generation can still fail: `GenerationError` has `decodingFailure`,
/// `exceededContextWindowSize`, `guardrailViolation` and `refusal`. What guided
/// generation removes is not failure but *silent* failure. A malformed answer
/// becomes a thrown error instead of a plausible-looking wrong one.
///
/// Three hard limits shape everything below, all checked against the SDK rather
/// than assumed:
///
/// - **`contextSize` is 4096**, prompt plus completion. The hosted prompts spend
///   roughly 400 tokens restating a JSON schema; here the schema is enforced by
///   the decoder, so `includeSchemaInPrompt: false` deletes that cost outright
///   and the instructions are written short.
/// - **One request at a time.** `GenerationError.concurrentRequests` is real, and
///   the app fans out four surfaces per solve, so this provider serialises them
///   itself rather than trusting callers.
/// - **It cannot see.** There is no image type anywhere in `FoundationModels`;
///   `PromptRepresentable` is `String`, `Prompt`, `Array` and `Optional`. Photos
///   reach it as recognised text via `SightedProvider`, which is why
///   `acceptsImageInput` is `false` here and why that is not a bug to fix.
@available(iOS 26.0, macOS 26.0, *)
public final class OnDeviceProvider: SolutionProvider {

    /// Serialised deliberately: see `concurrentRequests` above.
    private let queue = RequestQueue(maxConcurrent: 1)
    private let observe: (@Sendable (String, TimeInterval, String?) -> Void)?

    public init(observe: (@Sendable (String, TimeInterval, String?) -> Void)? = nil) {
        self.observe = observe
    }

    // MARK: - SolutionProvider

    public var identifier: String { "apple-on-device/guided" }
    public var maxConcurrentRequests: Int { 1 }
    public var isConfigured: Bool { availability == nil }

    /// False, and not fixable: the framework takes no images at all.
    public var acceptsImageInput: Bool { false }

    /// `nil` when the model is ready, otherwise the reason it is not.
    ///
    /// Worth surfacing in Settings rather than only at failure time: three of the
    /// four outcomes are about the device or the user's settings, not about
    /// anything the app did, and "Apple Intelligence is off" deserves a different
    /// sentence from "this iPhone is too old".
    public var availability: SolverError? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .backendUnavailable(reason: "This device cannot run Apple's on-device model. "
                + "It needs an iPhone 15 Pro or newer.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .backendUnavailable(reason: "Apple Intelligence is turned off. "
                + "Switch it on in Settings to solve problems on device.")
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .backendUnavailable(reason: "Apple's on-device model is unavailable.")
        }
    }

    /// Warm the model so the first solve does not pay for loading it.
    public func prewarm() {
        guard availability == nil else { return }
        LanguageModelSession(model: .default).prewarm()
    }

    // MARK: - Generable mirrors
    //
    // Separate from the domain models on purpose. Attaching `@Generable` to
    // `LessonContent` would tie a type used everywhere to a framework that only
    // exists on iOS 26, and these shapes are also deliberately smaller than the
    // hosted ones -- a 4096-token budget is not the place for five sections.
    //
    // Note what is *not* asked for: the step number. The model generates the
    // steps in order and we number them from the index, which removes an entire
    // failure mode. Repeated step numbers were breaking `ForEach` identity, and a
    // field the model never fills is a field it cannot get wrong.

    @Generable
    struct GeneratedSolution {
        @Guide(description: "The worked steps in order. The last one states the final answer.",
               .count(3...6))
        var steps: [GeneratedStep]
    }

    @Generable
    struct GeneratedStep {
        @Guide(description: "A short action phrase, like 'Apply the power rule'.")
        var title: String
        @Guide(description: "One or two plain sentences of reasoning. No LaTeX, no symbols: write 'x squared', not '$x^2$'.")
        var explanation: String
        @Guide(description: """
            The algebra for this step written in LaTeX, with no dollar delimiters. \
            Use LaTeX commands, never plain text: \\frac{a}{b} not a/b, x^{3} not \
            x^3, \\int_{0}^{1} not the word integral, \\sqrt{x} not sqrt(x), \
            \\left[ x^{3} \\right]_{0}^{1} for evaluation bars. Write only the \
            mathematics, no words. Empty string if this step is purely conceptual.
            """)
        var math: String
    }

    @Generable
    struct GeneratedLesson {
        @Guide(description: "Two words: a broad area and a sub-area, like 'Calculus - Integration'.")
        var topic: String
        @Guide(description: "One or two sentences on when and why this concept matters.")
        var introduction: String
        @Guide(description: "Sections teaching the concept: what it is, an intuition, then a worked example.",
               .count(2...3))
        var sections: [GeneratedSection]
        @Guide(description: "One sentence summarising the key idea.")
        var keyTakeaway: String
        // Declared last on purpose. Guided generation fills fields in declaration
        // order, and asked for a title first the model simply echoed the student's
        // problem back. Asked after it has written the lesson, it has something to
        // name.
        @Guide(description: """
            The name of the mathematical concept taught above, as it would appear as \
            a textbook chapter heading -- for example 'The Fundamental Theorem of \
            Calculus' or 'Integration by Parts'. Never restate the student's problem.
            """)
        var title: String
    }

    @Generable
    struct GeneratedSection {
        @Guide(description: "A short section heading.")
        var heading: String
        @Guide(description: "Two to four sentences of explanation. Inline maths goes in $...$.")
        var content: String
        @Guide(description: """
            The key formula in LaTeX with no dollar delimiters, using commands \
            rather than plain text: \\frac{a}{b}, x^{n}, \\int_{a}^{b}. Empty \
            string if the section has no formula.
            """)
        var formula: String
    }

    @Generable
    struct GeneratedFormulas {
        @Guide(description: "Formulas that actually apply to this problem.", .count(3...5))
        var formulas: [GeneratedFormula]
    }

    @Generable
    struct GeneratedFormula {
        @Guide(description: "A short human-readable name.")
        var name: String
        @Guide(description: """
            The formula in LaTeX with no dollar delimiters, using commands rather \
            than plain text: \\frac{a}{b}, x^{n}, \\int_{a}^{b}, \\sqrt{x}.
            """)
        var formula: String
        @Guide(description: "One or two plain sentences on when to use it.")
        var description: String
    }

    @Generable
    struct GeneratedVideos {
        @Guide(description: "Search suggestions for learning this topic.", .count(3...5))
        var videos: [GeneratedVideo]
    }

    @Generable
    struct GeneratedVideo {
        @Guide(description: "A descriptive title for what to look for.")
        var title: String
        @Guide(description: "A maths education channel likely to cover it.",
               .anyOf(["Khan Academy", "3Blue1Brown", "Professor Leonard",
                       "The Organic Chemistry Tutor", "PatrickJMT"]))
        var channel: String
        @Guide(description: "A specific YouTube search query naming the exact concept and operation.")
        var searchQuery: String
    }

    // MARK: - The four surfaces

    public func steps(for problem: ProblemInput) async throws -> [StepItem] {
        let text = try requireText(problem)
        let solution: GeneratedSolution = try await generate(
            surface: "steps",
            instructions: """
            You are a patient maths tutor. Solve the problem the student gives you, \
            showing every algebraic step. Be exact and do not skip working. All \
            mathematics must be written in LaTeX notation, never as plain text.
            """,
            prompt: "Solve this problem step by step: \(text)")

        return solution.steps.enumerated().map { index, step in
            StepItem(step: index + 1,
                     title: step.title,
                     explanation: step.explanation,
                     // Measured, not defensive: this model returns correct maths
                     // in the wrong notation no matter how the guide is worded.
                     math: step.math.isEmpty ? nil : MathNotation.toLaTeX(step.math))
        }
    }

    public func lesson(for problem: ProblemInput) async throws -> LessonContent {
        let text = try requireText(problem)
        let lesson: GeneratedLesson = try await generate(
            surface: "lesson",
            instructions: """
            You are a maths tutor. Teach the concept behind the student's problem. \
            Do not solve their exact problem.
            """,
            prompt: "Teach the concept behind this problem: \(text)")

        return LessonContent(
            title: lesson.title,
            topic: lesson.topic,
            introduction: lesson.introduction,
            sections: lesson.sections.map {
                LessonContent.LessonSection(heading: $0.heading,
                                            content: $0.content,
                                            formula: $0.formula.isEmpty
                                                ? nil : MathNotation.toLaTeX($0.formula),
                                            note: nil,
                                            steps: nil)
            },
            keyTakeaway: lesson.keyTakeaway)
    }

    public func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        let text = try requireText(problem)
        let generated: GeneratedFormulas = try await generate(
            surface: "formulas",
            instructions: "You are a maths tutor listing the formulas a problem needs.",
            prompt: "List the key formulas relevant to: \(text)")

        return generated.formulas.map {
            FormulaItem(name: $0.name,
                        formula: MathNotation.toLaTeX($0.formula),
                        description: $0.description)
        }
    }

    /// Search suggestions, not video IDs.
    ///
    /// A model with no network cannot know a real YouTube ID and will invent one
    /// that 404s, so it is never asked for. `VideoItem.youtubeURL` already falls
    /// back to a search URL when `videoId` is nil, so the tab works and nothing
    /// is fabricated.
    public func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        let text = try requireText(problem)
        let generated: GeneratedVideos = try await generate(
            surface: "videos",
            instructions: """
            You suggest what to search for on YouTube to learn a maths topic. \
            Never invent a video ID or a URL.
            """,
            prompt: "Suggest searches for learning the topic behind: \(text)")

        return generated.videos.map {
            VideoItem(title: $0.title, channel: $0.channel,
                      searchQuery: $0.searchQuery, videoId: nil, thumbnailURL: nil)
        }
    }

    public func chatReply(to message: String,
                          about problem: String,
                          history: [ChatMessage]) async throws -> String {
        if let unavailable = availability { throw unavailable }

        // History is trimmed hard: the whole conversation has to fit in 4096
        // tokens alongside the answer, so the last few turns are all that can be
        // afforded. Truncating oldest-first keeps the recent thread coherent.
        let recent = history.suffix(4)
            .map { "\($0.role == .user ? "Student" : "Tutor"): \($0.content)" }
            .joined(separator: "\n")

        return try await run(surface: "chat") {
            let session = LanguageModelSession(model: .default) {
                """
                You are a friendly, patient maths tutor. The student is working on: \
                \(problem). Answer their follow-up clearly and encouragingly, in a \
                short paragraph. If they seem confused, try an analogy.
                """
            }
            let prompt = recent.isEmpty ? message : "\(recent)\nStudent: \(message)"
            return try await session.respond(to: prompt, options: Self.options).content
        }
    }

    public func title(for problem: ProblemInput) async -> String {
        guard case .text(let text) = problem else { return "Scanned Problem" }
        let fallback = String(text.prefix(40))
        guard availability == nil else { return fallback }

        let generated = try? await run(surface: "title") {
            let session = LanguageModelSession(model: .default) {
                "You write three-to-five word titles for maths problems. Reply with the title only."
            }
            return try await session.respond(to: "Title this problem: \(text)",
                                             options: Self.options).content
        }
        let title = (generated ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || title.count > 60 { return fallback }
        return title
    }

    // MARK: - Generation

    /// Greedy by default so a rerun of the evaluation means something. Sampling
    /// is seedable here too, which the hosted API does not offer.
    private static var options: GenerationOptions {
        GenerationOptions(sampling: .greedy)
    }

    private func requireText(_ problem: ProblemInput) throws -> String {
        guard case .text(let text) = problem else {
            // Reached only if this provider is used unwrapped. `ProviderFactory`
            // wraps it in `SightedProvider`, which turns a photo into text first.
            throw SolverError.backendUnavailable(
                reason: "The on-device model cannot read images. "
                      + "Text recognition should have run first.")
        }
        return text
    }

    /// One guided generation, with the schema kept out of the prompt.
    ///
    /// `includeSchemaInPrompt: false` is the whole reason a 4096-token window is
    /// workable: constrained decoding already enforces the shape, so restating it
    /// in the prompt buys nothing and costs a few hundred tokens of the budget
    /// the answer needs.
    private func generate<T: Generable & Sendable>(surface: String,
                                        instructions: String,
                                        prompt: String) async throws -> T {
        if let unavailable = availability { throw unavailable }
        return try await run(surface: surface) {
            let session = LanguageModelSession(model: .default) { instructions }
            return try await session.respond(to: prompt,
                                             generating: T.self,
                                             includeSchemaInPrompt: false,
                                             options: Self.options).content
        }
    }

    private func run<T: Sendable>(surface: String,
                                  _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await queue.withSlot {
            let started = Date()
            do {
                let value = try await body()
                self.observe?(surface, Date().timeIntervalSince(started), nil)
                return value
            } catch let error as LanguageModelSession.GenerationError {
                let mapped = Self.translate(error)
                self.observe?(surface, Date().timeIntervalSince(started), "\(error)")
                throw mapped
            } catch {
                self.observe?(surface, Date().timeIntervalSince(started), "\(error)")
                throw error
            }
        }
    }

    /// Framework errors become the app's own, so the UI can say something useful.
    ///
    /// `decodingFailure` is the one worth noticing: it is guided generation's
    /// version of the repair ladder failing, except it arrives as a thrown error
    /// rather than as text that parses into nonsense.
    private static func translate(_ error: LanguageModelSession.GenerationError) -> SolverError {
        switch error {
        case .exceededContextWindowSize:
            return .contextExceeded
        case .assetsUnavailable:
            return .modelNotReady
        case .rateLimited, .concurrentRequests:
            return .rateLimited(retryAfter: 2)
        case .guardrailViolation:
            return .backendUnavailable(
                reason: "The on-device model declined this one. Try rephrasing it.")
        case .refusal:
            return .backendUnavailable(
                reason: "The on-device model declined to answer this.")
        case .decodingFailure:
            return .decodingFailed(context: "on-device: the model's answer did not fit the schema")
        case .unsupportedLanguageOrLocale:
            return .backendUnavailable(
                reason: "The on-device model does not support this language yet.")
        default:
            return .apiError(error.localizedDescription)
        }
    }
}
#endif

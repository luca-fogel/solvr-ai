import Testing
import Foundation
@testable import SolvrCore

/// What the model is asked, and whether every surface of one solve is asked the
/// same thing.
///
/// These exist because of a photograph of `∫ 3x² + 2x + 4 dx` that produced a
/// lesson about flatbed scanners, a topic line reading `SCANNING`, and five
/// suggested videos titled "Scanning". None of that was the model being stupid:
/// it was asked about the word.
@Suite("One solve, one question")
@MainActor
struct SolveCoordinatorTests {

    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
    private static let recognised = "∫ 3x^2 + 2x + 4 dx"

    /// A provider that answers instantly and remembers what it was asked.
    private static func spy() -> RecordingProvider { RecordingProvider() }

    /// The app's wiring: `ProviderFactory.current()` builds a fresh
    /// `SightedProvider` on every call, so the recogniser it closes over is
    /// resolved per request, not per solve.
    private static func factory(_ spy: RecordingProvider,
                                recogniser: OCRCounter) -> @Sendable () -> any SolutionProvider {
        { SightedProvider(wrapping: spy) { _ in await recogniser.read(recognised) } }
    }

    // MARK: - The bug in the screenshots

    /// A photographed problem, backed out of and re-opened from History, must
    /// not ask the model about whatever string was on screen at the time.
    ///
    /// `Problem` has one text field and it holds a *label* -- "Scanning...",
    /// "[Scanned Image]", or a model-written title. Re-opening the entry and
    /// touching a surface that was never fetched the first time re-asks with
    /// that label as the problem, and the label is the only thing the model ever
    /// sees.
    @Test("a solve re-opened from history asks about the problem, not its label")
    func historyDoesNotAskAboutTheLabel() async {
        let spy = Self.spy()
        let ocr = OCRCounter()
        let coordinator = SolveCoordinator(provider: Self.factory(spy, recogniser: ocr))

        coordinator.solveFromImage(jpeg: Self.jpeg, placeholder: "Scanning...")
        await coordinator.settle()

        // The user backs out. The app saves what it was showing, because that is
        // the only field the history entry has.
        let saved = coordinator.problemTitle.isEmpty ? coordinator.currentProblem
                                                     : coordinator.problemTitle
        coordinator.loadFromHistory(text: saved,
                                    stepsJSON: nil, lessonJSON: nil,
                                    formulasJSON: nil, videosJSON: nil)

        // ...and opens the Lesson tab, which was never fetched.
        coordinator.ensureLoaded(.lesson)
        await coordinator.settle()

        let asked = spy.question(for: .lesson) ?? "nothing"
        #expect(asked == Self.recognised, "the lesson was asked about \(asked)")
    }

    /// Requirement 1, stated directly: every surface of one solve gets the same
    /// bytes.
    @Test("every surface of one solve receives byte-identical input")
    func allSurfacesAskTheSameThing() async {
        let spy = Self.spy()
        let coordinator = SolveCoordinator(provider: Self.factory(spy, recogniser: OCRCounter()))

        coordinator.solveFromImage(jpeg: Self.jpeg, placeholder: "Scanning...")
        await coordinator.settle()
        for surface in [Surface.lesson, .formulas, .videos] {
            coordinator.ensureLoaded(surface)
            await coordinator.settle()
        }

        let asked = spy.questions()
        #expect(Set(asked.values).count == 1,
                "surfaces were asked different questions: \(asked)")
        #expect(asked[.steps] == Self.recognised)
    }

    /// A photograph is read once, not once per surface.
    ///
    /// `SightedProvider` memoises per instance, and the app builds a new one per
    /// request, so the memo has never hit: Vision runs for steps, for the title,
    /// and again for every tab that is opened.
    @Test("a photograph is read once per solve")
    func photographIsReadOnce() async {
        let ocr = OCRCounter()
        let coordinator = SolveCoordinator(provider: Self.factory(Self.spy(), recogniser: ocr))

        coordinator.solveFromImage(jpeg: Self.jpeg, placeholder: "Scanning...")
        await coordinator.settle()
        for surface in [Surface.lesson, .formulas, .videos] {
            coordinator.ensureLoaded(surface)
            await coordinator.settle()
        }

        let reads = await ocr.count
        #expect(reads == 1, "Vision ran \(reads) times for one photograph")
    }

    // MARK: - Requirement 3: failure is legible

    /// A retry cancels the tail of the chain, and the cancelled task returns
    /// without writing a terminal state -- so the surface it was going to fetch
    /// stays `loading` for the life of the screen, with no error and no way out.
    @Test("retrying one surface does not strand another on a spinner")
    func retryDoesNotStrandASpinner() async {
        let spy = Self.spy()
        spy.fail(.steps, with: .contextExceeded)
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.solveAll(problem: "Solve for x: x^2 - 5x + 6 = 0")
        await coordinator.settle()
        #expect(coordinator.stepsState.error != nil)

        // The student opens Lesson, then gives up waiting and retries Steps.
        coordinator.ensureLoaded(.lesson)
        coordinator.retry(.steps)
        await coordinator.settle()

        #expect(!coordinator.lessonState.isLoading,
                "the lesson tab is stuck on a spinner that will never end")
    }

    /// Nothing has been solved, so there is nothing to ask about. The
    /// "Generate" button on an idle card must not send an empty problem.
    @Test("a surface cannot be fetched before anything has been solved")
    func noSolveMeansNoRequest() async {
        let spy = Self.spy()
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.retry(.steps)
        await coordinator.settle()

        let asked = spy.questions()
        #expect(asked.isEmpty, "asked the model \(asked)")
    }
}

// MARK: - Doubles

/// Counts how many times a photograph is read.
private actor OCRCounter {
    private(set) var count = 0
    func read(_ text: String) -> String {
        count += 1
        return text
    }
}

/// Answers instantly, and remembers the question it was given per surface.
private final class RecordingProvider: SolutionProvider, @unchecked Sendable {
    var identifier: String { "recording" }
    var maxConcurrentRequests: Int { 1 }
    var isConfigured: Bool { true }
    var acceptsImageInput: Bool { false }

    private let lock = NSLock()
    private var seen: [Surface: String] = [:]
    private var failures: [Surface: SolverError] = [:]

    func fail(_ surface: Surface, with error: SolverError) {
        lock.lock(); failures[surface] = error; lock.unlock()
    }

    func questions() -> [Surface: String] {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    func question(for surface: Surface) -> String? {
        lock.lock(); defer { lock.unlock() }
        return seen[surface]
    }

    private func record(_ surface: Surface, _ input: ProblemInput) throws {
        lock.lock()
        seen[surface] = input.text ?? "<an unresolved photograph>"
        let failure = failures[surface]
        lock.unlock()
        if let failure { throw failure }
    }

    func steps(for problem: ProblemInput) async throws -> [StepItem] {
        try record(.steps, problem)
        return [StepItem(step: 1, title: "t", explanation: "e", math: "x = 1")]
    }
    func lesson(for problem: ProblemInput) async throws -> LessonContent {
        try record(.lesson, problem)
        return LessonContent(title: "t", topic: "a", introduction: "i",
                             sections: [], keyTakeaway: nil)
    }
    func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        try record(.formulas, problem)
        return [FormulaItem(name: "n", formula: "x", description: "d")]
    }
    func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        try record(.videos, problem)
        return [VideoItem(title: "t", channel: "c", searchQuery: "q",
                          videoId: nil, thumbnailURL: nil)]
    }
    func chatReply(to message: String, about problem: String,
                   history: [ChatMessage]) async throws -> String { "reply" }
    func title(for problem: ProblemInput) async -> String {
        "A Model-Written Title"
    }
}

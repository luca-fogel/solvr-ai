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

    private static func builder(_ ocr: OCRCounter) -> SolveBuilder {
        SolveBuilder { _ in await ocr.read(recognised) }
    }

    // MARK: - The bug in the screenshots

    /// A photographed problem, backed out of and re-opened from History, must
    /// not ask the model about whatever string was on screen at the time.
    ///
    /// The history entry used to hold one text field, and that field held a
    /// *label*: "Scanning...", "[Scanned Image]", or a model-written title. It
    /// now holds the question as well, so re-opening the entry and touching a
    /// surface that was never fetched asks about the problem.
    @Test("a solve re-opened from history asks about the problem, not its label")
    func historyDoesNotAskAboutTheLabel() async throws {
        let spy = RecordingProvider()
        let ocr = OCRCounter()
        let coordinator = SolveCoordinator(provider: { spy })

        let solve = try await Self.builder(ocr).photograph(Self.jpeg)
        coordinator.begin(solve)
        await coordinator.settle()

        // The user backs out. What is saved is the solve, question included --
        // there is no longer a way to save only the label.
        coordinator.restore(solve, stepsJSON: nil, lessonJSON: nil,
                            formulasJSON: nil, videosJSON: nil)

        // ...and opens the Lesson tab, which was never fetched.
        coordinator.ensureLoaded(.lesson)
        await coordinator.settle()

        let asked = spy.question(for: .lesson) ?? "nothing"
        #expect(asked == Self.recognised, "the lesson was asked about \(asked)")
    }

    /// A history entry from before the question was recorded cannot be
    /// re-asked, and must say so rather than guess.
    @Test("an unrecorded question is refused, not invented")
    func unrecordedQuestionIsRefused() async {
        let spy = RecordingProvider()
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.restore(nil, stepsJSON: nil, lessonJSON: nil,
                            formulasJSON: nil, videosJSON: nil)
        coordinator.ensureLoaded(.lesson)
        await coordinator.settle()

        #expect(spy.questions().isEmpty, "asked the model \(spy.questions())")
        #expect(coordinator.lessonState.error == .questionNotRecorded)
        #expect(coordinator.lessonState.error?.isRetryable == false)
    }

    /// Requirement 1, stated directly: every surface of one solve gets the same
    /// bytes.
    @Test("every surface of one solve receives byte-identical input")
    func allSurfacesAskTheSameThing() async throws {
        let spy = RecordingProvider()
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.begin(try await Self.builder(OCRCounter()).photograph(Self.jpeg))
        await coordinator.settle()
        for surface in [Surface.lesson, .formulas, .videos] {
            coordinator.ensureLoaded(surface)
            await coordinator.settle()
        }

        let asked = spy.questions()
        #expect(asked.count == 4)
        #expect(Set(asked.values).count == 1,
                "surfaces were asked different questions: \(asked)")
        #expect(asked[.steps] == Self.recognised)
    }

    /// A photograph is read once, not once per surface.
    ///
    /// `SightedProvider` memoised per instance and the app built a new one per
    /// request, so the memo never hit: Vision ran for steps, for the title, and
    /// again for every tab that was opened. Reading it in `SolveBuilder` -- above
    /// the provider rather than below it -- makes five reads unrepresentable.
    @Test("a photograph is read once per solve")
    func photographIsReadOnce() async throws {
        let ocr = OCRCounter()
        let coordinator = SolveCoordinator(provider: { RecordingProvider() })

        coordinator.begin(try await Self.builder(ocr).photograph(Self.jpeg))
        await coordinator.settle()
        for surface in [Surface.lesson, .formulas, .videos] {
            coordinator.ensureLoaded(surface)
            await coordinator.settle()
        }

        let reads = await ocr.count
        #expect(reads == 1, "Vision ran \(reads) times for one photograph")
    }

    // MARK: - Requirement 3: failure is legible

    /// A retry used to cancel the tail of the chain, and the cancelled task
    /// returned without writing a terminal state -- so the surface it was going
    /// to fetch stayed `loading` for the life of the screen, with no error and
    /// no way out.
    @Test("retrying one surface does not strand another on a spinner")
    func retryDoesNotStrandASpinner() async throws {
        let spy = RecordingProvider()
        spy.fail(.steps, with: .contextExceeded)
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.begin(try Self.builder(OCRCounter()).typed("Solve for x: x^2 - 5x + 6 = 0"))
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
        let spy = RecordingProvider()
        let coordinator = SolveCoordinator(provider: { spy })

        coordinator.retry(.steps)
        await coordinator.settle()

        #expect(spy.questions().isEmpty, "asked the model \(spy.questions())")
        #expect(coordinator.stepsState.error == .nothingToSolve)
    }

    /// A photograph with nothing legible in it fails once, before a results
    /// screen exists, rather than four times inside it.
    @Test("a photograph nothing can be read from fails before any request")
    func unreadablePhotographFailsEarly() async {
        let builder = SolveBuilder { _ in "   \n  " }
        await #expect(throws: SolverError.self) {
            _ = try await builder.photograph(Self.jpeg)
        }
    }

    @Test("an empty typed problem is refused")
    func emptyTypedProblemIsRefused() {
        let builder = SolveBuilder { _ in "" }
        #expect(throws: SolverError.nothingToSolve) {
            _ = try builder.typed("   ")
        }
    }

    /// Whitespace is trimmed once, in the constructor, so the string shown and
    /// the string asked about are the same bytes.
    @Test("the question shown is the question asked")
    func questionIsTrimmedOnce() throws {
        let solve = try SolveBuilder { _ in "" }.typed("  2x + 3 = 7  \n")
        #expect(solve.question == "2x + 3 = 7")
        #expect(solve.source == .typed)
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

    private func record(_ surface: Surface, _ question: String) throws {
        lock.lock()
        seen[surface] = question
        let failure = failures[surface]
        lock.unlock()
        if let failure { throw failure }
    }

    func steps(for question: String) async throws -> [StepItem] {
        try record(.steps, question)
        return [StepItem(step: 1, title: "t", explanation: "e", math: "x = 1")]
    }
    func lesson(for question: String) async throws -> LessonContent {
        try record(.lesson, question)
        return LessonContent(title: "t", topic: "a", introduction: "i",
                             sections: [], keyTakeaway: nil)
    }
    func formulas(for question: String) async throws -> [FormulaItem] {
        try record(.formulas, question)
        return [FormulaItem(name: "n", formula: "x", description: "d")]
    }
    func videos(for question: String) async throws -> [VideoItem] {
        try record(.videos, question)
        return [VideoItem(title: "t", channel: "c", searchQuery: "q",
                          videoId: nil, thumbnailURL: nil)]
    }
    func chatReply(to message: String, about question: String,
                   history: [ChatMessage]) async throws -> String { "reply" }
}

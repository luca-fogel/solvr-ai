import Testing
import Foundation
@testable import SolvrCore

/// A provider that only ever sees text, and records what it was given.
private final class TextOnlySpy: SolutionProvider, @unchecked Sendable {
    var identifier: String { "spy" }
    var maxConcurrentRequests: Int { 1 }
    var isConfigured: Bool { true }
    var acceptsImageInput: Bool { false }

    private(set) var seen: [ProblemInput] = []
    private let lock = NSLock()

    private func record(_ input: ProblemInput) {
        lock.lock(); seen.append(input); lock.unlock()
    }

    func lesson(for problem: ProblemInput) async throws -> LessonContent {
        record(problem)
        return LessonContent(title: "t", topic: "a • b", introduction: "i",
                             sections: [], keyTakeaway: nil)
    }
    func steps(for problem: ProblemInput) async throws -> [StepItem] {
        record(problem)
        return [StepItem(step: 1, title: "s", explanation: "e", math: nil)]
    }
    func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        record(problem)
        return []
    }
    func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        record(problem)
        return []
    }
    func chatReply(to message: String, about problem: String,
                   history: [ChatMessage]) async throws -> String {
        "reply"
    }
    func title(for problem: ProblemInput) async -> String {
        record(problem)
        return "title"
    }
}

@Suite("Reading a photograph for a text-only backend")
struct SightedProviderTests {

    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])

    @Test("a photograph reaches a text-only model as recognised text")
    func imageBecomesText() async throws {
        let spy = TextOnlySpy()
        let sighted = SightedProvider(wrapping: spy) { _ in "\\int_0^1 x^2 dx" }

        _ = try await sighted.steps(for: .image(jpeg))

        #expect(spy.seen == [.text("\\int_0^1 x^2 dx")])
    }

    @Test("typed text is passed through untouched, and the recogniser never runs")
    func textIsNotRecognised() async throws {
        let spy = TextOnlySpy()
        let sighted = SightedProvider(wrapping: spy) { _ in
            Issue.record("the recogniser must not run for typed input")
            return ""
        }

        _ = try await sighted.steps(for: .text("solve x^2 = 4"))

        #expect(spy.seen == [.text("solve x^2 = 4")])
    }

    @Test("the wrapper reports that it accepts images even though the model does not")
    func capabilityIsReportedByTheWrapper() {
        let spy = TextOnlySpy()
        #expect(spy.acceptsImageInput == false)
        #expect(SightedProvider(wrapping: spy) { _ in "" }.acceptsImageInput == true)
    }

    @Test("the identifier records that the answer came via OCR, not native vision")
    func identifierRecordsTheDowngrade() {
        let sighted = SightedProvider(wrapping: TextOnlySpy()) { _ in "" }
        #expect(sighted.identifier == "spy+ocr")
    }

    @Test("one photograph is recognised once, not once per surface")
    func recognitionIsSharedAcrossTheFourSurfaces() async throws {
        let calls = Counter()
        let sighted = SightedProvider(wrapping: TextOnlySpy()) { _ in
            await calls.bump()
            return "x + 1 = 2"
        }

        _ = try await sighted.lesson(for: .image(jpeg))
        _ = try await sighted.steps(for: .image(jpeg))
        _ = try await sighted.formulas(for: .image(jpeg))
        _ = try await sighted.videos(for: .image(jpeg))

        #expect(await calls.count == 1)
    }

    @Test("a different photograph is recognised again rather than reusing the last one")
    func memoIsKeyedByTheImage() async throws {
        let spy = TextOnlySpy()
        let sighted = SightedProvider(wrapping: spy) { data in
            data.count == 7 ? "first" : "second"
        }

        _ = try await sighted.steps(for: .image(jpeg))
        _ = try await sighted.steps(for: .image(Data([0xFF, 0xD8])))

        #expect(spy.seen == [.text("first"), .text("second")])
    }

    @Test("a photograph with no readable text says so instead of asking the model nothing")
    func emptyRecognitionIsAnError() async {
        let sighted = SightedProvider(wrapping: TextOnlySpy()) { _ in "   \n  " }

        await #expect(throws: SolverError.self) {
            _ = try await sighted.steps(for: .image(jpeg))
        }
    }

    @Test("a failing recogniser surfaces as a readable error, not the Vision one")
    func recogniserFailureIsTranslated() async {
        struct Boom: Error {}
        let sighted = SightedProvider(wrapping: TextOnlySpy()) { _ in throw Boom() }

        do {
            _ = try await sighted.steps(for: .image(jpeg))
            Issue.record("expected a throw")
        } catch let error as SolverError {
            #expect(error.errorDescription?.contains("Could not parse image") == true)
        } catch {
            Issue.record("expected SolverError, got \(error)")
        }
    }

    @Test("a title still comes back when the photograph cannot be read")
    func titleDegradesRatherThanThrowing() async {
        let sighted = SightedProvider(wrapping: TextOnlySpy()) { _ in "" }
        #expect(await sighted.title(for: .image(jpeg)) == "Scanned Problem")
    }
}

private actor Counter {
    private(set) var count = 0
    func bump() { count += 1 }
}

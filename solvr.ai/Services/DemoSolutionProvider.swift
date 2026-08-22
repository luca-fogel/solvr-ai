import Foundation
import SolvrCore

/// Solvr with no key and no network, answering from bundled fixtures.
///
/// This is not new behaviour: demo mode was already a backend, hand-inlined as
/// fourteen short-circuit blocks at the top of twelve methods on the Anthropic
/// manager. Extracting it deletes all fourteen and, more usefully, makes it the
/// second conformance to `SolutionProvider` -- which is what demonstrates the
/// protocol is a real seam rather than a rename.
///
/// Two properties of the old arrangement are preserved deliberately, because
/// both are load-bearing and neither is obvious:
///
/// - The fixtures are raw JSON *text* carrying unescaped LaTeX, decoded through
///   the production `LLMJSON` ladder. Demo mode therefore exercises the repair
///   layer on every launch rather than bypassing it, which makes the screenshot
///   run a regression test on the parser. A future provider that returns typed
///   values directly -- guided generation -- would quietly stop testing it.
/// - The pause is real. Without it the loading and shimmer states are
///   unreachable, and they are a third of the interface.
struct DemoSolutionProvider: SolutionProvider {

    var identifier: String { "demo" }

    /// Matches the hosted backend so the demo exercises the same fan-out.
    var maxConcurrentRequests: Int { 4 }

    /// Always. Needing no configuration is the entire point.
    var isConfigured: Bool { true }

    /// It ignores the image and returns the same fixture, which is honest: the
    /// demo is not pretending to read anything.
    var acceptsImageInput: Bool { true }

    func lesson(for problem: ProblemInput) async throws -> LessonContent {
        await DemoMode.pause()
        return try DemoMode.decode(LessonContent.self, from: DemoFixtures.lesson, label: "lesson")
    }

    func steps(for problem: ProblemInput) async throws -> [StepItem] {
        await DemoMode.pause()
        return try DemoMode.decode([StepItem].self, from: DemoFixtures.steps, label: "steps")
    }

    func formulas(for problem: ProblemInput) async throws -> [FormulaItem] {
        await DemoMode.pause()
        return try DemoMode.decode([FormulaItem].self, from: DemoFixtures.formulas, label: "formulas")
    }

    func videos(for problem: ProblemInput) async throws -> [VideoItem] {
        await DemoMode.pause()
        return try DemoMode.decode([VideoItem].self, from: DemoFixtures.videos, label: "videos")
    }

    func chatReply(to message: String,
                   about problem: String,
                   history: [ChatMessage]) async throws -> String {
        await DemoMode.pause()
        return DemoFixtures.chatReply
    }

    /// No pause: the title is fetched alongside the four surfaces and delaying
    /// it only delays the header.
    func title(for problem: ProblemInput) async -> String {
        DemoFixtures.title
    }
}

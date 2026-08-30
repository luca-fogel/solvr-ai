#if SOLVR_DEMO
import Foundation

/// Solvr with no key and no network, answering from bundled fixtures.
///
/// This is not new behaviour: demo mode was already a backend, hand-inlined as
/// fourteen short-circuit blocks at the top of twelve methods on the Anthropic
/// manager. Extracting it deleted all fourteen and, more usefully, made it the
/// second conformance to `SolutionProvider` -- which is what shows the protocol
/// is a real seam rather than a rename.
///
/// It lives here rather than in the app so the evaluation harness can run the
/// whole pipeline -- compliance, grading, reporting -- with no key and no spend.
/// A harness that can only be exercised by paying for it does not get exercised.
///
/// Two properties are preserved deliberately, because both are load-bearing and
/// neither is obvious:
///
/// - The fixtures are raw JSON *text* carrying unescaped LaTeX, decoded through
///   the production `LLMJSON` ladder. Demo mode therefore exercises the repair
///   layer on every launch rather than bypassing it, which makes the screenshot
///   run a regression test on the parser. A provider that returned typed values
///   directly -- guided generation -- would quietly stop testing it.
/// - The pause is real. Without it the loading and shimmer states are
///   unreachable, and they are a third of the interface. The harness passes zero.
public struct FixtureSolutionProvider: SolutionProvider {

    private let latency: Duration
    private let observe: (@Sendable (String, LLMJSON.Compliance) -> Void)?

    public init(latency: Duration = .zero,
                observe: (@Sendable (String, LLMJSON.Compliance) -> Void)? = nil) {
        self.latency = latency
        self.observe = observe
    }

    public var identifier: String { "demo/fixtures" }

    /// Matches the hosted backend so the demo exercises the same fan-out.
    public var maxConcurrentRequests: Int { 4 }

    /// Always. Needing no configuration is the entire point.
    public var isConfigured: Bool { true }

    private func pause() async {
        guard latency > .zero else { return }
        try? await Task.sleep(for: latency)
    }

    private func decode<T: Decodable>(_ type: T.Type,
                                      from json: String,
                                      label: String) throws -> T {
        guard let decoded = LLMJSON.decode(type, from: json) else {
            throw SolverError.decodingFailed(
                context: "\(label): demo fixture '\(label)' failed to parse")
        }
        observe?(label, decoded.compliance)
        return decoded.value
    }

    public func lesson(for question: String) async throws -> LessonContent {
        await pause()
        return try decode(LessonContent.self, from: DemoFixtures.lesson, label: "lesson")
    }

    public func steps(for question: String) async throws -> [StepItem] {
        await pause()
        return try decode([StepItem].self, from: DemoFixtures.steps, label: "steps")
    }

    public func formulas(for question: String) async throws -> [FormulaItem] {
        await pause()
        return try decode([FormulaItem].self, from: DemoFixtures.formulas, label: "formulas")
    }

    public func videos(for question: String) async throws -> [VideoItem] {
        await pause()
        return try decode([VideoItem].self, from: DemoFixtures.videos, label: "videos")
    }

    public func chatReply(to message: String,
                          about question: String,
                          history: [ChatMessage]) async throws -> String {
        await pause()
        return DemoFixtures.chatReply
    }

}
#endif  // SOLVR_DEMO

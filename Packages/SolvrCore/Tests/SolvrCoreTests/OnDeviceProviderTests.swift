#if canImport(FoundationModels)
import Testing
import Foundation
@testable import SolvrCore

/// The parts of the on-device provider that do not need a model: what happens
/// to the model's answer between generation and the screen.
@Suite("On-device provider, without the model")
struct OnDeviceProviderTests {

    private func step(_ n: Int, _ title: String, _ explanation: String = "",
                      math: String? = nil) -> StepItem {
        StepItem(step: n, title: title, explanation: explanation, math: math)
    }

    /// Verbatim from an iOS run: step 6 "State the solution" and an appended
    /// step 7 "Final answer", both `(x, y) = (7, 3)` apart from spacing.
    @Test("an answer the working already ends on is marked, not repeated")
    @available(macOS 26.0, iOS 26.0, *)
    func finalMathNotRepeated() {
        let steps = [step(1, "Add"), step(2, "State the solution", math: "(x,y) = (7,3)")]
        let out = OnDeviceProvider.attachingFinalAnswer(to: steps, math: "(x, y) = (7, 3)", prose: nil)
        #expect(out.count == 2)
        #expect(out.last?.isFinalAnswer == true)
    }

    /// Verbatim from a Mac run: a step titled "Final answer" saying the median
    /// sentence, then the same sentence again as the appended answer.
    @Test("a word answer the last step already says is marked, not repeated")
    @available(macOS 26.0, iOS 26.0, *)
    func finalProseNotRepeated() {
        let sentence = "The median of the data set is 5.5."
        let steps = [step(1, "Sort", math: "2, 3, 4, 7, 7, 9"), step(2, "Final answer", sentence)]
        let out = OnDeviceProvider.attachingFinalAnswer(to: steps, math: nil, prose: sentence)
        #expect(out.count == 2)
        #expect(out.last?.isFinalAnswer == true)
    }

    @Test("a different answer is still added as its own step")
    @available(macOS 26.0, iOS 26.0, *)
    func differentAnswerAppended() {
        let steps = [step(1, "Simplify", math: "x = (-3 \\pm 5)/4")]
        let out = OnDeviceProvider.attachingFinalAnswer(to: steps, math: "x = 1/2", prose: nil)
        #expect(out.count == 2)
        #expect(out.last?.title == "Final answer")
        #expect(out.last?.isFinalAnswer == true)
        #expect(out.first?.isFinalAnswer == false)
    }
}
#endif

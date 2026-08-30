import Testing
import Foundation
@testable import SolvrCore

/// The rewrite that happens on the way *in* to the model.
///
/// Every case here corresponds to a measured failure, recorded in
/// `MathNotation.plainForModel`'s own documentation: `x³ · sin(x)` was refused
/// outright and `x^3 · sin(x)` overflowed the context window, on every one of
/// three identical greedy runs.
@Suite("Problem text, written the way the model can read it")
struct PlainForModelTests {

    @Test("superscripts become carets")
    func superscripts() {
        #expect(MathNotation.plainForModel("x³") == "x^3")
        #expect(MathNotation.plainForModel("x² - 5x + 6 = 0") == "x^2 - 5x + 6 = 0")
        #expect(MathNotation.plainForModel("x¹⁰") == "x^{10}")
    }

    @Test("the multiplication characters a keyboard produces become an asterisk")
    func operators() {
        #expect(MathNotation.plainForModel("x³ · sin(x)") == "x^3 * sin(x)")
        #expect(MathNotation.plainForModel("3 × 4") == "3 * 4")
        #expect(MathNotation.plainForModel("8 ÷ 2") == "8 / 2")
    }

    @Test("a Unicode minus becomes a hyphen, which is what the model reads")
    func minusSign() {
        #expect(MathNotation.plainForModel("5 − 3") == "5 - 3")
    }

    @Test("Greek letters and relations are left alone -- they are measured to work")
    func leftAlone() {
        let trig = "Solve for θ: 2sin(θ) - 1 = 0, where 0 ≤ θ ≤ 2π"
        #expect(MathNotation.plainForModel(trig) == trig)
    }

    @Test("plain ASCII is untouched, so this is safe to apply to everything")
    func asciiUnchanged() {
        for text in ["Solve for x: 3x + 7 = 22",
                     "Find the area of a triangle with sides 5, 12, and 13",
                     "d/dx x^2"] {
            #expect(MathNotation.plainForModel(text) == text)
        }
    }

    @Test("every sample problem survives the rewrite as recognisable maths")
    func sampleProblems() {
        for sample in SampleProblems.all {
            let plain = MathNotation.plainForModel(sample.text)
            #expect(!plain.isEmpty)
            #expect(!plain.contains("³"))
            #expect(!plain.contains("·"))
        }
    }

    @Test("the chips and the measured set are the same six strings")
    func oneSourceOfTruth() {
        // The point of SampleProblems: a claim that "the examples work" is a
        // graded run of the exact strings the chips insert, not of six strings
        // that used to match them.
        #expect(SampleProblems.topics.count == SampleProblems.all.count)
        for sample in SampleProblems.all {
            #expect(SampleProblems.byTopic[sample.topic] == sample.text)
        }
    }
}

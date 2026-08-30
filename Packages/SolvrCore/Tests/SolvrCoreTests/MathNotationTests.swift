import Testing
import Foundation
@testable import SolvrCore

/// The inputs here are not invented. They are what Apple's on-device model
/// actually returned when asked, twice and increasingly firmly, for LaTeX.
@Suite("Plain-text maths to LaTeX")
struct MathNotationTests {

    @Test("LaTeX is returned untouched -- the property that makes this safe")
    func alreadyLaTeXIsUntouched() {
        for input in [#"\frac{d}{dx}x^{2} = 2x"#,
                      #"\int_{0}^{1} 3x^{2}\,dx"#,
                      #"\left[x^{3}\right]_{0}^{1}"#,
                      #"\sqrt{x^2+y^2}"#] {
            #expect(MathNotation.toLaTeX(input) == input)
        }
    }

    @Test("the integral the on-device model actually emitted")
    func observedIntegral() {
        // Verbatim from a device run.
        #expect(MathNotation.toLaTeX("∫[0,1] 3x^2 dx") == #"\int_{0}^{1} 3x^{2} dx"#)
    }

    @Test("bare exponents get braces, parenthesised ones get unwrapped")
    func exponents() {
        #expect(MathNotation.toLaTeX("x^3") == "x^{3}")
        #expect(MathNotation.toLaTeX("(3/3)x^(2+1)") == "(3/3)x^{2+1}")
        #expect(MathNotation.toLaTeX("F(1) = 1^3 = 1") == "F(1) = 1^{3} = 1")
        #expect(MathNotation.toLaTeX("x^-1") == "x^{-1}")
    }

    @Test("already-braced exponents are not double-wrapped, so this is idempotent")
    func idempotent() {
        let once = MathNotation.toLaTeX("∫[0,1] 3x^2 dx")
        #expect(MathNotation.toLaTeX(once) == once)
    }

    @Test("Unicode symbols become commands")
    func unicodeSymbols() {
        #expect(MathNotation.toLaTeX("π r^2") == #"\pi r^{2}"#)
        #expect(MathNotation.toLaTeX("a ≠ b") == #"a \neq b"#)
        #expect(MathNotation.toLaTeX("x → ∞") == #"x \to \infty"#)
    }

    @Test("function names become commands, and sqrt takes its argument")
    func functions() {
        #expect(MathNotation.toLaTeX("sqrt(x+1)") == #"\sqrt{x+1}"#)
        #expect(MathNotation.toLaTeX("sin(x) cos(x)") == #"\sin(x) \cos(x)"#)
    }

    @Test("an interval in prose is not mistaken for integral limits")
    func intervalsAreLeftAlone() {
        // Only a limit-taking operator triggers the bracket rule.
        #expect(MathNotation.toLaTeX("x in [0,1]") == "x in [0,1]")
    }

    @Test("empty and non-mathematical strings pass through")
    func degenerate() {
        #expect(MathNotation.toLaTeX("") == "")
        #expect(MathNotation.toLaTeX("Apply the power rule") == "Apply the power rule")
    }

    @Test("everything it produces actually parses -- no half-converted output")
    func outputIsWellFormed() {
        // Balanced braces is the cheap structural check; the harness renders the
        // real thing through KaTeX.
        for input in ["∫[0,1] 3x^2 dx", "x^(2+1)", "sqrt(x)", "π r^2", "F(1) - F(0)"] {
            let out = MathNotation.toLaTeX(input)
            #expect(out.filter { $0 == "{" }.count == out.filter { $0 == "}" }.count,
                    "unbalanced braces in \(out)")
        }
    }
}

/// Fields meant for mathematics that arrive holding a sentence.
///
/// The input below is verbatim from the running app: asked for the algebra of a
/// step, the on-device model returned a sentence, KaTeX rendered it as italics
/// with the spaces collapsed, and the resulting box was wide enough to push the
/// page sideways and clip the text beside it.
@Suite("Prose in a maths field")
struct ProseDetection {

    @Test("a sentence is recognised as prose")
    func sentence() {
        #expect(MathNotation.looksLikeProse(
            "Let f(x) = 3x^2. Then, the antiderivative of f(x) is F(x) = x^3."))
        #expect(MathNotation.looksLikeProse(
            "The derivative of the function with respect to x"))
    }

    @Test("real working is not")
    func working() {
        for maths in [#"\int_{0}^{1} 3x^{2}\,dx = 1"#,
                      #"\frac{d}{dx}x^{3} = 3x^{2}"#,
                      "3x = 22 - 7 = 15",
                      #"\left[x^{3}\right]_{0}^{1}"#,
                      #"x = \pm\sqrt{4}"#,
                      #"\tan\left(\frac{\pi}{4}\right) = 1"#] {
            #expect(!MathNotation.looksLikeProse(maths), "misjudged: \(maths)")
        }
    }

    @Test(#"\text{} is exempt, because that is LaTeX's own way to carry words"#)
    func textMacroIsExempt() {
        #expect(!MathNotation.looksLikeProse(
            #"\text{area under the curve} = \int_{0}^{1} f(x)\,dx"#))
    }

    @Test("short function names and variables survive")
    func shortNames() {
        #expect(!MathNotation.looksLikeProse("sin(x) cos(x) = \\frac{1}{2}\\sin(2x)"))
    }
}

/// Regressions from the first run of the app on a real iPhone, where the six
/// topic-chip problems produced maths that was wrong, garbled or missing.
@Suite("Conversions that used to corrupt correct maths")
struct MathNotationRegressionTests {

    @Test("a function name inside a longer word is left alone")
    func functionNamesAreNotWordPrefixes() {
        // Every one of these became an undefined control sequence -- \sine,
        // \cost, \expression -- which KaTeX drops or paints red. This is a large
        // part of what "the rendering is garbled" meant.
        for word in ["sine", "cosine", "cost", "tangent", "expression",
                     "exponent", "logistic", "secant", "cotangent"] {
            #expect(MathNotation.toLaTeX(word) == word, "\(word) was rewritten")
        }
    }

    @Test("a real function call still becomes a command")
    func functionCallsStillConvert() {
        #expect(MathNotation.toLaTeX("sin(x)") == #"\sin(x)"#)
        #expect(MathNotation.toLaTeX("2sin(θ) - 1 = 0") == #"2\sin(\theta) - 1 = 0"#)
        #expect(MathNotation.toLaTeX("log(100)") == #"\log(100)"#)
    }

    @Test("the radical takes its argument -- √16 was rendering as √1 times 6")
    func radicalTakesItsArgument() {
        #expect(MathNotation.toLaTeX("√16") == #"\sqrt{16}"#)
        #expect(MathNotation.toLaTeX("√(x+1)") == #"\sqrt{x+1}"#)
        #expect(MathNotation.toLaTeX("√x + √y") == #"\sqrt{x} + \sqrt{y}"#)
        #expect(MathNotation.toLaTeX("√2.5") == #"\sqrt{2.5}"#)
    }

    @Test("a radical with nothing after it is left as a bare command, not a corruption")
    func radicalWithNoArgument() {
        #expect(MathNotation.toLaTeX("√") == #"\sqrt"#)
    }

    @Test("converting twice changes nothing, radicals included")
    func radicalsAreIdempotent() {
        for input in ["√16", "√(x+1)", "√x + √y", "sin(x) + √2"] {
            let once = MathNotation.toLaTeX(input)
            #expect(MathNotation.toLaTeX(once) == once, "\(input) was not stable")
        }
    }

    @Test("the six problems the topic chips insert are all convertible")
    func sampleProblemsSurviveConversion() {
        // Not an assertion about the model: an assertion that the strings the
        // app inserts do not themselves trip the converter.
        for sample in SampleProblems.all {
            let converted = MathNotation.toLaTeX(sample.text)
            #expect(!converted.contains(#"\sine"#))
            #expect(!converted.contains(#"\sqrt1"#))
            #expect(!converted.isEmpty)
        }
    }
}

/// The KaTeX failures an on-device run actually produced, twenty-one of thirty
/// of them, in two shapes.
@Suite("What KaTeX refused to render")
struct MathNotationRenderFailureTests {

    @Test("a bracketed radical is the thing under the root, not its index")
    func bracketedRadical() {
        // Heron's formula, as the model writes it. `\sqrt[...]` with no
        // argument is "unexpected end of input" and the whole expression is
        // lost.
        #expect(MathNotation.toLaTeX("Area = √[s(s-a)(s-b)(s-c)]")
                == #"Area = \sqrt{s(s-a)(s-b)(s-c)}"#)
        #expect(MathNotation.toLaTeX("√[20(20-5)]") == #"\sqrt{20(20-5)}"#)
    }

    @Test("a literal backslash-n is a line break, not a command")
    func literalNewline() {
        #expect(MathNotation.toLaTeX(#"a = 1 \nb = 2"#) == #"a = 1  \quad b = 2"#)
        #expect(MathNotation.toLaTeX(#"sin(θ) = 1/2 \nθ = π/6"#).contains(#"\quad"#))
    }

    @Test("commands that really do start with n survive")
    func realCommandsSurvive() {
        // `x \neq y` has a space before the backslash exactly like the broken
        // case, so the guard cannot be "preceded by whitespace".
        for latex in [#"x \neq y"#, #"\nabla f"#, #"a \ne b"#, #"\nu = 1"#] {
            #expect(MathNotation.toLaTeX(latex) == latex)
        }
    }
}

import Testing
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

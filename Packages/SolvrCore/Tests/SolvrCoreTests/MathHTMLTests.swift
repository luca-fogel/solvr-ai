import Testing
import Foundation
@testable import SolvrCore

/// Maths goes into the page unescaped so its backslashes survive. That is
/// right, and it was also how a `<` swallowed a line and a `<script>` ran.
@Suite("LaTeX in an HTML page")
struct MathHTMLTests {

    @Test("the three characters an HTML parser acts on are escaped")
    func htmlSyntaxIsNeutralised() {
        #expect(MathHTML.escapeLaTeX("a < b") == "a &lt; b")
        #expect(MathHTML.escapeLaTeX("x > 0") == "x &gt; 0")
        #expect(MathHTML.escapeLaTeX("P(A) & P(B)") == "P(A) &amp; P(B)")
    }

    @Test("ampersands are escaped before the others, not after")
    func ampersandFirst() {
        // Escaping `<` first would leave `&lt;` and then turn its own ampersand
        // into `&amp;lt;`, which renders as the literal text "&lt;".
        #expect(MathHTML.escapeLaTeX("<") == "&lt;")
        #expect(MathHTML.escapeLaTeX("&lt;") == "&amp;lt;")
    }

    @Test("a script tag cannot reach the web view as markup")
    func scriptIsNeutralised() {
        let escaped = MathHTML.escapeLaTeX("<script>fetch('http://x')</script>")
        #expect(!escaped.contains("<"))
        #expect(!escaped.contains(">"))
    }

    @Test("LaTeX itself is untouched, which is the whole reason not to escapeHTML it")
    func latexSurvives() {
        for latex in [#"\frac{a}{b}"#, #"x^{2}"#, #"\int_{0}^{1} 3x^{2}\,dx"#,
                      #"\left[ x^{3} \right]_{0}^{1}"#, #"\sqrt{16}"#] {
            #expect(MathHTML.escapeLaTeX(latex) == latex)
        }
    }

    @Test("dollar delimiters are stripped, since the page adds its own")
    func dollarsAreStripped() {
        #expect(MathHTML.escapeLaTeX("$$x^2$$") == "x^2")
        #expect(MathHTML.escapeLaTeX("$x$") == "x")
    }

    @Test("paired inline dollars become KaTeX delimiters")
    func pairedInlineMath() {
        #expect(MathHTML.processInlineMath("the value $x$ is") == #"the value \(x\) is"#)
        #expect(MathHTML.processInlineMath("$a$ and $b$") == #"\(a\) and \(b\)"#)
    }

    @Test("an unpaired dollar leaves the text alone instead of eating the page")
    func unpairedDollarIsLeftAlone() {
        // The old version emitted an opening \( with no close, and KaTeX's
        // auto-render then swallowed everything after it.
        #expect(MathHTML.processInlineMath("costs $5 to run") == "costs $5 to run")
        #expect(MathHTML.processInlineMath("$a$ and $b") == "$a$ and $b")
    }

    @Test("text with no maths is returned unchanged")
    func noDollarsNoChange() {
        #expect(MathHTML.processInlineMath("plain sentence") == "plain sentence")
    }
}

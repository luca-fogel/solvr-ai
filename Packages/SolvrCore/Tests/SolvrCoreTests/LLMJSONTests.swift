import Foundation
import Testing
@testable import SolvrCore

// Local stand-ins for the app's models, so these tests depend on nothing but
// SolvrCore and can run in a couple of seconds with no Xcode and no simulator.
private struct Step: Codable, Equatable {
    let step: Int
    let title: String
    let explanation: String
    let math: String?
}

private struct Lesson: Codable, Equatable {
    let title: String
    let introduction: String
}

@Suite("Code fences")
struct CodeFences {

    @Test("a ```json fence is stripped from both ends")
    func fenced() {
        let raw = "```json\n{\"a\": 1}\n```"
        #expect(LLMJSON.stripCodeFences(raw) == "{\"a\": 1}")
    }

    @Test("a bare ``` fence is stripped too")
    func bareFence() {
        #expect(LLMJSON.stripCodeFences("```\n[]\n```") == "[]")
    }

    @Test("a fence with no newline after it does not eat the payload")
    func fenceWithoutNewline() {
        #expect(LLMJSON.stripCodeFences("```{\"a\":1}") == "{\"a\":1}")
    }

    @Test("unfenced JSON is returned unchanged")
    func unfenced() {
        #expect(LLMJSON.stripCodeFences("  {\"a\":1}  ") == "{\"a\":1}")
    }
}

@Suite("LaTeX escape repair")
struct LaTeXRepair {

    // The cases the repair exists for.

    @Test("an unescaped LaTeX command is doubled so JSON accepts it")
    func fracIsDoubled() {
        let raw = #"{"math": "\frac{1}{2}"}"#
        let out = LLMJSON.repairLaTeXEscapes(raw)
        #expect(out == #"{"math": "\\frac{1}{2}"}"#)
        #expect((try? JSONSerialization.jsonObject(with: Data(out.utf8))) != nil)
    }

    @Test("a command whose first letter is not a JSON escape needs no word list")
    func unambiguousCommands() {
        for cmd in ["alpha", "int", "sqrt", "sum", "cdot", "le", "ge", "pi"] {
            let out = LLMJSON.repairLaTeXEscapes("{\"m\": \"\\\(cmd) x\"}")
            #expect(out.contains("\\\\\(cmd)"), "\\\(cmd) should have been doubled")
        }
    }

    @Test("backslash before a brace or pipe is not a legal escape, so it is LaTeX")
    func punctuationEscapes() {
        let out = LLMJSON.repairLaTeXEscapes(#"{"m": "\{x\|y\}"}"#)
        #expect(out == #"{"m": "\\{x\\|y\\}"}"#)
        #expect((try? JSONSerialization.jsonObject(with: Data(out.utf8))) != nil)
    }

    // The cases the OLD implementation broke. Each of these fails if the repair
    // goes back to doubling every backslash it sees.

    @Test("an escaped quote survives -- the bug that corrupted valid documents")
    func escapedQuoteIsNotTouched() {
        let raw = #"{"title": "the \"chain rule\" explained"}"#
        let out = LLMJSON.repairLaTeXEscapes(raw)
        #expect(out == raw)
        let decoded = try? JSONDecoder().decode(Lesson.self, from: Data(
            #"{"title": "the \"chain rule\" explained", "introduction": "x"}"#.utf8))
        #expect(decoded != nil)
    }

    @Test("a newline escape followed by prose stays a newline")
    func newlineEscapeSurvives() {
        let raw = #"{"explanation": "First line.\nNext, differentiate."}"#
        #expect(LLMJSON.repairLaTeXEscapes(raw) == raw)
    }

    @Test("an already-escaped backslash is left as it is, not turned into four")
    func doubleBackslashIsStable() {
        let raw = #"{"m": "\\frac{1}{2}"}"#
        #expect(LLMJSON.repairLaTeXEscapes(raw) == raw)
    }

    @Test("repair is idempotent: running it twice changes nothing further")
    func idempotent() {
        let once = LLMJSON.repairLaTeXEscapes(#"{"m": "\frac{a}{b}", "t": "say \"hi\""}"#)
        #expect(LLMJSON.repairLaTeXEscapes(once) == once)
    }

    @Test("a unicode escape is preserved")
    func unicodeEscape() {
        let raw = #"{"t": "CALCULUS \u2022 LIMITS"}"#
        #expect(LLMJSON.repairLaTeXEscapes(raw) == raw)
    }

    @Test("a \\u that is not four hex digits is LaTeX, not an escape")
    func bogusUnicodeEscapeIsLaTeX() {
        // \union is a plausible thing for a model to emit; \u + "nion" is not a
        // valid JSON escape, so it must be doubled rather than kept.
        let out = LLMJSON.repairLaTeXEscapes(#"{"m": "A \union B"}"#)
        #expect(out.contains(#"\\union"#))
    }

    @Test("ambiguous commands are decided by the word, not the letter")
    func ambiguousLetters() {
        // \times, \frac, \beta, \nu, \rho are all JSON escape letters.
        for cmd in ["times", "frac", "beta", "nu", "rho", "theta", "text"] {
            let out = LLMJSON.repairLaTeXEscapes("{\"m\": \"\\\(cmd)\"}")
            #expect(out.contains("\\\\\(cmd)"), "\\\(cmd) is LaTeX and should be doubled")
        }
    }

    @Test("a tab escape before a letter is kept when the word is not a command")
    func tabBeforeWord() {
        // \tricky is not in the command list, and \t is a valid escape, so the
        // conservative reading wins: a broken parse beats silent corruption.
        let out = LLMJSON.repairLaTeXEscapes(#"{"m": "a\tricky"}"#)
        #expect(out == #"{"m": "a\tricky"}"#)
    }

    @Test("backslashes outside strings are untouched")
    func outsideStrings() {
        #expect(LLMJSON.repairLaTeXEscapes("[\\]") == "[\\]")
    }
}

@Suite("The decode ladder")
struct DecodeLadder {

    @Test("well formed JSON parses on the first rung and says so")
    func strict() {
        let raw = #"[{"step":1,"title":"Set up","explanation":"Start here","math":null}]"#
        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.provenance == .strict)
        #expect(out?.value.first?.title == "Set up")
    }

    @Test("fenced JSON with raw LaTeX parses on the repair rung")
    func repaired() {
        let raw = """
        ```json
        [{"step":1,"title":"Differentiate","explanation":"Apply the power rule","math":"\\frac{d}{dx}x^2 = 2x"}]
        ```
        """
        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.provenance == .repaired)
        #expect(out?.value.first?.math == #"\frac{d}{dx}x^2 = 2x"#)
    }

    @Test("provenance distinguishes a clean parse from a rescued one")
    func provenanceIsMeaningful() {
        let clean = LLMJSON.decode([Step].self, from: #"[{"step":1,"title":"a","explanation":"b","math":null}]"#)
        let rescued = LLMJSON.decode([Step].self, from: "```json\n[{\"step\":1,\"title\":\"a\",\"explanation\":\"b\",\"math\":\"\\frac12\"}]\n```")
        #expect(clean?.provenance == .strict)
        #expect(rescued?.provenance != .strict)
    }

    @Test("valid JSON can still be the wrong answer -- the case that set the order of the ladder")
    func validJSONCanStillBeWrong() {
        // "\frac" is *valid* JSON, because \f is a form feed. A ladder that
        // tries strict parsing first therefore succeeds and hands back
        // "<FF>rac{1}{2}" with no error anywhere.
        let raw = #"[{"step":1,"title":"a","explanation":"b","math":"\frac{1}{2}"}]"#

        let naive = try? JSONDecoder().decode([Step].self, from: Data(raw.utf8))
        #expect(naive?.first?.math == "\u{0C}rac{1}{2}", "this is the corruption being avoided")

        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.value.first?.math == #"\frac{1}{2}"#)
        #expect(out?.provenance == .repaired)
    }

    @Test("a response truncated by a token limit returns nil rather than a partial value")
    func truncated() {
        let raw = #"[{"step":1,"title":"Set up","explanation":"We begin by"#
        #expect(LLMJSON.decode([Step].self, from: raw) == nil)
    }

    @Test("prose instead of JSON returns nil")
    func prose() {
        let raw = "Sure! Here is how to solve it: first, differentiate both sides."
        #expect(LLMJSON.decode([Step].self, from: raw) == nil)
    }

    @Test("an empty response returns nil")
    func empty() {
        #expect(LLMJSON.decode([Step].self, from: "") == nil)
        #expect(LLMJSON.decode([Step].self, from: "   \n ") == nil)
    }

    @Test("JSON of the wrong shape returns nil rather than a half-filled object")
    func wrongShape() {
        #expect(LLMJSON.decode([Step].self, from: #"{"steps": []}"#) == nil)
    }

    @Test("a null math field is absent, not an empty string")
    func nullIsAbsent() {
        let out = LLMJSON.decode([Step].self, from: #"[{"step":1,"title":"a","explanation":"b","math":null}]"#)
        #expect(out?.value.first?.math == nil)
    }
}

@Suite("HTML escaping")
struct HTMLEscaping {

    @Test("the five dangerous characters are escaped")
    func escapes() {
        #expect(LLMJSON.escapeHTML("a<b>&\"'") == "a&lt;b&gt;&amp;&quot;&#39;")
    }

    @Test("model output containing a less-than sign cannot open a tag")
    func inequalityIsNotMarkup() {
        let out = LLMJSON.escapeHTML("if x < 0 then <script>alert(1)</script>")
        #expect(!out.contains("<script>"))
        #expect(out.contains("&lt;script&gt;"))
    }

    @Test("ordinary maths text is unchanged")
    func plainText() {
        #expect(LLMJSON.escapeHTML("x^2 + 2x - 1 = 0") == "x^2 + 2x - 1 = 0")
    }
}


@Suite("Finding the JSON in a chatty answer")
struct SliceJSONBody {

    @Test("prose before and after an object is discarded")
    func prosePadding() {
        let raw = "Sure! Here you go:\n{\"title\": \"Limits\"}\nLet me know if you want more."
        #expect(LLMJSON.sliceJSONBody(raw, shape: .object) == #"{"title": "Limits"}"#)
    }

    @Test("the outermost braces win, not the first closing brace")
    func nestedObjects() {
        let raw = #"prefix {"a": {"b": 1}, "c": 2} suffix"#
        #expect(LLMJSON.sliceJSONBody(raw, shape: .object) == #"{"a": {"b": 1}, "c": 2}"#)
    }

    @Test("an array is sliced by its own brackets")
    func arrays() {
        let raw = "Here: [{\"step\":1}] done"
        #expect(LLMJSON.sliceJSONBody(raw, shape: .array) == #"[{"step":1}]"#)
    }

    @Test("text with no JSON at all is returned unchanged, so the decoder reports the error")
    func noJSON() {
        #expect(LLMJSON.sliceJSONBody("I cannot help with that.", shape: .object) == "I cannot help with that.")
    }

    @Test("a closing brace before the opening one is not a span")
    func invertedBraces() {
        #expect(LLMJSON.sliceJSONBody("} then {", shape: .object) == "} then {")
    }
}

/// The instrument itself, under test.
///
/// A backend comparison is only as good as its measure of compliance, and this
/// measure used to under-report. `provenance` was derived by comparing the
/// repaired string against the *post-fence-strip* one, so a fence was invisible;
/// and slicing prose off the ends happened at the call site, so that was
/// invisible too. Both are the failures a small local model produces most, which
/// means the error ran in the flattering direction.
@Suite("What the compliance record measures")
struct ComplianceInstrument {

    private let bare = #"[{"step":1,"title":"a","explanation":"b","math":null}]"#

    @Test("clean JSON reports nothing done to it")
    func cleanIsClean() {
        let out = LLMJSON.decode([Step].self, from: bare)
        #expect(out?.compliance.isClean == true)
        #expect(out?.compliance == LLMJSON.Compliance())
    }

    @Test("a fence is recorded -- it used to report .strict")
    func fenceIsNoLongerInvisible() {
        let out = LLMJSON.decode([Step].self, from: "```json\n\(bare)\n```")
        #expect(out?.compliance.wasFenced == true)
        #expect(out?.compliance.isClean == false)
        #expect(out?.provenance != .strict, "a fenced response is not a compliant one")
    }

    @Test("prose around the JSON is recorded -- it used to happen outside decode")
    func sliceIsNoLongerInvisible() {
        let raw = "Sure! Here is the JSON:\n\(bare)\nLet me know if you need anything else."
        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.compliance.wasSliced == true)
        #expect(out?.provenance != .strict)
        #expect(out?.value.first?.title == "a")
    }

    @Test("escape repair is recorded separately from fencing and slicing")
    func repairIsItsOwnSignal() {
        let raw = #"[{"step":1,"title":"a","explanation":"b","math":"\frac{1}{2}"}]"#
        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.compliance.escapesRepaired == true)
        #expect(out?.compliance.wasFenced == false)
        #expect(out?.compliance.wasSliced == false)
    }

    @Test("the three failures are counted independently when they arrive together")
    func signalsAreIndependent() {
        let raw = """
        Here you go:
        ```json
        [{"step":1,"title":"a","explanation":"b","math":"\\frac{1}{2}"}]
        ```
        Hope that helps.
        """
        let out = LLMJSON.decode([Step].self, from: raw)
        #expect(out?.compliance.wasFenced == true)
        #expect(out?.compliance.escapesRepaired == true)
        #expect(out?.value.first?.math == #"\frac{1}{2}"#)
    }

    @Test("decode slices without being told the shape, for objects and arrays alike")
    func shapeIsInferred() {
        let object = LLMJSON.decode(Lesson.self, from: #"Here: {"title":"T","introduction":"i"}"#)
        #expect(object?.value.title == "T")
        #expect(object?.compliance.wasSliced == true)

        let array = LLMJSON.decode([Step].self, from: "Here: \(bare)")
        #expect(array?.value.count == 1)
        #expect(array?.compliance.wasSliced == true)
    }

    @Test("isClean is the number to compare across backends, and a fence disqualifies")
    func isCleanIsTheHeadlineMetric() {
        let clean = LLMJSON.decode([Step].self, from: bare)
        let fenced = LLMJSON.decode([Step].self, from: "```\n\(bare)\n```")
        // Before this change both of these reported .strict, so a model that
        // fenced every single response scored a perfect compliance rate.
        #expect(clean?.compliance.isClean == true)
        #expect(fenced?.compliance.isClean == false)
    }
}

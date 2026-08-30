import Testing
import Foundation
@testable import SolvrCore

/// What the converter is *for*, asked of the renderer rather than of a reviewer.
///
/// `MathNotationTests` asserts what the conversion produces, string by string.
/// That is worth having and it is not sufficient: every one of the three
/// corruption bugs this file exists because of -- `\sqrt16`, `\sine`, `\intx` --
/// passed a string-equality test written by the same person who wrote the bug,
/// and was found later on a phone, in red.
///
/// So these tests ask KaTeX. Two properties, both of which the converter must
/// hold for inputs nobody has thought of yet:
///
/// 1. every symbol in the table survives a letter following it;
/// 2. **a conversion never breaks a string that already rendered.** That is the
///    governing rule `MathNotation`'s own documentation states -- "a conversion
///    may never damage input that was already correct" -- and until now nothing
///    checked it.
@Suite("The converter, checked against KaTeX")
struct MathNotationRendersTests {

    @Test("the KaTeX the app ships is the KaTeX these tests use")
    func oracleLoadsTheVendoredBundle() throws {
        let katex = try KaTeXOracle()
        #expect(katex.renders(#"\int_{0}^{1} 3x^{2}\,dx"#))
        #expect(katex.failure(#"\notacommand"#) != nil)
    }

    /// A LaTeX control word runs to the first non-letter, so `\int` immediately
    /// followed by `x` is the single command `\intx`, which does not exist.
    ///
    /// This is the bug from the whiteboard photograph: the model wrote
    /// `∫x^n dx`, the substitution made it `\intx^n dx`, and KaTeX painted it
    /// red. It is not specific to the integral -- every entry in the table is a
    /// control word and every one of them has the same fault.
    @Test("every symbol in the table survives being followed by a letter")
    func symbolsTerminateBeforeALetter() throws {
        let katex = try KaTeXOracle()
        var broken: [String] = []
        for (unicode, command) in MathNotation.symbols {
            for suffix in ["x", "r^{2}", "f(x)dx", "n=1"] {
                let converted = MathNotation.toLaTeX(unicode + suffix)
                if let message = katex.failure(converted) {
                    broken.append("\(unicode)\(suffix) -> \(converted)  [\(command)]  \(message.prefix(60))")
                }
            }
        }
        let report = broken.joined(separator: "\n")
        #expect(broken.isEmpty, "\(broken.count) conversions do not render:\n\(report)")
    }

    /// The exact strings from the bug report, kept verbatim.
    @Test("the formulas from the photographed integral render")
    func theWhiteboardIntegral() throws {
        let katex = try KaTeXOracle()
        for raw in ["∫x^n dx = (x^(n+1))/(n+1) + C",
                    "∫a * f(x)dx = a * ∫f(x)dx",
                    "∫(f(x) + g(x))dx = ∫f(x)dx + ∫g(x)dx",
                    "∫c dx = cx + C"] {
            let converted = MathNotation.toLaTeX(raw)
            #expect(katex.renders(converted),
                    "\(raw) -> \(converted): \(katex.failure(converted) ?? "")")
        }
    }

    /// The property that would have caught all three historical bugs at the
    /// commit that introduced them.
    ///
    /// The corpus is the maths the on-device model actually wrote, recorded
    /// before conversion in `docs/eval-records/**/*.graded.jsonl` -- which is why
    /// that field was added. A string the model wrote that KaTeX already accepts
    /// must still be accepted after we have "improved" it.
    @Test("no conversion breaks a string that already rendered")
    func conversionNeverWorsens() throws {
        let katex = try KaTeXOracle()
        let corpus = try RecordedMath.rawStrings()
        #expect(corpus.count > 50, "the corpus should not have quietly emptied")

        var regressions: [String] = []
        for raw in corpus where katex.renders(raw) {
            let converted = MathNotation.toLaTeX(raw)
            if let message = katex.failure(converted) {
                regressions.append("\(raw)\n  -> \(converted)\n  \(message.prefix(80))")
            }
        }
        let report = regressions.joined(separator: "\n")
        #expect(regressions.isEmpty,
                """
                \(regressions.count) of \(corpus.count) recorded strings were made unrenderable:
                \(report)
                """)
    }
}

/// The `rawMath` fields of the published evaluation records.
enum RecordedMath {

    static func rawStrings() throws -> [String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let root = url.appendingPathComponent("docs/eval-records")

        var seen = Set<String>()
        var out: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        for case let file as URL in enumerator ?? .init() where file.lastPathComponent.hasSuffix(".graded.jsonl") {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let raw = object["rawMath"] as? [String]
                else { continue }
                for string in raw where !string.isEmpty && seen.insert(string).inserted {
                    out.append(string)
                }
            }
        }
        return out
    }
}

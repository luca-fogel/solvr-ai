import Foundation

/// Turns plain-text or Unicode mathematics into LaTeX, when a model would not.
///
/// This exists because of a measured failure, not a hypothetical one. Apple's
/// on-device model produces *correct* maths in the *wrong notation*: asked
/// explicitly, through both `@Guide` descriptions and session instructions, for
/// `\int_{0}^{1} 3x^{2}\,dx`, it returns `∫[0,1] 3x^2 dx`. Tightening the guide
/// wording changed the flavour of the wrong answer and not its correctness --
/// which is a useful result in itself: the on-device model's weakness here is
/// presentation, not mathematics, and prompt wording is not a strong enough
/// lever to fix it. A fine-tune is.
///
/// Until then this closes the gap deterministically. Deterministic matters: the
/// alternative is asking a model to reformat a model's output, which adds a
/// second thing that can be wrong.
///
/// The governing rule, inherited from `LLMJSON`: **a conversion may never damage
/// input that was already correct.** Anything that already looks like LaTeX is
/// returned untouched, and every rule below is one that cannot fire on
/// well-formed LaTeX.
public enum MathNotation {

    /// Convert plain-text mathematics to LaTeX, or return it unchanged if it is
    /// already LaTeX or cannot be improved safely.
    public static func toLaTeX(_ raw: String) -> String {
        // Before deciding anything else: a literal `\n` is a newline the model
        // typed, not evidence that it was writing LaTeX. Left in place it would
        // satisfy `needsConversion`'s "there is a backslash command here" test
        // and the whole string would be returned untouched -- including the `\n`
        // that KaTeX then chokes on.
        let cleaned = literalNewlines(raw)
        let evidence = cleaned.replacingOccurrences(of: "\\quad", with: "")
        guard needsConversion(evidence) else { return cleaned }

        var s = radicals(cleaned)
        for (plain, latex) in symbols {
            s = s.replacingOccurrences(of: plain, with: latex)
        }
        s = bracketedLimits(s)
        s = functionCalls(s)
        s = braceExponents(s, marker: "^")
        s = braceExponents(s, marker: "_")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a field meant to hold mathematics actually holds a sentence.
    ///
    /// Observed in the running app: asked for the algebra of a step, the on-device
    /// model returned "Let f(x) = 3x^2. Then, the antiderivative of f(x) is
    /// F(x) = x^3." KaTeX renders that as italic maths, collapsing the spaces into
    /// "Letf(x)...theantiderivativeof" -- and the resulting box is wide enough to
    /// push the whole page sideways and clip the text beside it.
    ///
    /// An empty box is better than a garbled one, so a field that reads as prose is
    /// dropped rather than rendered. The test is deliberately conservative: real
    /// working is mostly symbols, so several ordinary words in a row is the signal.
    /// `\text{...}` is exempt, since that is how LaTeX is *supposed* to carry words.
    public static func looksLikeProse(_ raw: String) -> Bool {
        let stripped = raw.replacingOccurrences(
            of: "\\\\text\\{[^}]*\\}", with: "", options: .regularExpression)
        let words = stripped
            .replacingOccurrences(of: "\\\\[a-zA-Z]+", with: " ",
                                  options: .regularExpression)
            .split(whereSeparator: { !$0.isLetter })
            .filter { $0.count >= 3 }
        // Single-letter variables and short function names survive; a run of real
        // words does not. Four is loose enough to keep "sqrt of the sum" style
        // fragments and tight enough to catch a sentence.
        return words.count >= 4
    }

    /// Whether this looks like text a model wrote instead of LaTeX.
    ///
    /// A single backslash-command is taken as proof the model was writing LaTeX,
    /// and its output is then left completely alone. That is deliberately
    /// generous: half-converting a string that was already right is worse than
    /// leaving a stray `x^2`, which KaTeX renders correctly anyway.
    static func needsConversion(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }
        var index = raw.startIndex
        while let slash = raw[index...].firstIndex(of: "\\") {
            let next = raw.index(after: slash)
            if next < raw.endIndex, raw[next].isLetter { return false }
            guard next < raw.endIndex else { break }
            index = next
        }
        return true
    }

    /// Unicode a model reaches for instead of the command.
    private static let symbols: [(String, String)] = [
        ("∫", "\\int"), ("∑", "\\sum"), ("∏", "\\prod"),
        ("∂", "\\partial"), ("∇", "\\nabla"), ("∞", "\\infty"),
        ("≠", "\\neq"), ("≤", "\\leq"), ("≥", "\\geq"), ("≈", "\\approx"),
        ("±", "\\pm"), ("×", "\\times"), ("÷", "\\div"), ("⋅", "\\cdot"),
        ("→", "\\to"), ("⇒", "\\Rightarrow"), ("∈", "\\in"),
        ("π", "\\pi"), ("θ", "\\theta"), ("α", "\\alpha"), ("β", "\\beta"),
        ("γ", "\\gamma"), ("λ", "\\lambda"), ("μ", "\\mu"), ("σ", "\\sigma"),
        ("φ", "\\phi"), ("ω", "\\omega"), ("Δ", "\\Delta"), ("Σ", "\\Sigma"),
        ("Ω", "\\Omega"),
    ]

    /// A literal `\n` the model wrote as a line separator.
    ///
    /// Measured: twelve of the thirty KaTeX failures in an on-device run were
    /// `2sin(θ) - 1 = 0 \nsin(θ) = 1/2` and its like -- a backslash and an `n`,
    /// meant as a newline, read by KaTeX as an undefined control sequence that
    /// takes the rest of the expression down with it.
    ///
    /// `\quad` rather than `\\`: KaTeX itself warns that `\\` does nothing in
    /// display mode, so it would render as a silent join. A wide space at least
    /// shows two statements are two.
    ///
    /// The commands that legitimately begin `\n` are spelled out rather than
    /// guessed at, because `x \neq y` and `\nabla f` must survive, and both have
    /// a space before the backslash exactly like the broken case does.
    private static func literalNewlines(_ s: String) -> String {
        guard s.contains("\\n") else { return s }
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            guard s[index] == "\\", s.index(after: index) < s.endIndex,
                  s[s.index(after: index)] == "n" else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            var end = s.index(after: index)
            while end < s.endIndex, s[end].isLetter { end = s.index(after: end) }
            let command = String(s[s.index(after: index)..<end])
            if nCommands.contains(command) {
                out += "\\" + command
                index = end
            } else {
                // The `n` was a newline; whatever followed it is content.
                out += " \\quad "
                index = s.index(index, offsetBy: 2)
            }
        }
        return out
    }

    /// Real LaTeX commands starting with `n`, longest first is not needed --
    /// the whole letter run is matched at once.
    private static let nCommands: Set<String> = [
        // `\n` itself is deliberately absent: it is not a LaTeX command, and
        // including it kept `\n2sin(θ) = 1` broken -- the letter run after the
        // backslash is just "n" when a digit follows.
        "ne", "neq", "neg", "nabla", "not", "nu", "ni", "nmid", "nleq",
        "ngeq", "newline", "nonumber", "normalsize", "natural", "nsim",
        "nparallel", "nrightarrow", "nleftarrow", "nsubseteq", "nsupseteq",
    ]

    /// `√16` -> `\sqrt{16}`, `√(x+1)` -> `\sqrt{x+1}`.
    ///
    /// This one is not cosmetic. `√` used to be a plain entry in the symbol
    /// table, mapping to `\sqrt` with no argument -- so `√16` became `\sqrt16`,
    /// which KaTeX reads as `\sqrt{1}` followed by a `6` and renders as √1·6.
    /// A different number, shown to a student with no hint that anything was
    /// substituted. `√x` fared worse: `\sqrtx` is not a command at all.
    ///
    /// The radical therefore takes its argument the way LaTeX needs it: the
    /// parenthesised group if there is one, otherwise the run of alphanumerics,
    /// otherwise nothing at all -- a bare `\sqrt` with the input unchanged after
    /// it, which is no worse than what was there.
    private static func radicals(_ s: String) -> String {
        guard s.contains("√") else { return s }
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            guard s[index] == "√" else {
                out.append(s[index])
                index = s.index(after: index)
                continue
            }
            var argument = s.index(after: index)
            while argument < s.endIndex, s[argument] == " " {
                argument = s.index(after: argument)
            }
            // `√[s(s-a)(s-b)(s-c)]` -- Heron's formula, exactly as the model
            // writes it, nine times in one run. Left alone it becomes
            // `\sqrt[...]`, where KaTeX reads the brackets as the *index* of the
            // radical and then finds no argument at all: "unexpected end of
            // input". Brackets and parentheses both mean "the thing under the
            // root" here.
            if argument < s.endIndex, s[argument] == "(" || s[argument] == "[",
               let close = matchingGroup(s, from: argument) {
                out += "\\sqrt{\(String(s[s.index(after: argument)..<close]))}"
                index = s.index(after: close)
                continue
            }
            var end = argument
            while end < s.endIndex, s[end].isLetter || s[end].isNumber || s[end] == "." {
                end = s.index(after: end)
            }
            if end > argument {
                out += "\\sqrt{\(String(s[argument..<end]))}"
                index = end
            } else {
                out += "\\sqrt"
                index = s.index(after: index)
            }
        }
        return out
    }

    /// `\int[0,1]` -> `\int_{0}^{1}`.
    ///
    /// Runs after the symbol pass, because what the model actually emits is
    /// `∫[0,1]`. Only fires directly after an operator that takes limits, so an
    /// ordinary interval `[0,1]` in prose is left alone.
    private static func bracketedLimits(_ s: String) -> String {
        var out = s
        for op in ["\\int", "\\sum", "\\prod"] {
            while let start = out.range(of: op + "["),
                  let close = out[start.upperBound...].firstIndex(of: "]") {
                let inner = String(out[start.upperBound..<close])
                let parts = inner.split(separator: ",", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2 else { break }
                let replacement = "\(op)_{\(parts[0])}^{\(parts[1])}"
                out.replaceSubrange(start.lowerBound...close, with: replacement)
            }
        }
        return out
    }

    /// `sqrt(x)` -> `\sqrt{x}`, and the same for the trig and log names, which
    /// models write bare.
    private static func functionCalls(_ s: String) -> String {
        var out = s
        for name in ["sqrt", "sin", "cos", "tan", "sec", "csc", "cot",
                     "log", "ln", "exp"] {
            var searchFrom = out.startIndex
            while let range = out.range(of: name, range: searchFrom..<out.endIndex) {
                // Not part of a longer word, and not already a command.
                let beforeOK: Bool
                if range.lowerBound == out.startIndex {
                    beforeOK = true
                } else {
                    let prev = out[out.index(before: range.lowerBound)]
                    beforeOK = !prev.isLetter && prev != "\\"
                }
                // And not the start of a longer word either: checking only the
                // character before turned `sine` into `\sine`, `cost` into
                // `\cost` and `expression` into `\expression` -- undefined
                // control sequences that KaTeX drops or paints red. A digit may
                // follow (`sin2x`), a letter may not.
                let afterOK: Bool
                if range.upperBound == out.endIndex {
                    afterOK = true
                } else {
                    afterOK = !out[range.upperBound].isLetter
                }
                guard beforeOK, afterOK else {
                    searchFrom = range.upperBound
                    continue
                }
                let isSqrt = name == "sqrt"
                if isSqrt, range.upperBound < out.endIndex, out[range.upperBound] == "(",
                   let close = matchingParen(out, from: range.upperBound) {
                    let inner = String(out[out.index(after: range.upperBound)..<close])
                    out.replaceSubrange(range.lowerBound...close, with: "\\sqrt{\(inner)}")
                    searchFrom = out.startIndex
                    continue
                }
                if !isSqrt {
                    out.replaceSubrange(range, with: "\\" + name)
                    searchFrom = out.index(range.lowerBound, offsetBy: name.count + 1)
                    continue
                }
                searchFrom = range.upperBound
            }
        }
        return out
    }

    /// `x^2` -> `x^{2}`, `x^(2+1)` -> `x^{2+1}`. Already-braced exponents are
    /// left alone, which is what keeps this safe to run twice.
    private static func braceExponents(_ s: String, marker: Character) -> String {
        var out = ""
        var index = s.startIndex
        while index < s.endIndex {
            let c = s[index]
            guard c == marker else {
                out.append(c)
                index = s.index(after: index)
                continue
            }
            let next = s.index(after: index)
            guard next < s.endIndex else {
                out.append(c)
                break
            }
            if s[next] == "{" {
                out.append(c)
                index = next
                continue
            }
            if s[next] == "(", let close = matchingParen(s, from: next) {
                out.append(c)
                out.append("{")
                out += String(s[s.index(after: next)..<close])
                out.append("}")
                index = s.index(after: close)
                continue
            }
            // A bare run of alphanumerics, plus a leading minus.
            var end = next
            if s[end] == "-" { end = s.index(after: end) }
            while end < s.endIndex, s[end].isLetter || s[end].isNumber {
                end = s.index(after: end)
            }
            guard end > next else {
                out.append(c)
                index = next
                continue
            }
            out.append(c)
            out.append("{")
            out += String(s[next..<end])
            out.append("}")
            index = end
        }
        return out
    }

    private static func matchingParen(_ s: String, from open: String.Index) -> String.Index? {
        matchingGroup(s, from: open)
    }

    /// The index of the delimiter closing the one at `open`, nesting included.
    private static func matchingGroup(_ s: String, from open: String.Index) -> String.Index? {
        let opening = s[open]
        let closing: Character
        switch opening {
        case "(": closing = ")"
        case "[": closing = "]"
        case "{": closing = "}"
        default: return nil
        }
        var depth = 0
        var i = open
        while i < s.endIndex {
            if s[i] == opening { depth += 1 }
            if s[i] == closing {
                depth -= 1
                if depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }
}

// MARK: - Input, going the other way

extension MathNotation {

    /// Rewrite a problem into notation the on-device model will accept.
    ///
    /// Measured, and the measurement was a surprise. Two of the app's six
    /// example problems failed on **every** run, deterministically, and neither
    /// failure was about the mathematics:
    ///
    /// - `Find the derivative of f(x) = x³ · sin(x)` came back as a *refusal* --
    ///   `GenerationError.guardrailViolation`, surfaced to the student as "the
    ///   model declined this one". Replacing `x³` with `x^3` answers it
    ///   correctly. `x²` in the algebra example was fine, so this is not a rule
    ///   about superscripts the model states anywhere; it is behaviour, and the
    ///   only way to know was to run it.
    /// - The middle dot `·` sent it into a generation long enough to exceed the
    ///   4,096-token window: `contextExceeded`, no answer at all. `*` is fine.
    ///
    /// So the app writes the problem the way the model can read it before
    /// asking. This is not cosmetic and it is not only about the chips: a
    /// student typing `x³` on the iOS keyboard, or a photograph of a textbook
    /// read by Vision, produces exactly these characters.
    ///
    /// Conservative on purpose. It converts the characters that were measured
    /// to break generation and leaves the rest -- `θ`, `π`, `≤` all appear in a
    /// sample problem the model answers correctly, so they stay.
    public static func plainForModel(_ raw: String) -> String {
        var out = ""
        var pendingSuperscript = ""

        func flushSuperscript() {
            guard !pendingSuperscript.isEmpty else { return }
            // Braces only when there is more than one digit: `x^2` is what the
            // model writes itself, and matching its own idiom is the point.
            out += pendingSuperscript.count == 1
                ? "^\(pendingSuperscript)"
                : "^{\(pendingSuperscript)}"
            pendingSuperscript = ""
        }

        for character in raw {
            if let digit = superscriptDigits[character] {
                pendingSuperscript.append(digit)
                continue
            }
            flushSuperscript()
            switch character {
            case "·", "⋅", "×": out.append("*")
            case "÷": out.append("/")
            case "−": out.append("-")   // U+2212, not a hyphen
            default: out.append(character)
            }
        }
        flushSuperscript()
        return out
    }

    private static let superscriptDigits: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
    ]
}

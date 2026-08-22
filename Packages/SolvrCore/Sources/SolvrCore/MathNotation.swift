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
        guard needsConversion(raw) else { return raw }

        var s = raw
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
        ("∫", "\\int"), ("∑", "\\sum"), ("∏", "\\prod"), ("√", "\\sqrt"),
        ("∂", "\\partial"), ("∇", "\\nabla"), ("∞", "\\infty"),
        ("≠", "\\neq"), ("≤", "\\leq"), ("≥", "\\geq"), ("≈", "\\approx"),
        ("±", "\\pm"), ("×", "\\times"), ("÷", "\\div"), ("⋅", "\\cdot"),
        ("→", "\\to"), ("⇒", "\\Rightarrow"), ("∈", "\\in"),
        ("π", "\\pi"), ("θ", "\\theta"), ("α", "\\alpha"), ("β", "\\beta"),
        ("γ", "\\gamma"), ("λ", "\\lambda"), ("μ", "\\mu"), ("σ", "\\sigma"),
        ("φ", "\\phi"), ("ω", "\\omega"), ("Δ", "\\Delta"), ("Σ", "\\Sigma"),
        ("Ω", "\\Omega"),
    ]

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
                guard beforeOK else {
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
        var depth = 0
        var i = open
        while i < s.endIndex {
            if s[i] == "(" { depth += 1 }
            if s[i] == ")" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }
}

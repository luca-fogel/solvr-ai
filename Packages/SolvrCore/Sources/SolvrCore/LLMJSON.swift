import Foundation

/// Turning a language model's answer into a typed value.
///
/// Every prompt in solvr.ai asks for strict JSON, and the model mostly complies.
/// The interesting 5% is what this file is for: fenced output, LaTeX backslashes
/// that JSON rejects, and responses truncated mid-object by a token limit.
///
/// The rule throughout: **a repair may never damage input that was already
/// valid.** An earlier version of this logic doubled every single backslash it
/// found, which fixed `\frac` and simultaneously turned a legitimate `\"` into a
/// literal backslash followed by an unescaped quote -- breaking documents that
/// had arrived perfectly well formed. Correctness on the happy path is worth
/// more than cleverness on the sad one.
public enum LLMJSON {

    // MARK: - Fences

    /// Remove a leading ```json / ``` fence and a trailing ``` fence.
    ///
    /// Models add these even when told not to, and they are the single most
    /// common reason a response fails to parse.
    public static func stripCodeFences(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            } else {
                s = String(s.dropFirst(3))
            }
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - LaTeX escapes

    /// LaTeX commands whose first letter is also a valid JSON escape character.
    ///
    /// `\frac`, `\times` and `\nu` are indistinguishable from a form feed, a tab
    /// and a newline by looking at two characters, so the decision needs the rest
    /// of the word. Prefix matching, so `\textbf` is caught by `text`.
    static let ambiguousLaTeXCommands: Set<String> = [
        // b
        "bar", "begin", "beta", "big", "binom", "bmatrix", "boldsymbol", "bullet",
        // f
        "frac", "forall", "floor", "fbox",
        // n
        "nabla", "ne", "neq", "nleq", "ngeq", "not", "notin", "nu",
        // r
        "rangle", "rceil", "rfloor", "rho", "right", "rvert",
        // t
        "tan", "tau", "text", "tfrac", "theta", "therefore", "times", "to", "top",
        "triangle",
    ]

    private static let jsonEscapeLetters: Set<Character> = ["b", "f", "n", "r", "t"]
    private static let alwaysValidEscapes: Set<Character> = ["\"", "\\", "/"]

    /// Double the backslashes that JSON cannot accept, and leave alone the ones
    /// it can.
    ///
    /// Decisions, in order, for a backslash inside a string:
    /// - `\"`, `\\`, `\/` and `\uXXXX` are valid JSON. Copied untouched -- this
    ///   is the property the old implementation broke.
    /// - `\` followed by a letter that is *not* a JSON escape letter (`\alpha`,
    ///   `\int`, `\sqrt`) can only be LaTeX. Doubled.
    /// - `\` followed by `b`, `f`, `n`, `r` or `t` is ambiguous, and is treated as
    ///   LaTeX only when the word that follows is a known command. So `\frac` is
    ///   doubled and `\nNext step` stays a newline.
    /// - `\` followed by anything else (`\{`, `\(`, `\|`, `\ `, `\2`) is not a
    ///   legal JSON escape, so it is LaTeX. Doubled.
    ///
    /// The known-command list is the honest limitation: a LaTeX command starting
    /// with b/f/n/r/t that is missing from it will be read as an escape. That
    /// fails loudly at decode time rather than silently corrupting text.
    public static func repairLaTeXEscapes(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count + 16)
        var inString = false
        var i = raw.startIndex

        while i < raw.endIndex {
            let c = raw[i]

            if c == "\"" && inString {
                inString = false
                out.append(c)
                i = raw.index(after: i)
                continue
            }
            if c == "\"" && !inString {
                inString = true
                out.append(c)
                i = raw.index(after: i)
                continue
            }
            guard c == "\\", inString else {
                out.append(c)
                i = raw.index(after: i)
                continue
            }

            // A backslash inside a string.
            let next = raw.index(after: i)
            guard next < raw.endIndex else {
                // Trailing backslash: cannot be a valid escape.
                out.append("\\\\")
                i = next
                continue
            }
            let n = raw[next]

            if alwaysValidEscapes.contains(n) {
                out.append(c)
                out.append(n)
                i = raw.index(after: next)
                continue
            }
            if n == "u", isFourHexDigits(raw, after: next) {
                out.append(c)
                out.append(n)
                i = raw.index(after: next)
                continue
            }
            if n.isLetter {
                let word = letterRun(raw, from: next)
                let isLaTeX = !jsonEscapeLetters.contains(n) || isKnownLaTeXCommand(word)
                out.append(isLaTeX ? "\\\\" : "\\")
                out.append(n)
                i = raw.index(after: next)
                continue
            }
            // Not a legal JSON escape at all, so it came from LaTeX.
            out.append("\\\\")
            out.append(n)
            i = raw.index(after: next)
        }
        return out
    }

    private static func isFourHexDigits(_ s: String, after uIndex: String.Index) -> Bool {
        var idx = s.index(after: uIndex)
        var count = 0
        while idx < s.endIndex, count < 4, s[idx].isHexDigit {
            idx = s.index(after: idx)
            count += 1
        }
        return count == 4
    }

    private static func letterRun(_ s: String, from start: String.Index) -> String {
        var idx = start
        var word = ""
        while idx < s.endIndex, s[idx].isLetter {
            word.append(s[idx])
            idx = s.index(after: idx)
        }
        return word
    }

    static func isKnownLaTeXCommand(_ word: String) -> Bool {
        let lower = word.lowercased()
        for cmd in ambiguousLaTeXCommands where lower.hasPrefix(cmd) {
            return true
        }
        return false
    }

    // MARK: - Finding the JSON in the answer

    public enum JSONShape: Sendable {
        case object, array

        var open: Character { self == .object ? "{" : "[" }
        var close: Character { self == .object ? "}" : "]" }
    }

    /// Take the outermost `{...}` or `[...]` out of a response that has prose
    /// wrapped around it ("Sure! Here is the JSON:" ... "Let me know if...").
    ///
    /// Outermost rather than first-balanced on purpose: nested objects are the
    /// norm here, and the first `}` is almost never the end of the document.
    /// Returns the input unchanged when no such span exists, so the caller's
    /// error comes from the decoder rather than from here.
    public static func sliceJSONBody(_ raw: String, shape: JSONShape) -> String {
        guard let start = raw.firstIndex(of: shape.open),
              let end = raw.lastIndex(of: shape.close),
              start < end
        else { return raw }
        return String(raw[start...end])
    }

    // MARK: - The decode ladder

    /// Which rung of the ladder produced a value. Worth carrying: a value that
    /// needed repair is not as trustworthy as one that parsed on the first try,
    /// and the caller may want to say so.
    public enum Provenance: String, Sendable {
        /// Parsed as sent. The model did what it was asked.
        case strict
        /// Parsed after fences were stripped and LaTeX escapes repaired.
        case repaired
        /// Parsed after re-serialising through `JSONSerialization`, which
        /// normalises escaping that `JSONDecoder` refuses.
        case normalised
    }

    public struct Decoded<T> {
        public let value: T
        public let provenance: Provenance

        public init(value: T, provenance: Provenance) {
            self.value = value
            self.provenance = provenance
        }
    }

    /// Try increasingly forgiving readings of a model response.
    /// Returns `nil` when every rung fails, so the caller can fall back to
    /// showing the raw text rather than pretending to have structure.
    ///
    /// **Repair runs before the first decode attempt, not after it.** The
    /// tempting order -- try strict JSON first, repair only on failure -- is
    /// wrong here, and a test caught it: `"\frac{d}{dx}"` is *valid* JSON,
    /// because `\f` is a form feed. Strict parsing therefore succeeds and
    /// quietly yields `"<FF>rac{d}{dx}"`, so the app renders mangled maths and
    /// reports no error at all. A response that parses is not the same as a
    /// response that parsed correctly, and this is a maths app: LaTeX fidelity
    /// wins over the letter of the escape table.
    ///
    /// The cost of that choice, stated plainly: a string that legitimately
    /// contains a tab followed by `imes` will be read as `\times`. Accepted --
    /// in this domain the second reading is right far more often.
    public static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> Decoded<T>? {
        let cleaned = stripCodeFences(raw)
        let repaired = repairLaTeXEscapes(cleaned)
        // Nothing needed changing: the model emitted JSON with no ambiguous
        // escapes in it, which is the only case that deserves to be called strict.
        let provenance: Provenance = repaired == cleaned ? .strict : .repaired

        if let data = repaired.data(using: .utf8),
           let v = try? JSONDecoder().decode(type, from: data) {
            return Decoded(value: v, provenance: provenance)
        }

        // If the repair itself made the document unparseable, the original still
        // deserves a try before giving up.
        if let data = cleaned.data(using: .utf8),
           let v = try? JSONDecoder().decode(type, from: data) {
            return Decoded(value: v, provenance: .strict)
        }

        // JSONSerialization accepts some escaping that JSONDecoder rejects, so a
        // round trip through it normalises the document.
        for candidate in [repaired, cleaned] {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let normalised = try? JSONSerialization.data(withJSONObject: object),
                  let v = try? JSONDecoder().decode(type, from: normalised)
            else { continue }
            return Decoded(value: v, provenance: .normalised)
        }
        return nil
    }

    // MARK: - HTML

    /// Escape text for interpolation into the HTML that renders maths in a web
    /// view. Model output is untrusted text: it arrives with `<`, `&` and quotes
    /// in it routinely, and a lesson that renders as broken markup is the least
    /// of the possible outcomes.
    public static func escapeHTML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}

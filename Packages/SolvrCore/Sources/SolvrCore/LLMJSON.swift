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

    /// Slice without being told the shape.
    ///
    /// The shape-taking overload above is still the right call when you know what
    /// you asked for, but `decode` cannot know, and requiring it to guess is how
    /// slicing ended up outside the instrument in the first place. Whichever
    /// bracket opens first wins.
    public static func sliceJSONBody(_ raw: String) -> String {
        let firstObject = raw.firstIndex(of: "{")
        let firstArray = raw.firstIndex(of: "[")
        let shape: JSONShape
        switch (firstObject, firstArray) {
        case (nil, nil):
            return raw
        case (_?, nil):
            shape = .object
        case (nil, _?):
            shape = .array
        case (let object?, let array?):
            shape = object < array ? .object : .array
        }
        return sliceJSONBody(raw, shape: shape)
    }

    // MARK: - The decode ladder

    /// Which rung of the ladder produced a value. Kept as a summary of
    /// `Compliance`, below, because it reads well in a log line.
    public enum Provenance: String, Sendable {
        /// Parsed exactly as sent. The model did what it was asked.
        case strict
        /// Parsed after something had to be done to it first -- a fence removed,
        /// prose trimmed away, LaTeX escapes repaired.
        case repaired
        /// Parsed only after re-serialising through `JSONSerialization`, which
        /// normalises escaping that `JSONDecoder` refuses.
        case normalised
    }

    /// What actually had to be done to a response before it would decode.
    ///
    /// This exists because `provenance` alone was not measuring what it claimed
    /// to. It was computed by comparing the repaired string against the
    /// *post-fence-strip* one, so a response wrapped in a ```json fence reported
    /// `.strict` -- and slicing prose off the ends happened at the call site,
    /// outside `decode` entirely, so that was invisible too.
    ///
    /// Both blind spots flattered exactly the failures a weaker model is most
    /// likely to produce. A 4B that fences every response would have scored
    /// identically to a frontier model emitting bare JSON, which would have made
    /// the headline number of a backend comparison wrong in the direction that
    /// looks good. Each step now reports itself.
    public struct Compliance: Sendable, Equatable {
        /// The response was wrapped in a markdown code fence.
        public var wasFenced = false
        /// Prose around the JSON had to be trimmed away.
        public var wasSliced = false
        /// LaTeX backslashes had to be escaped before JSON would accept them.
        public var escapesRepaired = false
        /// `JSONDecoder` refused it and it only parsed after a round trip
        /// through `JSONSerialization`.
        public var wasNormalised = false
        /// No JSON was recovered at all and the caller wrapped the prose to fill
        /// the shape. Set by the caller, since the wrapping happens above here.
        public var usedPlainTextFallback = false

        public init() {}

        /// The model emitted JSON that needed nothing done to it. This is the
        /// number worth reporting per surface, and the one to compare across
        /// backends.
        public var isClean: Bool {
            !wasFenced && !wasSliced && !escapesRepaired
                && !wasNormalised && !usedPlainTextFallback
        }

        public var provenance: Provenance {
            if wasNormalised { return .normalised }
            return isClean ? .strict : .repaired
        }
    }

    public struct Decoded<T> {
        public let value: T
        public let compliance: Compliance

        /// Summary of `compliance`.
        public var provenance: Provenance { compliance.provenance }

        public init(value: T, compliance: Compliance) {
            self.value = value
            self.compliance = compliance
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
    ///
    /// Fence stripping and prose slicing both happen *here* rather than at the
    /// call sites, so that everything done to a response is done where it can be
    /// counted.
    public static func decode<T: Decodable>(_ type: T.Type, from raw: String) -> Decoded<T>? {
        var compliance = Compliance()

        // Anywhere, not just at the front. A model that writes "Here you go:"
        // before the fence still fenced its output -- the leading-fence check
        // this replaces called that case unfenced, and then the slice quietly
        // removed the fence along with the prose, so the specific thing the
        // model did wrong went unrecorded. The false-positive risk is a response
        // legitimately containing a triple backtick, which in maths output is
        // not a thing that happens.
        compliance.wasFenced = raw.contains("```")
        let cleaned = stripCodeFences(raw)

        let sliced = sliceJSONBody(cleaned)
        compliance.wasSliced = sliced != cleaned

        let repaired = repairLaTeXEscapes(sliced)
        compliance.escapesRepaired = repaired != sliced

        if let data = repaired.data(using: .utf8),
           let v = try? JSONDecoder().decode(type, from: data) {
            return Decoded(value: v, compliance: compliance)
        }

        // If the repair itself made the document unparseable, the original still
        // deserves a try before giving up.
        if let data = sliced.data(using: .utf8),
           let v = try? JSONDecoder().decode(type, from: data) {
            var withoutRepair = compliance
            withoutRepair.escapesRepaired = false
            return Decoded(value: v, compliance: withoutRepair)
        }

        // JSONSerialization accepts some escaping that JSONDecoder rejects, so a
        // round trip through it normalises the document.
        for candidate in [repaired, sliced] {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let normalised = try? JSONSerialization.data(withJSONObject: object),
                  let v = try? JSONDecoder().decode(type, from: normalised)
            else { continue }
            compliance.wasNormalised = true
            return Decoded(value: v, compliance: compliance)
        }
        return nil
    }

    // MARK: - Arrays that arrived wearing a hat

    /// Pull the array out of a single-property object.
    ///
    /// Asked for a list, a model returns one of three shapes: the bare array it
    /// was shown in the prompt, the wrapper it was given in the schema
    /// (`{"items": [...]}`), or a wrapper it named itself after the thing it was
    /// asked for (`{"steps": [...]}`, `{"formulas": [...]}`). The third is the one
    /// that used to fail, because nothing was looking for it -- and it is not a
    /// malformed response, it is a reasonable reading of an ambiguous request.
    ///
    /// Observed rather than imagined: Kimi K3, given a JSON-Schema wrapper with
    /// `strict: true` *and* a prompt showing a bare array, sometimes honoured one
    /// and sometimes the other.
    ///
    /// Returns `nil` unless the document really is an object with exactly one
    /// property holding an array -- guessing between two candidate arrays would
    /// be worse than failing.
    public static func unwrapSingleArrayProperty(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.count == 1,
              let array = object.values.first as? [Any],
              let reserialised = try? JSONSerialization.data(withJSONObject: array),
              let string = String(data: reserialised, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Decode a list, accepting all three shapes a model might use for one.
    ///
    /// `wasSliced` is recorded when unwrapping was needed, because it is the same
    /// class of thing as trimming prose: the response was not the shape asked
    /// for, and a compliance figure that hid that would be flattering itself.
    public static func decodeList<Element: Decodable>(
        _ element: Element.Type, from raw: String
    ) -> Decoded<[Element]>? {
        if let direct = decode([Element].self, from: raw) {
            return direct
        }
        let cleaned = sliceJSONBody(stripCodeFences(raw), shape: .object)
        guard let inner = unwrapSingleArrayProperty(cleaned),
              let unwrapped = decode([Element].self, from: inner)
        else { return nil }
        // The inner decode only ever saw the extracted array, so anything wrong
        // with the document *around* it -- a fence, prose -- is invisible from
        // there and has to be carried across explicitly. Losing a signal because
        // of where it was measured is exactly the bug this record replaced.
        var compliance = unwrapped.compliance
        compliance.wasSliced = true
        compliance.wasFenced = compliance.wasFenced || raw.contains("```")
        return Decoded(value: unwrapped.value, compliance: compliance)
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

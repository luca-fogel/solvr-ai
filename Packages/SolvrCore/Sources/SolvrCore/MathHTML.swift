import Foundation

/// Putting model-written maths into an HTML page without breaking either one.
///
/// This lives beside `LLMJSON.escapeHTML` rather than in the app for the reason
/// that one does: it is string handling with sharp edges and it belongs where
/// `swift test` can reach it. The app's `HTMLBuilder` calls through.
///
/// The problem it solves is narrow and easy to get wrong. Prose is HTML-escaped
/// and maths is not, because escaping a backslash would destroy the LaTeX --
/// but "not escaped at all" is also wrong, and was what shipped: a `<` in a
/// maths field is read by the HTML parser as the start of a tag.
public enum MathHTML {

    /// Prepare a LaTeX string for interpolation into an HTML page.
    ///
    /// Escapes the three characters that mean something to an HTML parser and
    /// leaves everything else -- backslashes, braces, carets -- untouched. This
    /// is safe for KaTeX because the parser turns the entities back into
    /// characters before `renderMathInElement` reads `textContent`, so what the
    /// renderer sees is the original maths.
    ///
    /// Two things went wrong without it. `a < b` made the parser treat `< b …`
    /// as a tag and swallow the rest of the line, which is common enough in an
    /// app that shows inequalities. And a `<script>` reaching a maths field --
    /// from a photographed page, via OCR -- *ran*, in an app whose entire claim
    /// is that nothing it handles leaves the device.
    public static func escapeLaTeX(_ latex: String) -> String {
        var result = stripDollarDelimiters(latex)
        // Ampersand first, or the escapes escape each other.
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }

    /// The page wraps maths in `\[ \]` itself, so a delimiter the model added
    /// would nest and break the block.
    ///
    /// Separate from the HTML escaping because the evaluation harness needs
    /// this half and not the other: it renders recorded strings through KaTeX
    /// directly, and measuring a string the app never passes to KaTeX measures
    /// nothing. Nine "failures" in an on-device run were `$`-delimited text that
    /// the app strips before rendering.
    public static func stripDollarDelimiters(_ latex: String) -> String {
        latex.replacingOccurrences(of: "$$", with: "")
             .replacingOccurrences(of: "$", with: "")
    }

    /// The element a block of display maths goes into.
    ///
    /// The page used to be handed `\[ … \]` and left to find it with KaTeX's
    /// auto-render, which meant the LaTeX was *text in the document*: if it did
    /// not parse, auto-render rendered it in red and there was nothing left to
    /// fall back to. The maths now travels in an attribute and the element is
    /// empty, so the page can try to typeset it, fail, and put the source back
    /// as plain text -- an honest "this did not typeset" instead of red.
    ///
    /// The attribute is why this exists in the package rather than in
    /// `HTMLBuilder`: a `"` inside an attribute value ends it, and every maths
    /// string here is model output. `escapeLaTeX` was written for element
    /// content and does not escape quotes, which is correct there and would be a
    /// hole here.
    public static func mathElement(_ latex: String, cssClass: String) -> String {
        let tex = stripDollarDelimiters(latex)
        return "<div class=\"\(cssClass)\" data-tex=\"\(escapeAttribute(tex))\"></div>"
    }

    /// Escape a string for use inside a double-quoted HTML attribute.
    ///
    /// Everything `escapeLaTeX` does, plus the two quote characters. The page
    /// reads the value back with `getAttribute`, which returns the unescaped
    /// text, so KaTeX still sees the original maths.
    public static func escapeAttribute(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    /// Convert `$…$` inline delimiters in already-escaped prose to `\(…\)`.
    ///
    /// An odd number of dollars means the text is not delimited maths -- a price,
    /// a typo, a model that opened and never closed. The old version converted
    /// them positionally anyway, emitting a `\(` with no `\)`, and KaTeX's
    /// auto-render then treats the entire rest of the page as one maths
    /// expression: everything after it vanishes. Leaving the text alone is the
    /// honest outcome.
    public static func processInlineMath(_ htmlText: String) -> String {
        let dollars = htmlText.filter { $0 == "$" }.count
        guard dollars > 0, dollars.isMultiple(of: 2) else { return htmlText }

        var result = ""
        var inMath = false
        for character in htmlText {
            if character == "$" {
                result += inMath ? "\\)" : "\\("
                inMath.toggle()
            } else {
                result.append(character)
            }
        }
        return result
    }
}

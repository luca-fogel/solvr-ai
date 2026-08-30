import Foundation
import SolvrCore

enum HTMLBuilder {

    // MARK: - Steps HTML

    static func buildStepsHTML(steps: [StepItem]) -> String {
        var body = ""
        for (i, step) in steps.enumerated() {
            let isLast = i == steps.count - 1
            // "Final answer" is what the provider says it is, not what position
            // a step happens to occupy. The old version relabelled the last step
            // unconditionally -- throwing away the model's own heading, and
            // announcing a conclusion even when generation had been cut off
            // mid-working, which is exactly when the claim is worst.
            let isAnswer = step.isFinalAnswer
            let accentColor = isAnswer ? "var(--success)" : "var(--accent)"
            let badge = isAnswer ? "<span class=\"final-badge\">Final answer</span>" : ""

            body += """
            <div class="step-row">
                <div class="timeline">
                    <div class="circle" style="background:\(accentColor)">\(step.step)</div>
                    \(isLast ? "" : "<div class=\"line\"></div>")
                </div>
                <div class="step-content">
                    <div class="step-title">\(escapeHTML(step.title))\(badge)</div>
                    <div class="step-explanation">\(processInlineMath(escapeHTML(step.explanation)))</div>
            """

            if let math = step.math, !math.isEmpty {
                body += """
                    <div class="math-block">\\[\(escapeLaTeX(math))\\]</div>
                """
            }

            body += """
                </div>
            </div>
            """
        }

        let css = """
        .step-row { display:flex; gap:12px; }
        .timeline { display:flex; flex-direction:column; align-items:center; width:28px; flex-shrink:0; }
        .circle { width:28px; height:28px; border-radius:50%; color:#fff;
                  font-size:13px; font-weight:700; display:flex; align-items:center;
                  justify-content:center; }
        .line { width:1px; flex:1; background:var(--separator); min-height:16px; }
        .step-content { flex:1; padding-bottom:20px; }
        .step-title { font-weight:600; font-size:16px; color:var(--text-primary); margin-bottom:4px; }
        .final-badge { display:inline-block; margin-left:8px; padding:2px 8px; border-radius:99px;
                       background:var(--success); color:#fff; font-size:11px; font-weight:700;
                       letter-spacing:0.03em; vertical-align:middle; }
        .step-explanation { font-size:15px; color:var(--text-secondary); line-height:1.5; margin-bottom:8px; }
        .math-block { background:var(--tertiary-bg); border-radius:12px; padding:14px 16px;
                      overflow:hidden !important; margin-top:4px; max-width:100%; }
        .math-block .katex-display { margin:0; }
        """

        return wrapHTML(body: body, extraCSS: css)
    }

    // MARK: - Lesson HTML

    static func buildLessonHTML(lesson: LessonContent) -> String {
        var body = """
        <div class="lesson-title">\(escapeHTML(lesson.title))</div>
        <div class="lesson-topic">\(escapeHTML(lesson.topic.uppercased()))</div>
        <div class="divider"></div>
        <div class="lesson-intro">\(processInlineMath(escapeHTML(lesson.introduction)))</div>
        """

        for section in lesson.sections {
            body += """
            <div class="section">
                <div class="section-heading">\(escapeHTML(section.heading))</div>
                <div class="section-content">\(processInlineMath(escapeHTML(section.content)))</div>
            """

            if let formula = section.formula, !formula.isEmpty {
                body += """
                <div class="formula-box">\\[\(escapeLaTeX(formula))\\]</div>
                """
            }

            if let note = section.note, !note.isEmpty {
                body += """
                <div class="section-note">\(processInlineMath(escapeHTML(note)))</div>
                """
            }

            if let steps = section.steps, !steps.isEmpty {
                body += "<ol class=\"section-steps\">"
                for step in steps {
                    body += "<li>\(processInlineMath(escapeHTML(step)))</li>"
                }
                body += "</ol>"
            }

            body += "</div>"
        }

        if let takeaway = lesson.keyTakeaway, !takeaway.isEmpty {
            body += """
            <div class="takeaway">
                <div class="takeaway-bar"></div>
                <div class="takeaway-text">\(processInlineMath(escapeHTML(takeaway)))</div>
            </div>
            """
        }

        let css = """
        .lesson-title { font-size:22px; font-weight:700; color:var(--accent);
                        text-align:center; margin-bottom:4px; }
        .lesson-topic { font-size:12px; font-weight:600; color:var(--text-tertiary);
                        text-align:center; letter-spacing:0.5px; margin-bottom:12px; }
        .divider { height:1px; max-width:200px; margin:0 auto 16px;
                   background:color-mix(in srgb, var(--accent) 30%, transparent); }
        .lesson-intro { font-size:15px; color:var(--text-secondary); line-height:1.6; margin-bottom:20px; }
        .section { margin-bottom:20px; }
        .section-heading { font-size:18px; font-weight:600; color:var(--text-primary); margin-bottom:8px; }
        .section-content { font-size:15px; color:var(--text-primary); line-height:1.6; margin-bottom:8px; }
        .formula-box { background:var(--tertiary-bg); border-radius:12px; padding:14px 16px;
                       overflow:hidden !important; margin:8px 0; text-align:center; max-width:100%; }
        .formula-box .katex-display { margin:0; }
        .section-note { font-size:14px; color:var(--text-tertiary); font-style:italic; margin:8px 0; }
        .section-steps { padding-left:20px; margin:8px 0; }
        .section-steps li { font-size:15px; color:var(--text-primary); line-height:1.6;
                            margin-bottom:6px; padding-left:4px; }
        .section-steps li::marker { color:var(--accent); font-weight:600; }
        .takeaway { display:flex; gap:0; border-radius:8px; overflow:hidden;
                    background:var(--secondary-bg); margin-top:20px; }
        .takeaway-bar { width:3px; background:var(--accent); flex-shrink:0; }
        .takeaway-text { font-size:14px; color:var(--text-primary); line-height:1.5;
                         padding:12px 16px; }
        """

        return wrapHTML(body: body, extraCSS: css)
    }

    // MARK: - Formulas HTML

    static func buildFormulasHTML(formulas: [FormulaItem]) -> String {
        var body = ""
        for formula in formulas {
            body += """
            <div class="formula-card">
                <div class="formula-header">
                    <span class="formula-name">\(escapeHTML(formula.name.uppercased()))</span>
                </div>
                <div class="formula-math">\\[\(escapeLaTeX(formula.formula))\\]</div>
                <div class="formula-desc">\(processInlineMath(escapeHTML(formula.description)))</div>
            </div>
            """
        }

        let css = """
        .formula-card { background:var(--secondary-bg); border-radius:12px; padding:16px;
                        margin-bottom:12px; border:1px solid var(--separator); }
        .formula-header { display:flex; justify-content:space-between; align-items:center; margin-bottom:8px; }
        .formula-name { font-size:12px; font-weight:600; color:var(--accent); letter-spacing:0.5px; }
        .formula-math { text-align:center; padding:8px 0; overflow:hidden !important; max-width:100%; }
        .formula-math .katex-display { margin:0; }
        .formula-desc { font-size:14px; color:var(--text-secondary); line-height:1.5; }
        """

        return wrapHTML(body: body, extraCSS: css)
    }

    // MARK: - HTML Wrapper with KaTeX

    private static func wrapHTML(body: String, extraCSS: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, shrink-to-fit=yes">
        \(KaTeXAssets.styleTag)
        \(KaTeXAssets.scriptTag)
        <script>
            // Inlined rather than linked, so this runs with no network at all --
            // which an app that can answer on device has to be able to do.
            // `throwOnError: false` stays: one malformed formula should degrade to
            // red text, not blank the page. It does mean invalid LaTeX fails
            // silently here, which is why the evaluation harness renders the same
            // strings with `throwOnError: true` and counts what breaks.
            document.addEventListener("DOMContentLoaded", function () {
                renderMathInElement(document.body, {
                    delimiters: [
                        {left: '$$', right: '$$', display: true},
                        {left: '\\\\[', right: '\\\\]', display: true},
                        {left: '$', right: '$', display: false},
                        {left: '\\\\(', right: '\\\\)', display: false}
                    ],
                    throwOnError: false
                });
                scaleMath();
            });
        </script>
        <style>
            :root {
                --accent: #5856D6;
                --text-primary: #000;
                --text-secondary: #3C3C43;
                --text-tertiary: #8E8E93;
                --secondary-bg: #F2F2F7;
                --tertiary-bg: #E5E5EA;
                --separator: #C6C6C8;
                --success: #34C759;
            }
            @media (prefers-color-scheme: dark) {
                :root {
                    --text-primary: #FFF;
                    --text-secondary: #EBEBF5;
                    --text-tertiary: #8E8E93;
                    --secondary-bg: #1C1C1E;
                    --tertiary-bg: #2C2C2E;
                    --separator: #38383A;
                    --success: #30D158;
                }
            }
            * { margin:0; padding:0; box-sizing:border-box; -webkit-text-size-adjust:none; max-width:100vw; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
                color: var(--text-primary);
                padding: 16px 20px 40px;
                -webkit-user-select: text;
                overflow-x: hidden !important;
                width: 100%;
                max-width: 100%;
                background: transparent;
            }
            .katex { font-size: 1.05em; white-space:normal !important; }
            .katex-display {
                margin: 12px 0;
                overflow-x: hidden !important;
                overflow-y: hidden;
                padding: 0;
            }
            .katex-display > .katex { max-width:100%; overflow:hidden; }
            .katex-display > .katex > .katex-html { max-width:100%; overflow:hidden; }
            \(extraCSS)
        </style>
        </head>
        <body>\(body)
        <script>
        function scaleMath() {
            // Scale down display math equations wider than their container
            document.querySelectorAll('.katex-display').forEach(function(container) {
                var katex = container.querySelector('.katex');
                if (!katex) return;
                var containerWidth = container.parentElement.clientWidth;
                var mathWidth = katex.scrollWidth;
                if (mathWidth > containerWidth && containerWidth > 0) {
                    var scale = (containerWidth - 8) / mathWidth;
                    if (scale < 1) {
                        katex.style.display = 'block';
                        katex.style.transform = 'scale(' + scale + ')';
                        katex.style.transformOrigin = 'left center';
                        var h = katex.offsetHeight;
                        container.style.height = (h * scale + 8) + 'px';
                        container.style.overflow = 'hidden';
                    }
                }
            });
            // Scale equations inside math-box / formula-box containers
            document.querySelectorAll('.math-block, .formula-box, .formula-math').forEach(function(box) {
                box.querySelectorAll('.katex').forEach(function(katex) {
                    var boxWidth = box.clientWidth - 32;
                    var mathWidth = katex.scrollWidth;
                    if (mathWidth > boxWidth && boxWidth > 0) {
                        var scale = boxWidth / mathWidth;
                        if (scale < 1) {
                            katex.style.display = 'inline-block';
                            katex.style.transform = 'scale(' + scale + ')';
                            katex.style.transformOrigin = 'left center';
                        }
                    }
                });
            });
        }
        // Run again after a short delay in case KaTeX renders asynchronously
        setTimeout(scaleMath, 300);
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    /// Model output is untrusted text and lands inside a web view, so it is
    /// escaped by `SolvrCore.LLMJSON.escapeHTML` -- one implementation, covered
    /// by tests, rather than a second copy here that quietly forgets quotes.
    private static func escapeHTML(_ text: String) -> String {
        LLMJSON.escapeHTML(text)
    }

    /// Preserves LaTeX backslashes while neutralising the three characters an
    /// HTML parser would act on. Implemented in `SolvrCore.MathHTML` so it is
    /// covered by `swift test`; see there for what went wrong without it.
    private static func escapeLaTeX(_ latex: String) -> String {
        MathHTML.escapeLaTeX(latex)
    }

    /// Converts `$...$` inline delimiters in HTML-escaped text to `\(...\)` for
    /// KaTeX auto-render. In `SolvrCore.MathHTML`, and tested there.
    private static func processInlineMath(_ htmlText: String) -> String {
        MathHTML.processInlineMath(htmlText)
    }
}

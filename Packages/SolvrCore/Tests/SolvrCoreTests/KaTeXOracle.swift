import Foundation
import JavaScriptCore

/// KaTeX itself, as a test oracle.
///
/// The notation converter has now produced three separate corruption bugs --
/// `\sqrt16`, `\sine`, `\intx` -- and every one of them was found by a person
/// looking at red text on a phone. Reviewing the converter harder is not a plan;
/// the thing that can actually decide whether a string is valid LaTeX is the
/// renderer, so the renderer is what the tests ask.
///
/// Three properties make this cheap enough to run in the two-second suite:
///
/// - **`katex.renderToString` needs no DOM.** It builds an HTML string, so it
///   runs in a bare `JSContext` with no document, no window and no WebKit.
/// - **It is the *shipped* KaTeX.** The bundle is loaded from
///   `solvr.ai/Resources/KaTeX/katex.min.js` -- the file the app inlines into its
///   web view -- rather than from a separately installed npm copy, which could
///   drift from it without anything noticing.
/// - **`throwOnError: true`.** The app renders with `throwOnError: false`,
///   because a malformed formula should not blank the page, which is exactly why
///   these failures are silent in production and have to be made loud here.
///
/// Measured on this machine: 8 ms to evaluate the bundle, well under a
/// millisecond per string after that.
final class KaTeXOracle {

    private let context: JSContext
    private let check: JSValue

    /// The vendored bundle, found relative to this source file.
    ///
    /// `#filePath` rather than `Bundle.module`: the JavaScript belongs to the app
    /// target, and copying 276 KB into the package to test it would mean testing
    /// a second copy that can go stale -- the failure this is meant to prevent.
    static var bundleURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // .../SolvrCoreTests -> repo root
        return url.appendingPathComponent("solvr.ai/Resources/KaTeX/katex.min.js")
    }

    init() throws {
        let source = try String(contentsOf: Self.bundleURL, encoding: .utf8)
        guard let context = JSContext() else {
            throw Failure.engineUnavailable
        }
        self.context = context
        context.exceptionHandler = { _, value in
            FileHandle.standardError.write(
                Data("KaTeXOracle JS exception: \(value?.toString() ?? "?")\n".utf8))
        }
        context.evaluateScript(source)
        // A function rather than an expression per call: building the string
        // once keeps the per-check cost to the parse itself.
        context.evaluateScript("""
            function __solvrCheck(tex) {
                try {
                    katex.renderToString(tex, { throwOnError: true, displayMode: true });
                    return "";
                } catch (e) {
                    return String(e.message);
                }
            }
            """)
        guard let check = context.objectForKeyedSubscript("__solvrCheck"),
              !check.isUndefined,
              context.objectForKeyedSubscript("katex")?.isUndefined == false
        else {
            throw Failure.bundleDidNotLoad(Self.bundleURL.path)
        }
        self.check = check
    }

    /// `nil` when the string renders, otherwise KaTeX's own message.
    func failure(_ tex: String) -> String? {
        let message = check.call(withArguments: [tex])?.toString() ?? "no result"
        return message.isEmpty ? nil : message
    }

    func renders(_ tex: String) -> Bool { failure(tex) == nil }

    enum Failure: Error, CustomStringConvertible {
        case engineUnavailable
        case bundleDidNotLoad(String)

        var description: String {
            switch self {
            case .engineUnavailable:
                return "JavaScriptCore would not give us a context"
            case .bundleDidNotLoad(let path):
                return "no katex global after evaluating \(path)"
            }
        }
    }
}

import Foundation

/// KaTeX, vendored into the app instead of fetched from a CDN.
///
/// This was a real hole in the story. Solvr's whole point is becoming able to
/// answer without a hosted API, and it could do that while still being unable to
/// *render* the answer without a network: `HTMLBuilder` linked
/// `cdn.jsdelivr.net`. An on-device solve on a plane would have produced correct
/// LaTeX and shown it as raw backslashes.
///
/// The assets are inlined into the page as a `<style>` and a `<script>` rather
/// than linked as files, with the fonts as `data:` URIs inside the CSS. That is
/// deliberate: `loadHTMLString` is called with a nil `baseURL`, so there is no
/// document origin for a relative `href` to resolve against, and giving the web
/// view file-system read access purely to load its own stylesheet is a worse
/// trade than a larger string. Assembled once and cached -- the base64 pass over
/// 20 font files is not something to repeat per tab.
enum KaTeXAssets {

    /// A `<style>` element containing KaTeX's CSS with every font embedded.
    static let styleTag: String = {
        guard var css = string(named: "katex.min", ext: "css") else { return "" }

        // KaTeX's CSS asks for `fonts/KaTeX_Main-Regular.woff2`. Each one becomes
        // the font itself, so nothing is fetched at render time.
        for name in fontNames {
            guard let data = data(named: name, ext: "woff2") else { continue }
            let uri = "data:font/woff2;base64,\(data.base64EncodedString())"
            css = css.replacingOccurrences(of: "fonts/\(name).woff2", with: uri)
        }
        return "<style>\(css)</style>"
    }()

    /// A `<script>` element containing KaTeX and its auto-render extension.
    static let scriptTag: String = {
        let katex = string(named: "katex.min", ext: "js") ?? ""
        let autoRender = string(named: "auto-render.min", ext: "js") ?? ""
        return "<script>\(katex)\n\(autoRender)</script>"
    }()

    /// Whether the vendored copy is actually in the bundle.
    ///
    /// Checked rather than assumed because the app target uses a synchronized
    /// file group: resources are picked up by being on disk, which is convenient
    /// until something is not copied and the failure is a page of raw
    /// backslashes rather than a build error.
    static var isBundled: Bool {
        !styleTag.isEmpty && !scriptTag.isEmpty
    }

    private static let fontNames = [
        "KaTeX_AMS-Regular",
        "KaTeX_Caligraphic-Bold", "KaTeX_Caligraphic-Regular",
        "KaTeX_Fraktur-Bold", "KaTeX_Fraktur-Regular",
        "KaTeX_Main-Bold", "KaTeX_Main-BoldItalic",
        "KaTeX_Main-Italic", "KaTeX_Main-Regular",
        "KaTeX_Math-BoldItalic", "KaTeX_Math-Italic",
        "KaTeX_SansSerif-Bold", "KaTeX_SansSerif-Italic", "KaTeX_SansSerif-Regular",
        "KaTeX_Script-Regular",
        "KaTeX_Size1-Regular", "KaTeX_Size2-Regular",
        "KaTeX_Size3-Regular", "KaTeX_Size4-Regular",
        "KaTeX_Typewriter-Regular",
    ]

    private static func data(named name: String, ext: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "fonts")
        else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func string(named name: String, ext: String) -> String? {
        data(named: name, ext: ext).flatMap { String(data: $0, encoding: .utf8) }
    }
}

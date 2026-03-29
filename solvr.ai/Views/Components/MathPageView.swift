import SwiftUI
import WebKit

/// A single full-page WKWebView that renders an entire tab's content
/// (text + math) as one scrollable page using KaTeX.
struct MathPageView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)

            // Force content width to viewport after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.scrollView.contentSize.width = webView.frame.width
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await MainActor.run { UIApplication.shared.open(url) }
                return .cancel
            }
            return .allow
        }
    }
}

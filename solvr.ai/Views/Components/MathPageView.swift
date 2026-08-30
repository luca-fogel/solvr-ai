import SwiftUI
import WebKit

/// What a page reported about typesetting itself.
///
/// The app renders with `throwOnError: true` and degrades a string that will not
/// parse to plain text, so a failure is no longer visible as red maths -- which
/// is the point, and which means the only way to know it happened is for the
/// page to say so. This is that channel, and it is what the device self test
/// asserts is empty.
struct MathRenderReport: Sendable, Equatable {
    let total: Int
    let failures: [Failure]

    struct Failure: Sendable, Equatable {
        let tex: String
        let message: String
    }
}

/// A single full-page WKWebView that renders an entire tab's content
/// (text + math) as one scrollable page using KaTeX.
struct MathPageView: UIViewRepresentable {
    let html: String
    /// Called once per page load with what KaTeX made of it.
    var onRender: (@MainActor (MathRenderReport) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = []
        config.userContentController.add(context.coordinator, name: "solvrRender")

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
        context.coordinator.onRender = onRender
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)

            // Force content width to viewport after load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.scrollView.contentSize.width = webView.frame.width
            }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // A handler outlives the view otherwise, and adding the same name twice
        // is a hard crash rather than a warning.
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "solvrRender")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var onRender: (@MainActor (MathRenderReport) -> Void)?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }

        nonisolated func userContentController(_ controller: WKUserContentController,
                                               didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            let total = body["total"] as? Int ?? 0
            let failures = (body["failures"] as? [[String: Any]] ?? []).map {
                MathRenderReport.Failure(tex: $0["tex"] as? String ?? "",
                                         message: $0["message"] as? String ?? "")
            }
            let report = MathRenderReport(total: total, failures: failures)
            Task { @MainActor [weak self] in self?.onRender?(report) }
        }
    }
}

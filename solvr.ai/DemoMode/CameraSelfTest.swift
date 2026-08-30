import Foundation
import UIKit
import WebKit
import SolvrCore

/// Drives the camera path end to end on the device, from photographs with known
/// contents, and writes down what happened.
///
/// **This is the instrument whose absence let the bug ship.** The typed path had
/// `solvr-eval` on the Mac and `-SolvrSelfTest` on the phone, and both were used;
/// the camera path had neither, so a photograph of an integral could produce a
/// lesson about flatbed scanners and every number in the repository stayed green.
///
/// What it measures that the Mac harness cannot:
///
/// - **Vision on the phone**, which is not Vision on a Mac. This repository has
///   already been caught once believing a Mac about a phone: the same model
///   under the same greedy decoding solved a trig problem correctly on macOS and
///   wrongly on an iPhone 15 Pro.
/// - **The real renderer.** Each surface's page is built by the real
///   `HTMLBuilder` and loaded into a real `WKWebView` with the vendored KaTeX, and
///   the page reports how many strings it could not typeset. A Node check can
///   tell you a string parses; only this can tell you the page drew it.
/// - **The identity property.** All four surfaces of one solve are asked, and the
///   transcript records the question each of them got. Anything other than one
///   question per solve is a failed run.
///
/// Fixtures are not in the binary. They are pushed into the app's container, so
/// a Release build measures the Release code with no test data compiled into it:
///
///     xcrun devicectl device copy to --device <udid> \
///       --domain-type appDataContainer --domain-identifier Lulu.solvr-ai \
///       --source docs/fixtures/camera --destination Documents/fixtures
///     xcrun devicectl device process launch --console --device <udid> \
///       Lulu.solvr-ai -- -SolvrCameraSelfTest YES
///     xcrun devicectl device copy from --device <udid> \
///       --domain-type appDataContainer --domain-identifier Lulu.solvr-ai \
///       --source Documents/camera-selftest.log --destination .
@MainActor
enum CameraSelfTest {

    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "SolvrCameraSelfTest")
    }

    private static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static var reportURL: URL? {
        documents?.appendingPathComponent("camera-selftest.log")
    }

    private struct Fixture: Decodable {
        let id: String
        let file: String
        let topic: String
        let expectedText: String
        let answer: String
        let expectUnreadable: Bool?
        let notes: String?
    }

    private struct Manifest: Decodable {
        let fixtures: [Fixture]
    }

    static func run() async {
        var transcript: [String] = []
        func log(_ line: String) {
            print("[camera] \(line)")
            transcript.append(line)
            if let url = reportURL {
                try? transcript.joined(separator: "\n").appending("\n")
                    .write(to: url, atomically: true, encoding: .utf8)
            }
        }

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        log("start — build \(build), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")

        guard let documents else {
            log("no documents directory")
            return
        }
        let dir = documents.appendingPathComponent("fixtures")
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            log("no fixtures at \(dir.path) — push them with `devicectl device copy to`")
            log("end")
            return
        }

        let provider = ProviderFactory.onDevice
        if let unavailable = provider.availability {
            log("availability: UNAVAILABLE — \(unavailable.errorDescription ?? "unknown")")
            log("end")
            return
        }
        log("availability: available")
        provider.prewarm()
        log("fixtures: \(manifest.fixtures.count)")

        var renderFailures = 0
        var renderChecked = 0

        for fixture in manifest.fixtures {
            log("")
            log("\(fixture.id)  (\(fixture.file))")
            guard let jpeg = try? Data(contentsOf: dir.appendingPathComponent(fixture.file)) else {
                log("  MISSING image")
                continue
            }

            let clock = Date()
            let solve: Solve
            do {
                solve = try await ProviderFactory.builder.photograph(jpeg)
            } catch {
                let expected = fixture.expectUnreadable ?? false
                log(String(format: "  read: REFUSED in %.2fs — %@",
                           Date().timeIntervalSince(clock),
                           (error as? SolverError)?.errorDescription ?? "\(error)"))
                log("  \(expected ? "as expected: this fixture has nothing legible in it" : "UNEXPECTED: this fixture should have been readable")")
                log("  expected text: \(fixture.expectedText)")
                continue
            }

            if fixture.expectUnreadable ?? false {
                log("  UNEXPECTED: this fixture should have been refused")
            }
            log(String(format: "  read in %.2fs", Date().timeIntervalSince(clock)))
            log("  question: \(solve.question)")
            log("  expected: \(fixture.expectedText)")
            log("  exact:    \(solve.question == fixture.expectedText ? "yes" : "no")")

            // The whole app path, not a reimplementation of it: the same
            // coordinator the results screen drives, with the same provider.
            let coordinator = SolveCoordinator(provider: { ProviderFactory.current() })
            coordinator.begin(solve)
            for surface in Surface.allCases {
                let started = Date()
                coordinator.ensureLoaded(surface)
                await coordinator.settle()
                let state = coordinator.state(for: surface)
                let outcome = state.error.map { "FAILED — \($0.errorDescription ?? "")" }
                    ?? (state.hasValue ? "ok" : "empty")
                log(String(format: "  %-8@ %@ in %.1fs", surface.rawValue, outcome,
                           Date().timeIntervalSince(started)))
            }

            if let steps = coordinator.steps,
               let answer = steps.last(where: { $0.isFinalAnswer }) ?? steps.last {
                log("  answer:   \(answer.math ?? answer.explanation)")
                log("  correct:  \(fixture.answer)")
            }

            // Every surface of this solve was asked one question, or the run
            // has found the bug it was built for.
            log("  asked \(Surface.allCases.count) surfaces about one question: "
                + "\(coordinator.solve?.question == solve.question ? "yes" : "NO")")

            // And the pages the student would actually see, drawn by the real
            // renderer with `throwOnError: true`.
            for (name, html) in pages(from: coordinator) {
                let report = await render(html)
                renderChecked += report.total
                renderFailures += report.failures.count
                log("  render \(name): \(report.total - report.failures.count)/\(report.total) typeset")
                for failure in report.failures {
                    log("    could not typeset: \(failure.tex)")
                    log("      \(failure.message)")
                }
            }
        }

        log("")
        log("KaTeX: \(renderChecked - renderFailures)/\(renderChecked) display strings typeset "
            + "under throwOnError: true, on this device, in the app's own web view")
        log("end")
    }

    private static func pages(from coordinator: SolveCoordinator) -> [(String, String)] {
        var out: [(String, String)] = []
        if let steps = coordinator.steps {
            out.append(("steps", HTMLBuilder.buildStepsHTML(steps: steps)))
        }
        if let lesson = coordinator.lesson {
            out.append(("lesson", HTMLBuilder.buildLessonHTML(lesson: lesson)))
        }
        if let formulas = coordinator.formulas {
            out.append(("formulas", HTMLBuilder.buildFormulasHTML(formulas: formulas)))
        }
        return out
    }

    /// Load one page into a real web view and wait for it to say what it made of
    /// the maths in it.
    private static func render(_ html: String) async -> MathRenderReport {
        await withCheckedContinuation { continuation in
            let box = RenderBox(continuation: continuation)
            box.load(html)
        }
    }
}

/// Holds a web view alive until its page reports back, and gives up if it never
/// does -- a self test that can hang is a self test nobody runs twice.
@MainActor
private final class RenderBox: NSObject, WKScriptMessageHandler {
    private var continuation: CheckedContinuation<MathRenderReport, Never>?
    private var webView: WKWebView?
    private static var live: Set<RenderBox> = []

    init(continuation: CheckedContinuation<MathRenderReport, Never>) {
        self.continuation = continuation
        super.init()
        Self.live.insert(self)
    }

    func load(_ html: String) {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "solvrRender")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800),
                                configuration: config)
        self.webView = webView
        webView.loadHTMLString(html, baseURL: nil)

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.finish(MathRenderReport(total: 0, failures: [
                .init(tex: "(timed out)", message: "the page never reported")
            ]))
        }
    }

    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        let total = body["total"] as? Int ?? 0
        let failures = (body["failures"] as? [[String: Any]] ?? []).map {
            MathRenderReport.Failure(tex: $0["tex"] as? String ?? "",
                                     message: $0["message"] as? String ?? "")
        }
        Task { @MainActor [weak self] in
            self?.finish(MathRenderReport(total: total, failures: failures))
        }
    }

    private func finish(_ report: MathRenderReport) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: "solvrRender")
        webView = nil
        Self.live.remove(self)
        continuation.resume(returning: report)
    }
}

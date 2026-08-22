import Foundation
import SolvrCore

/// Proves the on-device backend works on real hardware, from the command line.
///
/// The on-device model cannot be verified anywhere convenient. It is absent from
/// the simulator, and absent from this Mac (no downloaded generative asset), so
/// the only honest check is a real device -- and a real device cannot be checked
/// by reading code. Hence a launch-argument self test, the same trick demo mode
/// uses:
///
///     xcrun devicectl device process launch --console \
///       --device <udid> Lulu.solvr-ai -SolvrSelfTest YES
///
/// It prints `SystemLanguageModel.availability`, then solves one problem and
/// reports what came back and how long it took. That is also the mechanism the
/// evaluation harness will need for the on-device arm, which cannot run under
/// `swift run` on a Mac with no model.
enum OnDeviceSelfTest {

    static let defaultsKey = "SolvrSelfTest"

    /// `UserDefaults` reads `-SolvrSelfTest YES` straight out of the launch
    /// arguments, so no argument parsing is needed anywhere.
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Where the report is written, in addition to stdout.
    ///
    /// A file rather than only a print: attaching a console to a launching app is
    /// unreliable on the simulator and awkward on a device, but the container is
    /// readable either way -- `xcrun simctl get_app_container` or
    /// `devicectl device copy from`. A self test you cannot read the output of is
    /// not a self test.
    static var reportURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("selftest.log")
    }

    static func run() async {
        var transcript: [String] = []
        let log = { (line: String) in
            print("[selftest] \(line)")
            transcript.append(line)
            if let url = reportURL {
                try? transcript.joined(separator: "\n").appending("\n")
                    .write(to: url, atomically: true, encoding: .utf8)
            }
        }
        log("start — build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")

        let provider = ProviderFactory.onDevice
        if let unavailable = provider.availability {
            log("availability: UNAVAILABLE — \(unavailable.errorDescription ?? "unknown")")
            log("end")
            return
        }
        log("availability: available")

        let problem = ProblemInput.text("Evaluate the definite integral of 3x^2 from 0 to 1")

        let warm = Date()
        provider.prewarm()
        log(String(format: "prewarm returned in %.2fs", Date().timeIntervalSince(warm)))

        do {
            let clock = Date()
            let steps = try await provider.steps(for: problem)
            let elapsed = Date().timeIntervalSince(clock)
            log(String(format: "steps: %d in %.2fs", steps.count, elapsed))
            for step in steps {
                log("  \(step.step). \(step.title) — \(step.math ?? "(no working)")")
            }
            // The point of the exercise: a typed value arrived, so no rung of the
            // repair ladder was reachable. Worth asserting out loud rather than
            // assuming, because it is the project's central claim.
            log("repair ladder: not reachable on this path (typed value, no string parsed)")
        } catch {
            log("steps: FAILED — \(error)")
        }

        do {
            let clock = Date()
            let lesson = try await provider.lesson(for: problem)
            log(String(format: "lesson: '%@' [%@] with %d sections in %.2fs",
                       lesson.title, lesson.topic, lesson.sections.count,
                       Date().timeIntervalSince(clock)))
        } catch {
            log("lesson: FAILED — \(error)")
        }

        do {
            let clock = Date()
            let formulas = try await provider.formulas(for: problem)
            log(String(format: "formulas: %d in %.2fs",
                       formulas.count, Date().timeIntervalSince(clock)))
            for formula in formulas {
                log("  \(formula.name): \(formula.formula)")
            }
        } catch {
            log("formulas: FAILED — \(error)")
        }

        log("end")
    }
}

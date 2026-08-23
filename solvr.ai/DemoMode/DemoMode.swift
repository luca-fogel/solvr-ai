import Foundation
import SolvrCore

/// Runs the app against canned responses instead of the on-device model.
///
/// Why it exists: without an API key, solvr.ai can show you a text field and
/// nothing else, which makes it impossible to evaluate, impossible to screenshot
/// honestly, and impossible to demonstrate to anyone who does not want to hand
/// over a key first. Demo mode makes the whole results surface reachable with no
/// key, no network and no cost.
///
/// Enable it either way:
/// - launch argument: `-SolvrDemo YES` (what the screenshot script uses)
/// - Settings → Demo mode (what a human uses)
///
/// It is deliberately not the default. An app that quietly shows fabricated
/// answers is worse than one that says it needs a key.
enum DemoMode {

    static let defaultsKey = "SolvrDemo"

    static var isEnabled: Bool {
        // UserDefaults reads `-SolvrDemo YES` from the launch arguments for free,
        // so one key covers both entry points.
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
    }

    /// Which screen to open straight to, for scripted screenshots:
    /// `-SolvrDemo YES -SolvrScreen lesson`.
    ///
    /// This exists because the alternative was synthesising taps at measured
    /// pixel coordinates, which is unreproducible by anyone else and breaks the
    /// moment a layout changes. A launch argument makes every screenshot in the
    /// README regenerable with one command.
    enum Screen: String {
        case home, steps, lesson, formulas, videos, chat, history, settings

        /// Matches `ResultTab`'s raw values; -1 for screens that are not a tab.
        var tabIndex: Int {
            switch self {
            case .steps: return 0
            case .lesson: return 1
            case .formulas: return 2
            case .videos: return 3
            case .chat: return 4
            case .home, .history, .settings: return -1
            }
        }
    }

    static var screen: Screen? {
        guard isEnabled,
              let raw = UserDefaults.standard.string(forKey: "SolvrScreen")
        else { return nil }
        return Screen(rawValue: raw)
    }

    /// Latency worth simulating: with an instant response the loading states are
    /// unreachable, and a shimmer nobody can see is a shimmer nobody maintains.
    /// Short enough not to be annoying.
    static let simulatedLatency: Duration = .milliseconds(700)

    static func pause() async {
        try? await Task.sleep(for: simulatedLatency)
    }

}

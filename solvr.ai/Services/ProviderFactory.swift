import Foundation
import SolvrCore
import UIKit

/// Decides which backend answers, and gives it eyes if it needs them.
enum ProviderFactory {

    /// Which backend the user has chosen. Stored separately from
    /// `selectedModel`, which is a model name *within* a backend.
    static let backendKey = "selectedBackend"

    enum Backend: String, CaseIterable {
        case anthropic

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic API"
            }
        }
    }

    static var selectedBackend: Backend {
        let stored = UserDefaults.standard.string(forKey: backendKey) ?? ""
        return Backend(rawValue: stored) ?? .anthropic
    }

    /// Resolve the provider for one request.
    ///
    /// Two orderings here are deliberate and were both true of the code this
    /// replaces:
    ///
    /// - **Demo mode is checked before anything else**, including whether a key
    ///   exists. That is why demo mode works with no credential at all; a factory
    ///   that resolved the backend first would reintroduce a key requirement.
    /// - **This is called per request, not cached.** The Settings toggle is an
    ///   `@AppStorage` binding on the same key, so flipping it takes effect on
    ///   the next fetch. A provider resolved once at launch would make the toggle
    ///   appear to do nothing until relaunch.
    static func current() -> any SolutionProvider {
        if DemoMode.isEnabled {
            return FixtureSolutionProvider(latency: DemoMode.simulatedLatency)
        }
        return sighted(backend(for: selectedBackend))
    }

    private static func backend(for backend: Backend) -> any SolutionProvider {
        switch backend {
        case .anthropic: return anthropic()
        }
    }

    /// The provider lives in `SolvrCore` so the evaluation harness can drive the
    /// same code the app does. Everything platform-specific it used to reach for
    /// directly is handed to it here.
    static func anthropic(usesStructuredOutputs: Bool = false,
                          observe: AnthropicProvider.Observer? = nil) -> AnthropicProvider {
        AnthropicProvider(
            configuration: .init(model: selectedModel,
                                 maxTokens: maxTokens,
                                 usesStructuredOutputs: usesStructuredOutputs),
            apiKey: { KeychainManager.retrieve() },
            isOnline: { NetworkMonitor.shared.isConnected },
            observe: observe)
    }

    /// Normalises whatever is in `UserDefaults` onto a model ID that exists.
    ///
    /// The old mapping sent Haiku to `claude-haiku-4-5-20251001`; current IDs
    /// carry no date suffix, so that string is not a model. The `default` branch
    /// passes unrecognised values straight through -- a previous version rewrote
    /// them to Sonnet, which would silently discard a local model name stored
    /// under the same key.
    private static var selectedModel: String {
        let stored = UserDefaults.standard.string(forKey: "selectedModel") ?? ""
        switch stored {
        case "", "claude-sonnet-4-20250514":
            return "claude-opus-5"
        case "claude-haiku-4-20250414", "claude-haiku-4-5-20251001":
            return "claude-haiku-4-5"
        default:
            return stored
        }
    }

    private static var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxTokens")
        return stored > 0 ? stored : 2048
    }

    /// Wrap any backend that cannot look at a photograph so that it can.
    ///
    /// The wrapping is decided by the provider's own `acceptsImageInput` rather
    /// than by a list kept here, so a backend added later cannot forget to
    /// declare it and silently lose the camera. `OCRService` is injected rather
    /// than imported by `SightedProvider` because that keeps the bridge in
    /// `SolvrCore`, under test, without dragging Vision in with it.
    private static func sighted(_ provider: any SolutionProvider) -> any SolutionProvider {
        guard !provider.acceptsImageInput else { return provider }
        return SightedProvider(wrapping: provider) { data in
            guard let image = UIImage(data: data) else {
                throw SolverError.invalidResponse
            }
            return try await OCRService.recognizeText(from: image)
        }
    }
}

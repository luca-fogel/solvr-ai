import Foundation
import SolvrCore
import UIKit

/// Decides which backend answers, and gives it eyes if it needs them.
enum ProviderFactory {

    /// Which backend the user has chosen. Stored separately from
    /// `selectedModel`, which is a model name *within* a backend.
    static let backendKey = "selectedBackend"

    enum Backend: String, CaseIterable, Identifiable {
        /// The hosted API. The quality ceiling, and the only backend that reads a
        /// photograph natively.
        case anthropic
        /// Apple's on-device model. No key, no network, nothing leaves the phone.
        case appleOnDevice

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic API"
            case .appleOnDevice: return "On this device"
            }
        }

        var detail: String {
            switch self {
            case .anthropic:
                return "Best answers, and the only one that can read a photo directly. "
                     + "Needs a key, and the problem is sent to Anthropic."
            case .appleOnDevice:
                return "Apple Intelligence, running on your iPhone. No key, no network, "
                     + "nothing leaves the device. Photos are read by on-device text "
                     + "recognition first, which is weaker on handwriting."
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
    /// - **This is called per request, not cached.** The Settings picker is an
    ///   `@AppStorage` binding on the same key, so changing it takes effect on the
    ///   next fetch. A provider resolved once at launch would make the picker
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
        case .appleOnDevice: return onDevice
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

    /// Cached, unlike the others, so `prewarm()` has somewhere to live. Loading
    /// the on-device model is the expensive part of the first solve, and a
    /// provider rebuilt per request could never warm it. The *selection* is still
    /// resolved per request, so the Settings picker stays live.
    static let onDevice = OnDeviceProvider()

    /// Why the on-device backend cannot be used right now, or `nil` if it can.
    /// Surfaced in Settings, because "Apple Intelligence is off" is the user's to
    /// fix and they can only fix it if told.
    static var onDeviceUnavailableReason: String? {
        onDevice.availability?.errorDescription
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
}

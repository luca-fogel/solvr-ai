import Foundation
import SolvrCore
import UIKit

/// Decides which provider answers, and gives it eyes.
///
/// This used to choose between three backends -- a hosted API, a model served on
/// your own machine, and Apple's on-device model. The first two are gone: they
/// were the only reason the app ever held a credential or opened a socket, and
/// removing them is what lets the app claim that nothing leaves the device.
/// What is left is a switch with one real arm, kept as a factory only because
/// demo mode still has to win over everything else.
enum ProviderFactory {

    /// Resolve the provider for one request.
    ///
    /// Two properties are deliberate and were both true of the code this replaces:
    ///
    /// - **Demo mode is checked before anything else.** That is why demo mode
    ///   works on a device with no Apple Intelligence at all; resolving the
    ///   backend first would reintroduce a requirement demo exists to avoid.
    /// - **This is called per request, not cached.** The demo toggle in Settings
    ///   is an `@AppStorage` binding, so flipping it takes effect on the next
    ///   fetch rather than at the next launch.
    static func current() -> any SolutionProvider {
        #if DEBUG
        // Release has no demo arm at all -- not a flag that defaults to off, no
        // branch. A shipped app that can be put into a state where it answers
        // from canned samples, with nothing on screen saying so, is an app whose
        // answers cannot be trusted to be its own.
        if DemoMode.isEnabled {
            return FixtureSolutionProvider(latency: DemoMode.simulatedLatency)
        }
        #endif
        return sighted(onDevice)
    }

    /// Cached, so `prewarm()` has somewhere to live. Loading the on-device model
    /// is the expensive part of the first solve, and a provider rebuilt per
    /// request could never warm it.
    static let onDevice = OnDeviceProvider()

    /// Why the on-device model cannot answer right now, or `nil` if it can.
    ///
    /// This matters more than it used to, not less. It was one explanation among
    /// three backends; it is now the only thing standing between the user and a
    /// blank screen, and every outcome it reports ("Apple Intelligence is turned
    /// off", "this iPhone is too old") is the user's to fix and can only be fixed
    /// if they are told.
    static var onDeviceUnavailableReason: String? {
        onDevice.availability?.errorDescription
    }

    /// Wrap any provider that cannot look at a photograph so that it can.
    ///
    /// The wrapping is decided by the provider's own `acceptsImageInput` rather
    /// than by a list kept here, so a backend added later cannot forget to
    /// declare it and silently lose the camera. That is still worth keeping with
    /// one backend: `FoundationModels` takes no image input at all, so this is
    /// the only reason the scanner works. `OCRService` is injected rather than
    /// imported by `SightedProvider` because that keeps the bridge in
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

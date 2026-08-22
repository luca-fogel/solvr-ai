import SwiftUI

enum Platform {
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    static var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}

extension Platform {

    /// Bounds of the screen this app is actually being shown on.
    ///
    /// `UIScreen.main` was deprecated in iOS 26, but the deprecation is the
    /// smaller reason to stop using it: under Mac Catalyst, or on an iPad with
    /// two windows of the same app, "the main screen" is not necessarily the one
    /// the view is in, so a crop rectangle computed from it lands in the wrong
    /// place. Falls back to `.zero`, which reads as "unknown" downstream rather
    /// than as a plausible wrong size.
    static var activeScreenBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.screen.bounds ?? .zero
    }
}

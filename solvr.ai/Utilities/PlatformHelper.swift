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

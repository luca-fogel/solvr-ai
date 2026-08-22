//  solvr.ai -- step-by-step maths solutions and lesson plans from a photo.
//  Copyright (C) 2026 Luca Fogel Robion
//
//  This program is free software: you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public
//  License for more details: <https://www.gnu.org/licenses/>.

import SwiftUI
import SwiftData

@main
struct solvr_aiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if targetEnvironment(macCatalyst)
                .onAppear {
                    configureMacWindow()
                }
                #endif
        }
        .modelContainer(for: Problem.self)
    }

    #if targetEnvironment(macCatalyst)
    private func configureMacWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 1400)
        windowScene.title = "solvr."

        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
    }
    #endif
}

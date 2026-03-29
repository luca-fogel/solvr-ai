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

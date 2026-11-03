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
    init() {
        // SwiftData creates its store file but not the folder the file lives in.
        // On a fresh install that folder does not exist yet, so the first launch
        // logged screens of CoreData errors ("Sandbox access to file-write-create
        // denied") before recovering on its own. Creating it first keeps the
        // console clean.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory,
                                                 withIntermediateDirectories: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    LegacyCredentialPurge.runIfNeeded()
                }
                #if targetEnvironment(macCatalyst)
                .onAppear {
                    configureMacWindow()
                }
                #endif
        }
        #if targetEnvironment(macCatalyst)
        .modelContainer(Self.macContainer)
        #else
        .modelContainer(for: Problem.self)
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// The Mac build is not sandboxed, so `.modelContainer(for:)` would put its
    /// store at ~/Library/Application Support/default.store -- the same file
    /// every other unsandboxed SwiftData app on the Mac uses by default. Seen on
    /// this Mac: Solvr found another app's store there and SwiftData migrated it
    /// in place, dropping that app's table for Solvr's. A folder of its own stops
    /// either app wiping the other's history. The iPhone build is sandboxed, so
    /// its default store is already its own and is left where it is.
    private static let macContainer: ModelContainer = {
        let folder = URL.applicationSupportDirectory
            .appending(path: "Lulu.solvr-ai", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let onDisk = ModelConfiguration(url: folder.appending(path: "solvr.store"))
        if let container = try? ModelContainer(for: Problem.self, configurations: onDisk) {
            return container
        }
        // History is a convenience and solving is the app: an empty sidebar is
        // better than a launch that never finishes. An in-memory store has no
        // file to fail on.
        return try! ModelContainer(for: Problem.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }()
    #endif

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

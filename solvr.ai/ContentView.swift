//  solvr.ai -- step-by-step maths solutions and lesson plans from a photo.
import SolvrCore
//  Copyright (C) 2026 Luca Fogel Robion
//
//  This program is free software: you can redistribute it and/or modify it under
//  the terms of the GNU General Public License as published by the Free Software
//  Foundation, either version 3 of the License, or (at your option) any later
//  version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public
//  License for more details: <https://www.gnu.org/licenses/>.

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var showSplash = !Platform.isMac
    @State private var path = NavigationPath()
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var currentProblem = ""
    @State private var isFromHistory = false
    @State private var currentHistoryProblem: Problem?

    @State private var homeVM = HomeViewModel()
    @State private var resultsVM = ResultsViewModel()
    @State private var chatVM = ChatViewModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                HomeView(
                    viewModel: homeVM,
                    onSolve: { problem in
                        solve(problem)
                    },
                    onSolveFromImage: { image in
                        solveFromImage(image)
                    },
                    onLoadFromHistory: { problem in
                        loadFromHistory(problem)
                    },
                    onHistory: {
                        showHistory = true
                    },
                    onSettings: {
                        showSettings = true
                    }
                )
                .navigationBarHidden(true)
                .navigationDestination(for: String.self) { _ in
                    ResultsView(
                        problemText: currentProblem,
                        viewModel: resultsVM,
                        chatViewModel: chatVM,
                        onBack: {
                            let titleToSave = resultsVM.problemTitle.isEmpty ? currentProblem : resultsVM.problemTitle
                            if !titleToSave.isEmpty && titleToSave != "[Scanned Image]" && !isFromHistory {
                                let problem = resultsVM.saveProblem(titleToSave, context: modelContext)
                                chatVM.saveMessages(to: problem)
                            } else if let historyProblem = currentHistoryProblem {
                                chatVM.saveMessages(to: historyProblem)
                            }
                            isFromHistory = false
                            currentHistoryProblem = nil
                            path.removeLast()
                        }
                    )
                    .navigationBarHidden(true)
                }
                .sheet(isPresented: $showHistory) {
                    HistoryView { problem in
                        homeVM.problemText = problem.text
                        loadFromHistory(problem)
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
            }

            // Splash overlay
            if showSplash {
                SplashScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            }
        }
        .task {
                await openDemoScreenIfRequested()
                // Loading the on-device model is the expensive part of the first
                // solve. Warming it while the user is still typing hides that.
                // No backend check any more: on-device is the only one there is,
                // and `prewarm()` already returns early if the model cannot run.
                if !DemoMode.isEnabled {
                    ProviderFactory.onDevice.prewarm()
                }
                if OnDeviceSelfTest.isRequested {
                    await OnDeviceSelfTest.run()
                }
                // `-SolvrSolve "<problem>"` runs a real solve at launch, through
                // whichever backend is selected. Demo mode drives the screens from
                // fixtures, which proves the UI; this proves the whole path --
                // prompt, model, decode, render -- without anyone typing.
                if let problem = UserDefaults.standard.string(forKey: "SolvrSolve"),
                   !problem.isEmpty {
                    showSplash = false
                    homeVM.problemText = problem
                    solve(problem)
                }
            }
    }

    /// Jump straight to one screen, populated with demo data, when launched with
    /// `-SolvrDemo YES -SolvrScreen <name>`. Used by tools/screenshots.sh.
    ///
    /// Debug builds only. The fixtures it draws on are not compiled into a
    /// Release binary at all, so in a shipped app this does nothing and there is
    /// no path from a launch argument to a canned answer.
    private func openDemoScreenIfRequested() async {
        #if DEBUG
        guard let screen = DemoMode.screen else { return }
        showSplash = false

        switch screen {
        case .home:
            return
        case .settings:
            showSettings = true
        case .history:
            // History needs something in it to be worth a screenshot.
            DemoSeed.seedHistory(into: modelContext)
            showHistory = true
        case .steps, .lesson, .formulas, .videos, .chat:
            homeVM.problemText = DemoFixtures.problem
            solve(DemoFixtures.problem)
            // Let the fixtures land before switching tab, so the shot shows
            // content rather than a shimmer.
            try? await Task.sleep(for: .milliseconds(1400))
            resultsVM.selectedTab = ResultTab(rawValue: screen.tabIndex) ?? .steps
            if screen == .chat {
                chatVM.seedDemoConversation()
            }
        }
        #endif
    }

    private func loadFromHistory(_ problem: Problem) {
        isFromHistory = true
        currentProblem = problem.text
        currentHistoryProblem = problem
        chatVM.clear()
        chatVM.setProblemContext(problem.text)
        chatVM.loadMessages(from: problem)
        resultsVM.loadFromHistory(problem)
        path.append("results")
    }

    private func solve(_ problem: String) {
        currentProblem = problem
        isFromHistory = false
        chatVM.clear()
        chatVM.setProblemContext(problem)
        resultsVM.solveAll(problem: problem)
        path.append("results")
    }

    private func solveFromImage(_ image: UIImage) {
        currentProblem = "Scanning..."
        isFromHistory = false
        chatVM.clear()
        chatVM.setProblemContext("[Scanned Image]")
        resultsVM.solveFromImage(image)
        path.append("results")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Problem.self, inMemory: true)
}

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
    /// The solve on screen, or `nil` on the home screen.
    ///
    /// This replaces a `String` that held, at various moments, "Scanning...",
    /// "[Scanned Image]", a model-written title, and occasionally the problem.
    /// Every one of those was passed to the results screen as `problemText`, and
    /// three of the four found their way into a prompt. A `Solve` cannot: it is
    /// built once, by `SolveBuilder`, from something a person actually gave us.
    @State private var currentSolve: Solve?
    @State private var isFromHistory = false
    @State private var currentHistoryProblem: Problem?
    @State private var isReadingPhoto = false

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
                        viewModel: resultsVM,
                        chatViewModel: chatVM,
                        onBack: {
                            if !isFromHistory,
                               let problem = resultsVM.saveProblem(context: modelContext) {
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
                // `-SolvrCameraSelfTest YES` drives the camera path end to end
                // from fixtures pushed into the container: photograph, Vision,
                // prompt, four surfaces, and the real KaTeX render of each page.
                // Nothing about it is compiled into the binary except the code
                // it exercises.
                if CameraSelfTest.isRequested {
                    await CameraSelfTest.run()
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
        currentHistoryProblem = problem
        chatVM.clear()
        // The chat is told the question, not the label. It used to be told
        // whatever the results header was showing -- so a photographed problem
        // gave the tutor "The student is working on: Scanning...", on the first
        // solve, with no history involved.
        chatVM.setProblemContext(problem.question)
        chatVM.loadMessages(from: problem)
        resultsVM.loadFromHistory(problem)
        currentSolve = resultsVM.solve
        path.append("results")
    }

    private func solve(_ problem: String) {
        guard let solve = try? ProviderFactory.builder.typed(problem) else {
            homeVM.errorMessage = SolverError.nothingToSolve.errorDescription
            return
        }
        begin(solve)
    }

    /// Read the photograph *before* leaving the camera.
    ///
    /// It used to navigate first and recognise later, inside the provider, once
    /// per surface -- so a photograph with nothing legible in it produced four
    /// identical errors on a results screen the student had already been pushed
    /// to. Reading it here means "no text in that photo" is one sentence, on the
    /// screen where the fix is to take another picture.
    private func solveFromImage(_ image: UIImage) {
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            homeVM.errorMessage = SolverError.invalidResponse.errorDescription
            return
        }
        isReadingPhoto = true
        Task {
            defer { isReadingPhoto = false }
            do {
                begin(try await ProviderFactory.builder.photograph(jpeg))
            } catch {
                homeVM.errorMessage = (error as? SolverError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func begin(_ solve: Solve) {
        currentSolve = solve
        isFromHistory = false
        chatVM.clear()
        chatVM.setProblemContext(solve.question)
        resultsVM.begin(solve)
        path.append("results")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Problem.self, inMemory: true)
}

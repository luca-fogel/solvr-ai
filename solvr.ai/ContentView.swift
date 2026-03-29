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

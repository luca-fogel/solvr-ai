import SwiftUI
import SolvrCore

struct ResultsView: View {
    @Bindable var viewModel: ResultsViewModel
    @Bindable var chatViewModel: ChatViewModel
    let onBack: () -> Void

    private var contentTabs: [ResultTab] {
        var tabs = TabOrderManager.shared.orderedTabs.filter { $0 != .chat }
        tabs.append(.chat)
        return tabs
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            if Platform.isMac {
                macResultsLayout
            } else {
                iphoneResultsLayout
            }
        }
        .onAppear {
            // The question, not whatever is written above the tabs. This line
            // used to hand the tutor "Scanning..." on every photographed solve.
            chatViewModel.setProblemContext(viewModel.solve?.question)
        }
    }

    // MARK: - iPhone Layout

    private var iphoneResultsLayout: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 4)

            problemHeader
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)

            DemoBanner()

            TabSelector(
                selectedTab: $viewModel.selectedTab,
                tabs: contentTabs.filter { $0 != .chat }
            )
            .padding(.bottom, Theme.Spacing.xs)

            Group {
                contentForTab(viewModel.selectedTab)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.animation(Theme.Animation.smooth))
            // No `.id(selectedTab)`: it tore down and rebuilt `MathPageView`'s
            // web view on every switch, re-parsing the page and re-running
            // KaTeX -- a visible flash for no gain.
            .task(id: viewModel.selectedTab) {
                viewModel.ensureLoaded(viewModel.selectedTab)
            }
        }
    }

    // MARK: - Mac Layout (horizontal split)

    private var macResultsLayout: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 4)

            HStack(spacing: 0) {
                // LEFT: Problem image/text + chat
                VStack(spacing: 0) {
                    problemHeader
                        .padding(Theme.Spacing.lg)

                    ChatView(viewModel: chatViewModel)
                }
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 420)
                .background(Theme.Colors.secondaryBackground.opacity(0.3))

                Divider()

                // RIGHT: Tabs + content
                VStack(spacing: 0) {
                    DemoBanner()

                    TabSelector(
                        selectedTab: $viewModel.selectedTab,
                        tabs: contentTabs.filter { $0 != .chat }
                    )
                    .padding(.bottom, Theme.Spacing.xs)

                    Group {
                        contentForTab(viewModel.selectedTab == .chat ? .steps : viewModel.selectedTab)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.animation(Theme.Animation.smooth))
                    .task(id: viewModel.selectedTab) {
                        viewModel.ensureLoaded(viewModel.selectedTab)
                    }
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
            }

            Spacer()

            Text("solvr.")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Colors.accent)

            Spacer()

            Button { shareSolution() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - What is being solved

    /// The photograph, and under it the text that was actually read from it.
    ///
    /// The recognised line is the point of this view. Apple's on-device model
    /// takes no image input, so a photographed problem is only ever as good as
    /// what Vision made of it -- and until now the app never showed that, so a
    /// misread `∫` looked identical to a model that could not integrate. What is
    /// on screen here is the same string, byte for byte, that every tab was
    /// asked about.
    @ViewBuilder
    private var problemHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
            }

            if let question = viewModel.solve?.question {
                if viewModel.sourceImage != nil {
                    Text("READ FROM THE PHOTO")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .accessibilityLabel("Text read from the photo, and asked about")
                }
                Text(question)
                    .font(Theme.Fonts.math(14))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(Theme.Spacing.base)
        .cardStyle()
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func contentForTab(_ tab: ResultTab) -> some View {
        switch tab {
        case .steps:
            StepByStepView(state: viewModel.stepsState,
                           onRetry: { viewModel.retrySteps() })
        case .lesson:
            LessonView(state: viewModel.lessonState,
                       onRetry: { viewModel.retryLesson() })
        case .formulas:
            FormulasView(state: viewModel.formulasState,
                         onRetry: { viewModel.retryFormulas() })
        case .videos:
            VideosView(state: viewModel.videosState,
                       onRetry: { viewModel.retryVideos() })
        case .chat:
            ChatView(viewModel: chatViewModel)
        }
    }

    // MARK: - Share

    private var shareableText: String {
        var parts: [String] = ["Problem: \(viewModel.solve?.question ?? "(not recorded)")"]
        if viewModel.lesson != nil { parts.append("Lesson available") }
        parts.append("\nSolved with solvr.ai")
        return parts.joined(separator: "\n")
    }

    private func shareSolution() {
        let items: [Any] = [shareableText]
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: 60, width: 0, height: 0)
            }
            topVC.present(activityVC, animated: true)
        }
    }
}


/// Says, unmissably, that the answers on screen are canned.
///
/// Demo mode returns the same fixture for every input, so with it on the app
/// shows an answer to a question nobody asked -- which is exactly what a broken
/// model looks like from the outside. It used to be invisible: a persisted
/// toggle in Settings and no other sign. It draws nothing in Release, where
/// demo mode does not exist.
struct DemoBanner: View {
    var body: some View {
        if DemoMode.isEnabled {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("DEMO DATA — canned samples, not an answer to this problem")
                    .font(Theme.Fonts.caption)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, Theme.Spacing.base)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Color.orange)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Demo data. These answers are canned samples, "
                                + "not an answer to this problem.")
        }
    }
}

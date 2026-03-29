import SwiftUI

struct ResultsView: View {
    let problemText: String
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
            chatViewModel.setProblemContext(problemText)
        }
    }

    // MARK: - iPhone Layout

    private var iphoneResultsLayout: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 4)

            if let sourceImage = viewModel.sourceImage {
                imageCard(sourceImage)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            } else if problemText != "[Scanned Image]" {
                problemCard
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            }

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
            .id(viewModel.selectedTab)
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
                    if let sourceImage = viewModel.sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
                            .padding(Theme.Spacing.lg)
                    } else if problemText != "[Scanned Image]" && problemText != "Scanning..." {
                        Text(problemText)
                            .font(Theme.Fonts.math(16))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .padding(Theme.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                            .padding(Theme.Spacing.lg)
                    }

                    ChatView(viewModel: chatViewModel)
                }
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 420)
                .background(Theme.Colors.secondaryBackground.opacity(0.3))

                Divider()

                // RIGHT: Tabs + content
                VStack(spacing: 0) {
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
                    .id(viewModel.selectedTab)
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

    // MARK: - Image Card

    private func imageCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
            .cardStyle()
    }

    // MARK: - Problem Text Card

    private var problemCard: some View {
        HStack {
            Text(problemText)
                .font(Theme.Fonts.math(14))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(3)
            Spacer()
        }
        .padding(Theme.Spacing.base)
        .cardStyle()
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func contentForTab(_ tab: ResultTab) -> some View {
        switch tab {
        case .steps:
            StepByStepView(
                steps: viewModel.steps,
                error: viewModel.stepsError,
                isLoading: viewModel.isLoadingSteps,
                onRetry: { viewModel.retrySteps() }
            )
        case .lesson:
            LessonView(
                lesson: viewModel.lesson,
                error: viewModel.lessonError,
                isLoading: viewModel.isLoadingLesson,
                onRetry: { viewModel.retryLesson() }
            )
        case .formulas:
            FormulasView(
                formulas: viewModel.formulas,
                error: viewModel.formulasError,
                isLoading: viewModel.isLoadingFormulas,
                onRetry: { viewModel.retryFormulas() }
            )
        case .videos:
            VideosView(
                videos: viewModel.videos,
                error: viewModel.videosError,
                isLoading: viewModel.isLoadingVideos,
                onRetry: { viewModel.retryVideos() }
            )
        case .chat:
            ChatView(viewModel: chatViewModel)
        }
    }

    // MARK: - Share

    private var shareableText: String {
        var parts: [String] = ["Problem: \(problemText)"]
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

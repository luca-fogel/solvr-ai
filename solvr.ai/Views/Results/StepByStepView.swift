import SwiftUI
import SolvrCore

struct StepByStepView: View {
    let steps: [StepItem]?
    let error: SolverError?
    let isLoading: Bool
    var onRetry: (() -> Void)?

    var body: some View {
        if isLoading {
            loadingState
        } else if let error {
            ScrollView {
                ErrorCard(error: error, onRetry: onRetry)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.base)
            }
        } else if let steps, !steps.isEmpty {
            MathPageView(html: HTMLBuilder.buildStepsHTML(steps: steps))
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.base) {
                IndeterminateProgressBar()
                    .padding(.horizontal, Theme.Spacing.lg)

                ShimmerLoadingView(lineCount: 6)
                    .padding(Theme.Spacing.base)
                    .cardStyle()
                    .padding(.horizontal, Theme.Spacing.lg)

                Text("Solving step by step...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.top, Theme.Spacing.base)
        }
    }
}

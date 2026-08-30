import SwiftUI
import SolvrCore

struct StepByStepView: View {
    let state: SurfaceState<[StepItem]>
    var onRetry: (() -> Void)?

    // Exhaustive by construction: every state the surface can be in has a
    // branch, and a new one will not compile until it has a branch too. The
    // version this replaced had no `else`, so "nothing to show" showed nothing.
    var body: some View {
        switch state {
        case .idle:
            SurfaceIdleCard(message: "Not solved yet.", onLoad: onRetry)
        case .loading:
            loadingState
        case .failed(let error):
            ScrollView {
                ErrorCard(error: error, onRetry: onRetry)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.base)
            }
        case .empty:
            SurfaceEmptyCard(message: "The model did not return any working for this one.",
                             onRetry: onRetry)
        case .ready(let steps):
            VStack(spacing: 0) {
                MathPageView(html: HTMLBuilder.buildStepsHTML(steps: steps))
                // Said once, quietly, on the surface that makes the claim.
                // The model cannot check its own arithmetic and nothing in the
                // app checks it either, so the student is told rather than left
                // to assume. Not said in demo mode, where nothing was worked
                // out on this device and the banner above says so instead.
                if !DemoMode.isEnabled {
                Text("Worked out on this device by a small model. Check each step.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .accessibilityLabel("Worked out on this device by a small model. "
                                        + "Check each step before relying on it.")
                }
            }
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

import SwiftUI
import SolvrCore

struct LessonView: View {
    let lesson: LessonContent?
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
        } else if let lesson {
            MathPageView(html: HTMLBuilder.buildLessonHTML(lesson: lesson))
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.base) {
                IndeterminateProgressBar()
                    .padding(.horizontal, Theme.Spacing.lg)

                ShimmerLoadingView(lineCount: 8)
                    .padding(Theme.Spacing.base)
                    .cardStyle()
                    .padding(.horizontal, Theme.Spacing.lg)

                Text("Generating lesson...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.top, Theme.Spacing.base)
        }
    }
}

// MARK: - Error Card

struct ErrorCard: View {
    let error: SolverError
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: error.icon)
                .font(.system(size: 32))
                .foregroundStyle(Theme.Colors.warning)

            Text(error.title)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(error.errorDescription ?? "Something went wrong.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            if let onRetry {
                Button {
                    Haptics.light()
                    onRetry()
                } label: {
                    Text("Try again")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .overlay(
                            Capsule().stroke(Theme.Colors.accent, lineWidth: 1)
                        )
                }
                .pressAnimation()
            }

            if let detail = error.debugDetail {
                Text(detail)
                    .font(Theme.Fonts.math(11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

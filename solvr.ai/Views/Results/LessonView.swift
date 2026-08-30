import SwiftUI
import SolvrCore

struct LessonView: View {
    let state: SurfaceState<LessonContent>
    var onRetry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle:
            SurfaceIdleCard(message: "Teach me this topic.", onLoad: onRetry)
        case .loading:
            loadingState
        case .failed(let error):
            ScrollView {
                ErrorCard(error: error, onRetry: onRetry)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.base)
            }
        case .empty:
            SurfaceEmptyCard(message: "The model did not return a lesson for this one.",
                             onRetry: onRetry)
        case .ready(let lesson):
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

// MARK: - The two states that used to be a blank screen

/// A tab that has not been asked for yet.
///
/// New with lazy fetching, and the common case: the on-device model answers one
/// request at a time, so asking for all four surfaces the moment a problem is
/// solved makes the student wait through three generations they did not ask for.
/// A tab is generated when it is opened -- this is what it looks like in the
/// instant before that happens, and if the automatic fetch ever fails to fire,
/// the button is the way out rather than an empty screen.
struct SurfaceIdleCard: View {
    let message: String
    var onLoad: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.accent)

            Text(message)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            if let onLoad {
                Button {
                    Haptics.light()
                    onLoad()
                } label: {
                    Text("Generate")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, Theme.Spacing.base)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Generate this section")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
    }
}

/// Answered, with nothing in it. Not an error: the model returned, it just
/// returned nothing, and saying so is better than drawing an empty page.
struct SurfaceEmptyCard: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text(message)
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
                        .padding(.horizontal, Theme.Spacing.base)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try this section again")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
    }
}

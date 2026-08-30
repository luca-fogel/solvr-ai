import SwiftUI
import SolvrCore

struct FormulasView: View {
    let state: SurfaceState<[FormulaItem]>
    var onRetry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle:
            SurfaceIdleCard(message: "Show the formulas this needs.", onLoad: onRetry)
        case .loading:
            loadingState
        case .failed(let error):
            ScrollView {
                ErrorCard(error: error, onRetry: onRetry)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.base)
            }
        case .empty:
            SurfaceEmptyCard(message: "The model did not return any formulas for this one.",
                             onRetry: onRetry)
        case .ready(let formulas):
            MathPageView(html: HTMLBuilder.buildFormulasHTML(formulas: formulas))
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

                Text("Loading formulas...")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.top, Theme.Spacing.base)
        }
    }
}

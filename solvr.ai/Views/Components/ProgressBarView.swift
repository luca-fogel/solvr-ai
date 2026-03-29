import SwiftUI

// MARK: - Indeterminate Progress Bar

struct IndeterminateProgressBar: View {
    @State private var offset: CGFloat = -0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.tertiaryBackground)

                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: geo.size.width * 0.3)
                    .offset(x: offset * geo.size.width)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                offset = 1.0
            }
        }
    }
}

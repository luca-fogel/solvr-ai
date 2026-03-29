import SwiftUI

struct ShimmerLoadingView: View {
    var lineCount: Int = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(0..<lineCount, id: \.self) { index in
                ShimmerLine(widthFraction: lineWidth(for: index))
            }
        }
        .padding(Theme.Spacing.base)
    }

    private func lineWidth(for index: Int) -> CGFloat {
        switch index % 5 {
        case 0: return 1.0
        case 1: return 0.85
        case 2: return 1.0
        case 3: return 0.85
        default: return 0.6
        }
    }
}

struct ShimmerLine: View {
    let widthFraction: CGFloat
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Colors.tertiaryBackground)

                LinearGradient(
                    colors: [
                        .clear,
                        Theme.Colors.separator.opacity(0.6),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: phase * geo.size.width * 1.4 - geo.size.width * 0.2)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(width: geo.size.width * widthFraction)
        }
        .frame(height: 14)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

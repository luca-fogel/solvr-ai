import SwiftUI

struct SplashScreen: View {
    @State private var showLogo = false
    @State private var showText = false
    @State private var finished = false

    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.base) {
                Text("solvr.")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    .scaleEffect(showLogo ? 1.0 : 0.8)
                    .opacity(showLogo ? 1.0 : 0.0)

                Text("point. snap. learn.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .opacity(showText ? 1.0 : 0.0)
                    .offset(y: showText ? 0 : 8)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
                showLogo = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                showText = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    finished = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onFinished()
                }
            }
        }
        .opacity(finished ? 0 : 1)
    }
}

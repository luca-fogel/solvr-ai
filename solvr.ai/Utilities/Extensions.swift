import SwiftUI

// MARK: - Card Style

extension View {
    func cardStyle() -> some View {
        self
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    func subtleShadow() -> some View {
        self.shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Staggered Animation

extension View {
    func staggeredAppear(index: Int, show: Bool) -> some View {
        self
            .opacity(show ? 1 : 0)
            .offset(y: show ? 0 : 12)
            .animation(
                Theme.Animation.standard.delay(Double(index) * Theme.Animation.stagger),
                value: show
            )
    }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay(
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Theme.Colors.separator.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6 - geo.size.width * 0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.lg, style: .continuous))
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmer(isActive: Bool) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - JSON Cleaning

extension String {
    func cleanJSON() -> String {
        var cleaned = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractJSONArray() -> String {
        let cleaned = self.cleanJSON()
        guard let startIdx = cleaned.firstIndex(of: "["),
              let endIdx = cleaned.lastIndex(of: "]") else {
            return cleaned
        }
        return String(cleaned[startIdx...endIdx])
    }

    func extractJSONObject() -> String {
        let cleaned = self.cleanJSON()
        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        return String(cleaned[startIdx...endIdx])
    }

    func markdownAttributed() -> AttributedString {
        do {
            return try AttributedString(markdown: self, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(self)
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

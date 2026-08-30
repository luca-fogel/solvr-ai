import SwiftUI

struct TopicChips: View {
    let topics: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(topics, id: \.self) { topic in
                    TopicChip(title: topic) {
                        onSelect(topic)
                    }
                    // VoiceOver reads "Algebra, button" otherwise, which does
                    // not say that tapping fills the field with an example.
                    .accessibilityLabel("\(topic) example")
                    .accessibilityHint("Fills the box with an example \(topic.lowercased()) problem")
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
    }
}

struct TopicChip: View {
    let title: String
    let action: () -> Void
    @State private var isTapped = false

    var body: some View {
        Button(action: {
            Haptics.selection()
            withAnimation(Theme.Animation.standard) {
                isTapped = true
            }
            action()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(Theme.Animation.standard) {
                    isTapped = false
                }
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isTapped ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.base)
                .padding(.vertical, 10)
                .background(isTapped ? Theme.Colors.accentSubtle : Theme.Colors.background)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isTapped ? Theme.Colors.accent : Theme.Colors.separator,
                            lineWidth: 1
                        )
                )
        }
        .scaleEffect(isTapped ? 1.05 : 1.0)
        .pressAnimation()
    }
}

import SwiftUI

enum Theme {

    // MARK: - Colors

    enum Colors {
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let tertiaryBackground = Color(.tertiarySystemBackground)
        static let groupedBackground = Color(.systemGroupedBackground)

        static let textPrimary = Color(.label)
        static let textSecondary = Color(.secondaryLabel)
        static let textTertiary = Color(.tertiaryLabel)

        // Single accent — indigo
        static let accent = Color.indigo
        static let accentSubtle = Color.indigo.opacity(0.1)

        static let separator = Color(.separator)
        static let success = Color(.systemGreen)
        static let error = Color(.systemRed)
        static let warning = Color(.systemOrange)

        // Math expression text
        static let mathText = Color(.label)
    }

    // MARK: - Typography

    enum Fonts {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.bold)
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2

        // Math — SF Mono for all mathematical expressions
        static func math(_ size: CGFloat = 17) -> Font {
            .system(size: size, weight: .regular, design: .monospaced)
        }

        static func mathBold(_ size: CGFloat = 17) -> Font {
            .system(size: size, weight: .semibold, design: .monospaced)
        }
    }

    // MARK: - Spacing (Apple HIG: 8pt grid)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radii

    enum Radii {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    // MARK: - Animation

    enum Animation {
        static let standard = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.85)
        static let quick = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.9)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let stagger: Double = 0.08
    }
}

// MARK: - Press Button Style

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.Animation.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
    }
}

extension View {
    func pressAnimation() -> some View {
        self.buttonStyle(PressButtonStyle())
    }
}

// MARK: - Hover Button Style (Mac)

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(isHovered ? 0.8 : 1.0)
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(Theme.Animation.quick, value: configuration.isPressed)
            .animation(Theme.Animation.quick, value: isHovered)
    }
}

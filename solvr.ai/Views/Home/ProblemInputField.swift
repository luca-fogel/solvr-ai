import SwiftUI

struct FloatingInputBar: View {
    @Binding var text: String
    var scanSuccess: Bool
    var isScanning: Bool
    @FocusState.Binding var isFocused: Bool
    var onCamera: () -> Void
    var onSolve: () -> Void
    var canSolve: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Scan success toast
            if scanSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("Text scanned successfully")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Colors.success)
                }
                .padding(.vertical, Theme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Input bar
            HStack(spacing: Theme.Spacing.md) {
                // Camera button
                Button(action: onCamera) {
                    if isScanning {
                        ProgressView()
                            .tint(Theme.Colors.accent)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(width: 36, height: 36)

                // Text input
                TextField("What are we solving?", text: $text, axis: .vertical)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1...4)
                    .focused($isFocused)

                // Send button
                if canSolve {
                    Button(action: onSolve) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.Colors.accent)
                            .clipShape(Circle())
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Spacing.base)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(
                        isFocused ? Theme.Colors.accent : Theme.Colors.separator,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: -2)
            .animation(Theme.Animation.smooth, value: isFocused)
            .animation(Theme.Animation.standard, value: canSolve)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

// Legacy name for compilation compatibility
struct ProblemInputField: View {
    @Binding var text: String
    var scanSuccess: Bool
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        TextField("What are we solving?", text: $text)
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(Theme.Spacing.base)
            .background(Theme.Colors.background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radii.md, style: .continuous)
                    .stroke(isFocused ? Theme.Colors.accent : Theme.Colors.separator, lineWidth: 1)
            )
            .focused($isFocused)
    }
}

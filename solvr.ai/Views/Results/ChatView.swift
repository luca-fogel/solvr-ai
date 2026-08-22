import SwiftUI
import SolvrCore

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        if viewModel.messages.isEmpty {
                            chatEmptyState
                                .padding(.top, 40)
                        }

                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.lg)
                            .id("typing")
                        }
                    }
                    .padding(.top, Theme.Spacing.base)
                    .padding(.bottom, Theme.Spacing.sm)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation {
                        if let last = viewModel.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, loading in
                    if loading {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            // Suggested prompts
            if viewModel.messages.isEmpty {
                suggestedChips
            }

            // Input bar
            chatInputBar
        }
        .background(Theme.Colors.background)
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accent.opacity(0.3))

            Text("Ask me anything")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    // MARK: - Suggested Chips

    private var suggestedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.suggestedPrompts, id: \.self) { prompt in
                    Button {
                        Task {
                            await viewModel.sendMessage(prompt)
                        }
                    } label: {
                        Text(prompt)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Theme.Colors.accent.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .pressAnimation()
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)
        }
    }

    // MARK: - Input Bar

    private var chatInputBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            TextField("Ask a question...", text: $viewModel.inputText, axis: .vertical)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, Theme.Spacing.base)
                .padding(.vertical, 10)
                .background(Theme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )

            Button {
                Task {
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Theme.Colors.textTertiary
                        : Theme.Colors.accent
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .padding(.horizontal, Theme.Spacing.base)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Group {
                if isUser {
                    Text(message.content)
                        .foregroundStyle(.white)
                } else {
                    Text(message.content.markdownAttributed())
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .font(Theme.Fonts.body)
            .lineSpacing(3)
            .padding(.horizontal, Theme.Spacing.base)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                isUser
                ? AnyShapeStyle(Theme.Colors.accent)
                : AnyShapeStyle(Theme.Colors.tertiaryBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Theme.Spacing.base)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotIndex = 0
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(dotIndex == index ? 1.3 : 1.0)
                    .animation(Theme.Animation.standard, value: dotIndex)
            }
        }
        .padding(.horizontal, Theme.Spacing.base)
        .padding(.vertical, 14)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            timerTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { break }
                    dotIndex = (dotIndex + 1) % 3
                }
            }
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }
}

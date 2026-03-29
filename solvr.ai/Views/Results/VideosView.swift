import SwiftUI

struct VideosView: View {
    let videos: [VideoItem]?
    let error: ClaudeAPIManager.ClaudeError?
    let isLoading: Bool
    var onRetry: (() -> Void)?

    @State private var appeared = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.base) {
                if isLoading {
                    loadingContent
                } else if let error {
                    ErrorCard(error: error, onRetry: onRetry)
                        .padding(.horizontal, Theme.Spacing.lg)
                } else if let videos {
                    // Header
                    HStack {
                        Text("WATCH & LEARN")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.lg)

                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        videoCard(video)
                            .staggeredAppear(index: index, show: appeared)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .padding(.top, Theme.Spacing.base)
            .padding(.bottom, 40)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                appeared = true
            }
        }
    }

    // MARK: - Video Card

    private func videoCard(_ video: VideoItem) -> some View {
        Button {
            if let url = video.youtubeURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 14) {
                // Thumbnail
                ZStack {
                    if let thumbURL = video.thumbnailImageURL {
                        AsyncImage(url: thumbURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 90, height: 64)
                                    .clipped()
                            } else {
                                thumbnailPlaceholder
                            }
                        }
                    } else {
                        thumbnailPlaceholder
                    }

                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                }
                .frame(width: 90, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.sm, style: .continuous))

                // Info
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(video.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(video.channel)
                        .font(Theme.Fonts.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(14)
            .cardStyle()
        }
        .pressAnimation()
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: Theme.Radii.sm, style: .continuous)
            .fill(Theme.Colors.tertiaryBackground)
            .frame(width: 90, height: 64)
            .overlay(
                Image(systemName: "play.rectangle")
                    .foregroundStyle(Theme.Colors.textTertiary)
            )
    }

    // MARK: - Loading

    private var loadingContent: some View {
        VStack(spacing: Theme.Spacing.base) {
            IndeterminateProgressBar()

            ShimmerLoadingView(lineCount: 5)
                .padding(Theme.Spacing.base)
                .cardStyle()

            Text("Finding videos...")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

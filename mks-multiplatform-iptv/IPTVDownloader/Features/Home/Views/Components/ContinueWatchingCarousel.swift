import SwiftUI

/// Netflix-style horizontal carousel showing content with saved playback progress.
///
/// Each card displays a backdrop/poster, play icon overlay, title, and progress bar.
/// Context menu allows removing items from Continue Watching.
struct ContinueWatchingCarousel: View {
    let items: [WatchHistoryEntry]
    let onPlay: (WatchHistoryEntry) -> Void
    let onRemove: (WatchHistoryEntry) -> Void

    #if os(iOS)
    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 140
    #else
    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 150
    #endif

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                ForEach(items, id: \.contentId) { entry in
                    ContinueWatchingCard(
                        entry: entry,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        onPlay: { onPlay(entry) },
                        onRemove: { onRemove(entry) }
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Continue Watching Card

struct ContinueWatchingCard: View {
    let entry: WatchHistoryEntry
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .bottom) {
                // Backdrop/poster image
                imageLayer
                    .frame(width: cardWidth, height: cardHeight)
                    .clipped()

                // Play icon overlay (center)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom gradient + title + progress
                bottomOverlay
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove from Continue Watching", systemImage: "xmark.circle")
            }
        }
    }

    @ViewBuilder
    private var imageLayer: some View {
        let imageURL = entry.backdropURL ?? entry.posterURL

        if let urlStr = imageURL, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        AppColors.surface
            .overlay {
                Image(systemName: entry.contentType == "episode" ? "tv" : "film")
                    .font(.title2)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let episodeTitle = entry.episodeTitle, !episodeTitle.isEmpty {
                    Text(episodeTitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(AppColors.accent)
                            .frame(width: geometry.size.width * entry.progress, height: 3)
                    }
                }
                .frame(height: 3)

                if let remaining = entry.remainingTimeFormatted {
                    Text(remaining)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .padding(.top, 20)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Recent Channels Carousel

/// Horizontal carousel showing recently watched live channels.
struct RecentChannelsCarousel: View {
    let channels: [RecentChannelEntry]
    @Binding var selectedView: String?

    var body: some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(channels, id: \.channelStreamId) { channel in
                        Button {
                            selectedView = NavigationDestination.liveChannels.rawValue
                        } label: {
                            recentChannelCard(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func recentChannelCard(channel: RecentChannelEntry) -> some View {
        VStack(spacing: 8) {
            if let iconURL = channel.channelIcon, let url = URL(string: iconURL) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        channelPlaceholder
                    }
                }
            } else {
                channelPlaceholder
            }

            Text(channel.channelName)
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
        }
        .padding(10)
        .frame(width: 100, height: 100)
        .background(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(Color.white.opacity(0.04))
        )
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
    }

    private var channelPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.surface)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "tv")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }
}

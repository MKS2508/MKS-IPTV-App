//
//  HomeView.swift
//  mks-multiplatform-iptv
//
//  Netflix-style Home screen composing hero banner, EPG sections,
//  recently added content, category spotlights, and live TV categories
//

import SwiftUI

struct HomeView: View {
    let homeViewModel: HomeViewModel
    @Binding var selectedView: String?

    @EnvironmentObject private var profile: IPTVProfile

    // Continue Watching player state
    @State private var cwActivePlayer: (any VideoPlayerProtocol)?
    @State private var cwShowingPlayer = false
    @State private var cwPlaybackTracker = PlaybackTracker()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(homeViewModel.sections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.black)
        .navigationTitle("Home")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .fullscreenPlayer(
            isPresented: $cwShowingPlayer,
            player: cwActivePlayer,
            title: "",
            stopOnDismiss: true
        )
        .onChange(of: cwShowingPlayer) { _, isShowing in
            if !isShowing {
                cwPlaybackTracker.stopTracking()
                cwActivePlayer?.stop()
                cwActivePlayer = nil
                // Refresh continue watching after player dismissal
                Task {
                    await homeViewModel.insertContinueWatchingSection(profileId: profile.id)
                }
            }
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section.type {
        case .heroBanner(let item):
            HeroBannerView(item: item, selectedView: $selectedView)

        case .continueWatching(let items):
            sectionHeader(title: section.title, icon: section.iconName)
            ContinueWatchingCarousel(
                items: items,
                onPlay: { entry in playContinueWatchingEntry(entry) },
                onRemove: { entry in removeContinueWatchingEntry(entry) }
            )

        case .recentChannels(let channels):
            sectionHeader(title: section.title, icon: section.iconName)
            RecentChannelsCarousel(channels: channels, selectedView: $selectedView)

        case .nowOnTV(let channels):
            sectionHeader(title: section.title, icon: section.iconName)
            NowOnTVCarousel(channels: channels, selectedView: $selectedView)

        case .comingUpNext(let programmes):
            sectionHeader(title: section.title, icon: section.iconName)
            ComingUpNextTimeline(programmes: programmes)

        case .mediaCarousel(let items):
            sectionHeader(title: section.title, icon: section.iconName)
            HomeMediaCarousel(items: items, selectedView: $selectedView)

        case .liveTVCategory(let channels, _):
            sectionHeader(title: section.title, icon: section.iconName)
            liveTVCarousel(channels: channels)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String?) -> some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.accent)
            }
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Live TV Category Carousel

    private func liveTVCarousel(channels: [LiveChannel]) -> some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(channels) { channel in
                        Button {
                            selectedView = NavigationDestination.liveChannels.rawValue
                        } label: {
                            liveChannelMiniCard(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func liveChannelMiniCard(channel: LiveChannel) -> some View {
        VStack(spacing: 8) {
            // Channel icon
            if let iconURL = channel.streamIcon, let url = URL(string: iconURL) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    default:
                        channelIconPlaceholder
                    }
                }
            } else {
                channelIconPlaceholder
            }

            Text(channel.name)
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

    private var channelIconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.surface)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "tv")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }

    // MARK: - Continue Watching Actions

    /// Play a continue watching entry — rebuilds the stream URL and seeks to saved position.
    private func playContinueWatchingEntry(_ entry: WatchHistoryEntry) {
        let ext = entry.containerExtension ?? "mkv"
        let urlString: String

        if entry.contentType == "movie" {
            urlString = IPTVConfiguration.buildMovieURL(
                profile: profile,
                vodID: entry.contentId,
                vodExtension: ext
            )
        } else {
            urlString = IPTVConfiguration.buildSeriesURL(
                profile: profile,
                vodID: entry.contentId,
                vodExtension: ext
            )
        }

        guard let url = URL(string: urlString) else { return }

        let player = PlayerFactory.shared.createPlayer(for: url)
        player.play()

        let identity = ContentIdentity(
            profileId: profile.id,
            contentType: entry.contentType,
            contentId: entry.contentId,
            displayTitle: entry.displayTitle,
            posterURL: entry.posterURL,
            backdropURL: entry.backdropURL,
            seriesId: entry.seriesId,
            showTitle: entry.showTitle,
            seasonNumber: entry.seasonNumber,
            episodeNumber: entry.episodeNumber,
            episodeTitle: entry.episodeTitle,
            containerExtension: entry.containerExtension
        )
        cwPlaybackTracker.startTracking(player: player, content: identity)

        // Seek to saved position once player is ready (handles transmux startup latency)
        let seekPosition = entry.lastPosition
        Task { @MainActor in
            for attempt in 0..<150 {
                if player.isReady && player.duration > 0 {
                    player.seek(to: seekPosition)
                    print("[ContinueWatching] Seeked to \(String(format: "%.1f", seekPosition))s (after \(attempt * 100)ms)")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        #if os(macOS)
        PlayerWindowManager.shared.present(player: player, title: entry.displayTitle)
        // Note: openWindow(id: "player") requires @Environment(\.openWindow) which
        // is available via the scene; handled in MainWindowContent
        #else
        cwActivePlayer = player
        cwShowingPlayer = true
        #endif
    }

    /// Remove a continue watching entry.
    private func removeContinueWatchingEntry(_ entry: WatchHistoryEntry) {
        Task {
            try? await WatchHistoryManager.shared?.deleteEntry(
                profileId: entry.profileId,
                contentType: entry.contentType,
                contentId: entry.contentId
            )
            await homeViewModel.insertContinueWatchingSection(profileId: profile.id)
        }
    }
}

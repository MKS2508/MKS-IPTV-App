//
//  HomeView.swift
//  mks-multiplatform-iptv
//
//  Apple TV-style Home screen with:
//  - Native Liquid Glass styling (iOS 26+)
//  - Cinematic hero banner
//  - Elegant section headers with glass chips
//  - Smooth scrolling and focus management
//  - Proper spacing and visual hierarchy
//

import SwiftUI
import IPTVCore

// MARK: - Home View

/// Apple TV-style home screen with cinematic presentation.
///
/// **Design Principles:**
/// - Full-bleed hero banner at top
/// - Horizontal carousels with consistent spacing
/// - Native Liquid Glass for all interactive elements
/// - Smooth entrance animations
/// - Focus-friendly for tvOS
///
struct HomeView: View {
    let homeViewModel: HomeViewModel
    @Binding var selectedView: String?

    @EnvironmentObject private var profile: IPTVProfile

    // Continue Watching player state
    @State private var cwActivePlayer: (any VideoPlayerProtocol)?
    @State private var cwShowingPlayer = false
    @State private var cwPlaybackTracker = PlaybackTracker()

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: sectionSpacing) {
                ForEach(homeViewModel.sections) { section in
                    sectionView(for: section)
                }
            }
            .padding(.bottom, 80)
        }
        .background(homeBackground)
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
                handlePlayerDismissal()
            }
        }
    }

    // MARK: - Layout Constants

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
        return 48
        #else
        return 28
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 20
        #endif
    }

    // MARK: - Background

    private var homeBackground: some View {
        VStack {
            // Subtle gradient at top for depth
            LinearGradient(
                colors: [
                    .black.opacity(0.3),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 200)

            Spacer()
        }
        .ignoresSafeArea()
        .background(Color.black)
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionView(for section: HomeSection) -> some View {
        switch section.type {
        case .heroBanner(let item):
            HeroBannerView(item: item, selectedView: $selectedView)
                .padding(.horizontal, heroHorizontalPadding)

        case .continueWatching(let items):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .prominent
            ) {
                ContinueWatchingCarousel(
                    items: items,
                    onPlay: { entry in playContinueWatchingEntry(entry) },
                    onRemove: { entry in removeContinueWatchingEntry(entry) }
                )
            }

        case .recentChannels(let channels):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .standard
            ) {
                RecentChannelsCarousel(channels: channels, selectedView: $selectedView)
            }

        case .nowOnTV(let channels):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .standard
            ) {
                NowOnTVCarousel(channels: channels, selectedView: $selectedView)
            }

        case .comingUpNext(let programmes):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .standard
            ) {
                ComingUpNextTimeline(programmes: programmes)
            }

        case .mediaCarousel(let items):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .standard
            ) {
                HomeMediaCarousel(items: items, selectedView: $selectedView)
            }

        case .liveTVCategory(let channels, _):
            HomeSectionContainer(
                title: section.title,
                icon: section.iconName,
                style: .standard
            ) {
                liveTVCarousel(channels: channels)
            }
        }
    }

    private var heroHorizontalPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 0
        #endif
    }

    // MARK: - Live TV Category Carousel

    private func liveTVCarousel(channels: [LiveChannel]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(channels) { channel in
                    Button {
                        selectedView = NavigationDestination.liveChannels.rawValue
                    } label: {
                        AppleTVLiveChannelCard(channel: channel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 12
        #endif
    }

    // MARK: - Continue Watching Actions

    private func handlePlayerDismissal() {
        cwPlaybackTracker.stopTracking()
        cwActivePlayer?.stop()
        cwActivePlayer = nil
        Task {
            await homeViewModel.insertContinueWatchingSection(profileId: profile.id)
        }
    }

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

        // Seek to saved position once player is ready
        let seekPosition = entry.lastPosition
        Task { @MainActor in
            for attempt in 0..<150 {
                if player.isReady && player.duration > 0 {
                    player.seek(to: seekPosition)
                    MKSLog.app.debug("[ContinueWatching] Seeked to \(String(format: "%.1f", seekPosition))s")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        #if os(macOS)
        PlayerWindowManager.shared.present(player: player, title: entry.displayTitle)
        #else
        cwActivePlayer = player
        cwShowingPlayer = true
        #endif
    }

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

// MARK: - Home Section Container

/// Styled container for home sections with title and optional glass effect.
struct HomeSectionContainer<Content: View>: View {
    let title: String
    let icon: String?
    let style: Style
    @ViewBuilder let content: () -> Content

    enum Style {
        case prominent  // Larger header, more spacing
        case standard   // Standard header
    }

    var body: some View {
        VStack(alignment: .leading, spacing: headerSpacing) {
            // Section header
            sectionHeader

            // Content
            content()
        }
    }

    private var headerSpacing: CGFloat {
        switch style {
        case .prominent: return 16
        case .standard: return 12
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(headerIconFont)
                    .foregroundStyle(AppColors.accent)
            }

            Text(title)
                .font(headerFont)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, style == .prominent ? 16 : 8)
    }

    private var headerFont: Font {
        switch style {
        case .prominent:
            #if os(tvOS)
            return .title2.weight(.bold)
            #else
            return .title3.weight(.bold)
            #endif
        case .standard:
            return .headline.weight(.semibold)
        }
    }

    private var headerIconFont: Font {
        switch style {
        case .prominent: return .title3
        case .standard: return .subheadline
        }
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 20
        #endif
    }
}

// MARK: - Apple TV Live Channel Card

/// Apple TV-style live channel card with Liquid Glass styling.
struct AppleTVLiveChannelCard: View {
    let channel: LiveChannel
    @State private var isFocused = false

    private let cardSize: CGFloat = {
        #if os(tvOS)
        return 140
        #else
        return 100
        #endif
    }()

    var body: some View {
        VStack(spacing: 10) {
            // Channel icon
            channelIcon
                .frame(width: iconSize, height: iconSize)

            // Channel name
            Text(channel.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: cardSize - 20)
        }
        .frame(width: cardSize, height: cardSize)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .stroke(isFocused ? AppColors.accent.opacity(0.6) : .white.opacity(0.1), lineWidth: isFocused ? 2 : 1)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.name)
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        return 56
        #else
        return 44
        #endif
    }

    @ViewBuilder
    private var channelIcon: some View {
        if let iconURL = channel.streamIcon, let url = URL(string: iconURL) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure, .empty:
                    iconPlaceholder
                @unknown default:
                    iconPlaceholder
                }
            }
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .overlay {
                Image(systemName: "tv")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
            }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(.white.opacity(0.05))
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: AppGlass.cornerRadiusSmall))
        } else {
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(.white.opacity(0.05))
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Previews

#Preview("Home View") {
    NavigationStack {
        HomeView(
            homeViewModel: HomeViewModel(),
            selectedView: .constant(nil)
        )
    }
    .environmentObject(IPTVProfile(name: "Test", baseURL: "http://test.com", username: "test", password: "test"))
}

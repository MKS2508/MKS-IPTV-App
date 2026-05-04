//
//  LiveChannelsGridView.swift
//  mks-multiplatform-iptv
//
//  Modern Live TV grid UI with native iOS 26+ Liquid Glass design:
//  - GlassEffectContainer for grouped glass elements
//  - Adaptive glass with fallbacks for older OS
//  - Efficient rendering for 571+ channels
//  - Platform-specific adaptations (iOS/macOS/tvOS)
//

import SwiftUI
import AVKit
import os
import TransmuxCore
import IPTVCore

// MARK: - View Mode

/// Display mode for channels
enum ChannelViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }
}

// MARK: - Live Channels Grid View

/// Modern Live TV UI with native Liquid Glass styling.
///
/// **Architecture Notes:**
/// - Components are extracted for better diffing performance with 571+ channels
/// - Uses `LiveChannelCard` with modes instead of separate card views
/// - Category filter uses `GlassCategoryFilterBar` with `GlassEffectContainer`
/// - Detail sheet is extracted to `LiveChannelDetailSheet`
///
struct LiveChannelsGridView: View {
    // MARK: - Environment

    @EnvironmentObject var profile: IPTVProfile
    @EnvironmentObject var viewModel: LiveChannelListViewModel
    @StateObject private var favoritesManager = LiveChannelFavoritesManager.shared

    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    // MARK: - State

    @State private var viewMode: ChannelViewMode = .grid
    @State private var selectedChannel: LiveChannel?
    @State private var showDetailSheet = false
    @State private var activePlayer: (any VideoPlayerProtocol)?
    @State private var showFullscreenPlayer = false
    @State private var playerTitle = ""

    // MARK: - Platform-Specific Configuration

    #if os(iOS)
    private let cardMinWidth: CGFloat = 160
    private let cardMaxWidth: CGFloat = 200
    private let gridSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    #else
    private let cardMinWidth: CGFloat = 180
    private let cardMaxWidth: CGFloat = 240
    private let gridSpacing: CGFloat = 14
    private let horizontalPadding: CGFloat = 20
    #endif

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: cardMaxWidth), spacing: gridSpacing, alignment: .top)]
    }

    // MARK: - Logger

    private let logger = Logger(subsystem: "LiveChannelsGridView", category: "UI")

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle("Live TV")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .searchable(
                text: $viewModel.searchText,
                placement: .automatic,
                prompt: "Search channels..."
            )
            .refreshable {
                await refreshChannels()
            }
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showDetailSheet) {
                if let channel = selectedChannel {
                    LiveChannelDetailSheet(
                        channel: channel,
                        categoryName: viewModel.categoryName(for: channel.categoryId),
                        onPlay: { handleDirectPlay(channel: channel) },
                        onFavorite: { viewModel.toggleFavorite(channel.streamId) },
                        isFavorite: viewModel.isFavorite(channel.streamId),
                        onClose: {
                            selectedChannel = nil
                            showDetailSheet = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .fullscreenPlayer(
                isPresented: $showFullscreenPlayer,
                player: activePlayer,
                title: playerTitle,
                stopOnDismiss: true
            )
            .task {
                await loadInitialData()
            }
    }

    // MARK: - Main Content

    private var contentView: some View {
        VStack(spacing: 0) {
            // Category Filter Bar
            #if os(iOS)
            GlassCategoryFilterBar(
                categories: viewModel.categories,
                selectedCategory: $viewModel.selectedCategoryId,
                favoritesCount: favoritesManager.favoriteIds.count,
                onCategorySelected: { _ in hapticLight() }
            )
            #endif

            // Main content
            mainContent
        }
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.loadingState {
        case .loading:
            loadingView

        case .failed(let error):
            errorView(error)

        case .loaded:
            if viewModel.filteredDisplayModels.isEmpty {
                emptyView
            } else {
                channelsList
            }

        case .idle:
            loadingView
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading channels...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: ChannelError) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "An unknown error occurred")
        } actions: {
            Button {
                Task { await refreshChannels() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Channels Found", systemImage: "tv.slash")
        } description: {
            if viewModel.searchText.isEmpty {
                Text("No channels in this category")
            } else {
                Text("No channels match '\(viewModel.searchText)'")
            }
        } actions: {
            if !viewModel.searchText.isEmpty {
                Button("Clear Search") {
                    viewModel.searchText = ""
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Channels List

    private var channelsList: some View {
        ScrollView {
            switch viewMode {
            case .grid:
                gridView
            case .list:
                listView
            }
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        LazyVGrid(columns: columns, spacing: gridSpacing) {
            ForEach(viewModel.filteredDisplayModels, id: \.id) { displayModel in
                LiveChannelCard(
                    displayModel: displayModel,
                    mode: .compact,
                    onTap: {
                        hapticLight()
                        handleDirectPlay(channel: displayModel.channel)
                    },
                    onLongPress: {
                        hapticMedium()
                        selectedChannel = displayModel.channel
                        showDetailSheet = true
                    }
                )
                .contextMenu {
                    channelContextMenu(for: displayModel)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 16)
    }

    // MARK: - List View

    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.filteredDisplayModels, id: \.id) { displayModel in
                LiveChannelCard(
                    displayModel: displayModel,
                    mode: .regular,
                    onTap: {
                        hapticLight()
                        handleDirectPlay(channel: displayModel.channel)
                    },
                    onLongPress: {
                        hapticMedium()
                        selectedChannel = displayModel.channel
                        showDetailSheet = true
                    },
                    onFavoriteToggle: {
                        viewModel.toggleFavorite(displayModel.id)
                        hapticSuccess()
                    }
                )
                .contextMenu {
                    channelContextMenu(for: displayModel)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    favoriteSwipeAction(for: displayModel)
                }
                .swipeActions(edge: .leading) {
                    playSwipeAction(for: displayModel)
                }

                Divider()
                    .padding(.leading, 80)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, horizontalPadding)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func channelContextMenu(for displayModel: LiveChannelDisplayModel) -> some View {
        Button {
            handleDirectPlay(channel: displayModel.channel)
        } label: {
            Label("Play", systemImage: "play.fill")
        }

        Button {
            selectedChannel = displayModel.channel
            showDetailSheet = true
        } label: {
            Label("Details", systemImage: "info.circle")
        }

        Divider()

        Button {
            viewModel.toggleFavorite(displayModel.id)
            hapticSuccess()
        } label: {
            Label(
                viewModel.isFavorite(displayModel.id) ? "Remove from Favorites" : "Add to Favorites",
                systemImage: viewModel.isFavorite(displayModel.id) ? "star.slash" : "star"
            )
        }

        Divider()

        Button {
            copyStreamURL(for: displayModel.channel)
        } label: {
            Label("Copy Stream URL", systemImage: "link")
        }
    }

    // MARK: - Swipe Actions

    @ViewBuilder
    private func favoriteSwipeAction(for displayModel: LiveChannelDisplayModel) -> some View {
        Button {
            viewModel.toggleFavorite(displayModel.id)
            hapticSuccess()
        } label: {
            Label(
                viewModel.isFavorite(displayModel.id) ? "Unfavorite" : "Favorite",
                systemImage: viewModel.isFavorite(displayModel.id) ? "star.slash.fill" : "star.fill"
            )
        }
        .tint(viewModel.isFavorite(displayModel.id) ? .orange : .yellow)
    }

    @ViewBuilder
    private func playSwipeAction(for displayModel: LiveChannelDisplayModel) -> some View {
        Button {
            handleDirectPlay(channel: displayModel.channel)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        .tint(.green)
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        // Sort menu (iOS only - uses topBarLeading)
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(ChannelSortOption.allCases) { option in
                    Button {
                        hapticLight()
                        viewModel.sortOption = option
                    } label: {
                        HStack {
                            Label(option.rawValue, systemImage: option.icon)
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }

        // View mode toggle (iOS only)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                hapticLight()
                withAnimation(.easeInOut(duration: 0.25)) {
                    viewMode = viewMode == .grid ? .list : .grid
                }
            } label: {
                Image(systemName: viewMode.icon)
            }
        }

        // Category picker (iOS)
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedCategoryId = nil
                    }
                } label: {
                    HStack {
                        Label("All Categories", systemImage: "tv")
                        if viewModel.selectedCategoryId == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if favoritesManager.favoriteIds.count > 0 {
                    Divider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedCategoryId = "favorites"
                        }
                    } label: {
                        HStack {
                            Label("Favorites", systemImage: "star.fill")
                            if viewModel.selectedCategoryId == "favorites" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                ForEach(viewModel.categories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedCategoryId = category.categoryId
                        }
                    } label: {
                        HStack {
                            Text(category.categoryName)
                            if viewModel.selectedCategoryId == category.categoryId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
        #else
        // macOS toolbar
        ToolbarItem(placement: .automatic) {
            Menu {
                Button {
                    Task { await refreshChannels() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Divider()

                ForEach(ChannelSortOption.allCases) { option in
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        HStack {
                            Label(option.rawValue, systemImage: option.icon)
                            if viewModel.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    viewModel.selectedCategoryId = nil
                } label: {
                    Label("All Channels (\(viewModel.liveChannels.count))", systemImage: "tv")
                }

                if favoritesManager.favoriteIds.count > 0 {
                    Button {
                        viewModel.selectedCategoryId = "favorites"
                    } label: {
                        Label("Favorites (\(favoritesManager.favoriteIds.count))", systemImage: "star.fill")
                    }
                }

                Divider()

                ForEach(viewModel.categories) { category in
                    Button {
                        viewModel.selectedCategoryId = category.categoryId
                    } label: {
                        HStack {
                            Text(category.categoryName)
                            if viewModel.selectedCategoryId == category.categoryId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }

        // macOS view mode toggle
        ToolbarItem(placement: .automatic) {
            Picker("View Mode", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(ChannelViewMode.grid)
                Image(systemName: "list.bullet").tag(ChannelViewMode.list)
            }
            .pickerStyle(.segmented)
        }
        #endif
    }

    // MARK: - Private Methods

    private func loadInitialData() async {
        logger.debug("Loading initial data")
        await viewModel.loadChannels()
        await viewModel.loadEPGAndBuildDisplayModels()
    }

    private func refreshChannels() async {
        logger.debug("Refreshing channels")
        hapticLight()
        await viewModel.refreshChannels()
        await viewModel.loadEPGAndBuildDisplayModels()
    }

    private func handleDirectPlay(channel: LiveChannel) {
        logger.info("[LivePlay] ▶ Starting playback for: \(channel.name) (id=\(channel.streamId))")
        hapticMedium()

        // Record channel watch for "Recently Watched" on Home
        Task {
            try? await WatchHistoryManager.shared?.recordChannelWatch(
                profileId: profile.id,
                channelStreamId: channel.streamId,
                channelName: channel.name,
                channelIcon: channel.streamIcon,
                categoryId: channel.categoryId
            )
        }

        Task {
            // Step 1: Live Segmenter pipeline (.ts → FFmpeg segment muxer → local HLS).
            logger.info("[LivePlay] Step 1: Trying live segmenter pipeline...")
            if let localURL = await startLiveSegmenterPipeline(channel: channel) {
                logger.info("[LivePlay] ✓ Segmenter pipeline OK → \(localURL.absoluteString)")
                await presentPlayer(url: localURL, title: channel.name)
                return
            }
            logger.warning("[LivePlay] ✗ Segmenter pipeline failed")

            // Step 2: LiveHLSProxy pipeline (.m3u8 → proxy upstream HLS → local serve).
            logger.info("[LivePlay] Step 2: Trying HLS proxy pipeline...")
            if let localURL = await startLiveHLSProxyPipeline(channel: channel) {
                logger.info("[LivePlay] ✓ HLS proxy pipeline OK → \(localURL.absoluteString)")
                await presentPlayer(url: localURL, title: channel.name)
                return
            }
            logger.warning("[LivePlay] ✗ HLS proxy pipeline failed")

            // Step 3: Direct URL play (last resort — may fail on AirPlay).
            logger.info("[LivePlay] Step 3: Falling back to direct URL...")
            guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: urlString) else {
                logger.error("[LivePlay] ✗ Failed to build direct stream URL")
                return
            }
            logger.info("[LivePlay] ✓ Direct URL → \(url.absoluteString)")
            await presentPlayer(url: url, title: channel.name)
        }
    }

    /// Start the live segmenter pipeline: FFmpeg segments the raw .ts stream into local HLS.
    private func startLiveSegmenterPipeline(channel: LiveChannel) async -> URL? {
        let tsURLString = IPTVConfiguration.buildLiveChannelTSURL(profile: profile, channelID: channel.streamId)
        guard let tsURL = URL(string: tsURLString) else {
            logger.error("[LivePlay] Segmenter: failed to build TS URL for channel \(channel.streamId)")
            return nil
        }
        logger.info("[LivePlay] Segmenter: TS URL = \(tsURL.absoluteString)")

        do {
            let liveSession = try await TransmuxingService.shared.startLiveTransmux(from: tsURL)
            logger.info("[LivePlay] Segmenter: FFmpeg session started, output dir = \(liveSession.outputDir)")
            let serverSession = try await TransmuxServer.shared.startLiveSegmented(
                directory: liveSession.outputDir,
                segmenter: liveSession.segmenter,
                handle: liveSession.handle
            )
            logger.info("[LivePlay] Segmenter: serving at \(serverSession.localURL.absoluteString)")
            return serverSession.localURL
        } catch {
            logger.error("[LivePlay] Segmenter error: \(error)")
            return nil
        }
    }

    /// Start the LiveHLSProxy pipeline: proxy upstream .m3u8 through a local server.
    private func startLiveHLSProxyPipeline(channel: LiveChannel) async -> URL? {
        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlString) else {
            logger.error("[LivePlay] HLS Proxy: failed to build channel URL for \(channel.streamId)")
            return nil
        }
        logger.info("[LivePlay] HLS Proxy: upstream URL = \(url.absoluteString)")

        do {
            let session = try await TransmuxServer.shared.startLive(upstreamURL: url)
            logger.info("[LivePlay] HLS Proxy: serving at \(session.localURL.absoluteString)")
            return session.localURL
        } catch {
            logger.error("[LivePlay] HLS Proxy error: \(error)")
            return nil
        }
    }

    /// Present the player on the appropriate platform.
    @MainActor
    private func presentPlayer(url: URL, title: String, isLive: Bool = true) {
        logger.info("[LivePlay] presentPlayer: url=\(url.absoluteString), isLive=\(isLive)")
        let player = PlayerFactory.shared.createPlayer(for: url, metadata: nil, isLive: isLive)
        player.play()
        logger.info("[LivePlay] Player created (type=\(type(of: player))), play() called")

        #if os(macOS)
        PlayerWindowManager.shared.present(player: player, title: title)
        openWindow(id: "player")
        logger.info("[LivePlay] macOS: opened player window")
        #else
        activePlayer = player
        playerTitle = title
        showFullscreenPlayer = true
        logger.info("[LivePlay] iOS: showFullscreenPlayer=true")
        #endif
    }

    private func copyStreamURL(for channel: LiveChannel) {
        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = urlString
        #endif

        hapticSuccess()
    }

    // MARK: - Haptic Feedback

    private func hapticLight() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func hapticMedium() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    private func hapticSuccess() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

// MARK: - Live Channel Detail Sheet

/// Detail sheet for live channel with native Liquid Glass styling.
///
/// **iOS 26+ Features:**
/// - Uses `.buttonStyle(.glassProminent)` for primary action
/// - Uses `.buttonStyle(.glass)` for secondary action
/// - Info section wrapped in `GlassEffectContainer` for proper glass blending
///
struct LiveChannelDetailSheet: View {
    let channel: LiveChannel
    let categoryName: String
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let isFavorite: Bool
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    quickActionsSection
                    infoSection
                }
                .padding()
            }
            .navigationTitle(channel.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Channel icon with glass background
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                GlassEffectContainer {
                    ChannelIconView(
                        url: URL(string: channel.streamIcon ?? ""),
                        size: CGSize(width: 100, height: 70),
                        cornerRadius: 12
                    )
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }
            } else {
                ChannelIconView(
                    url: URL(string: channel.streamIcon ?? ""),
                    size: CGSize(width: 100, height: 70),
                    cornerRadius: 12
                )
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            LiveBadge(size: .regular)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        HStack(spacing: 12) {
            // Primary action: Play button with prominent glass
            Button {
                onPlay()
                onClose()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .glassButtonStyle(isProminent: true)

            // Secondary action: Favorite button
            Button {
                onFavorite()
            } label: {
                Label(
                    isFavorite ? "Favorited" : "Favorite",
                    systemImage: isFavorite ? "star.fill" : "star"
                )
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .glassButtonStyle(isProminent: false, tintColor: isFavorite ? .yellow : nil)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent("Category", value: categoryName)
            LabeledContent("Stream ID", value: "\(channel.streamId)")

            if let timestamp = Double(channel.added),
               timestamp > 0 {
                let date = Date(timeIntervalSince1970: timestamp)
                LabeledContent("Added", value: date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding()
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall), fallbackOpacity: 0.5)
    }
}

// MARK: - Glass Button Style Extension

private extension Button {
    /// Applies glass button style with fallback for older OS versions
    @ViewBuilder
    func glassButtonStyle(isProminent: Bool = false, tintColor: Color? = nil) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            if isProminent {
                self.buttonStyle(.glassProminent)
            } else {
                if let tint = tintColor {
                    self.buttonStyle(.glass)
                        .tint(tint)
                } else {
                    self.buttonStyle(.glass)
                }
            }
        } else {
            if isProminent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
                if let tint = tintColor {
                    self.tint(tint)
                }
            }
        }
    }
}

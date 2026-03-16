//
//  LiveChannelsGridView.swift
//  mks-multiplatform-iptv
//
//  Modern Live TV grid UI with native iOS patterns:
//  - Haptic feedback on interactions
//  - Context menus for quick actions
//  - Pull-to-refresh
//  - Adaptive grid/list toggle
//  - Native search and sort
//

import SwiftUI
import AVKit
import os
import TransmuxCore

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

/// Modern Live TV UI with native iOS patterns.
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
    @State private var showSortSheet = false
    @State private var showCategoryPicker = false

    @Namespace private var animation

    // MARK: - Platform-Specific Configuration
    #if os(iOS)
    private let cardMinWidth: CGFloat = 160
    private let cardMaxWidth: CGFloat = 200
    private let gridSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    #else
    private let cardMinWidth: CGFloat = 200
    private let cardMaxWidth: CGFloat = 260
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
            .onChange(of: viewModel.searchText) { _, newValue in
                // Debounce is handled in ViewModel
            }
    }

    // MARK: - Main Content
    private var contentView: some View {
        VStack(spacing: 0) {
            // Category Filter Bar (iOS only)
            #if os(iOS)
            categoryFilterBar
            #endif

            // Main content
            mainContent
        }
    }

    // MARK: - Category Filter Bar
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All categories
                CategoryChip(
                    title: "All",
                    icon: "tv",
                    count: viewModel.liveChannels.count,
                    isSelected: viewModel.selectedCategoryId == nil
                ) {
                    hapticLight()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedCategoryId = nil
                    }
                }

                // Favorites
                if favoritesManager.favoriteIds.count > 0 {
                    CategoryChip(
                        title: "Favorites",
                        icon: "star.fill",
                        count: favoritesManager.favoriteIds.count,
                        isSelected: viewModel.selectedCategoryId == "favorites"
                    ) {
                        hapticLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedCategoryId = "favorites"
                        }
                    }
                }

                // Categories from API
                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: category.categoryName,
                        icon: nil,
                        count: channelCount(for: category.categoryId),
                        isSelected: viewModel.selectedCategoryId == category.categoryId
                    ) {
                        hapticLight()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedCategoryId = category.categoryId
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
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
                LiveChannelCardView(displayModel: displayModel)
                    .matchedGeometryEffect(id: displayModel.id, in: animation)
                    .contextMenu {
                        channelContextMenu(for: displayModel)
                    }
                    .onTapGesture {
                        hapticLight()
                        handleDirectPlay(channel: displayModel.channel)
                    }
                    .onLongPressGesture {
                        hapticMedium()
                        selectedChannel = displayModel.channel
                        showDetailSheet = true
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
                ChannelListRow(
                    displayModel: displayModel,
                    categoryName: viewModel.categoryName(for: displayModel.channel.categoryId)
                )
                .matchedGeometryEffect(id: displayModel.id, in: animation)
                .contextMenu {
                    channelContextMenu(for: displayModel)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    favoriteSwipeAction(for: displayModel)
                }
                .swipeActions(edge: .leading) {
                    playSwipeAction(for: displayModel)
                }
                .onTapGesture {
                    hapticLight()
                    handleDirectPlay(channel: displayModel.channel)
                }

                Divider()
                    .padding(.leading, 72)
            }
        }
        .padding(.vertical, 8)
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
        logger.debug("Direct play for channel: \(channel.name)")
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
            // Primary: Live Segmenter pipeline (.ts → FFmpeg segment muxer → local HLS).
            // Lower latency (~2-4s less), enables future timeshift/DVR, single upstream connection.
            if let localURL = await startLiveSegmenterPipeline(channel: channel) {
                await presentPlayer(url: localURL, title: channel.name)
                return
            }

            // Fallback: LiveHLSProxy pipeline (.m3u8 → proxy upstream HLS → local serve).
            // Works when the server doesn't support .ts or the segmenter fails.
            logger.debug("Live segmenter unavailable, falling back to LiveHLSProxy")
            if let localURL = await startLiveHLSProxyPipeline(channel: channel) {
                await presentPlayer(url: localURL, title: channel.name)
                return
            }

            // Last resort: direct play without any proxy (may fail on AirPlay).
            logger.error("All live pipelines failed — falling back to direct URL")
            guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: urlString) else {
                logger.error("Failed to generate valid stream URL")
                return
            }
            await presentPlayer(url: url, title: channel.name)
        }
    }

    /// Start the live segmenter pipeline: FFmpeg segments the raw .ts stream into local HLS.
    private func startLiveSegmenterPipeline(channel: LiveChannel) async -> URL? {
        let tsURLString = IPTVConfiguration.buildLiveChannelTSURL(profile: profile, channelID: channel.streamId)
        guard let tsURL = URL(string: tsURLString) else { return nil }

        do {
            let liveSession = try await TransmuxingService.shared.startLiveTransmux(from: tsURL)
            let serverSession = try await TransmuxServer.shared.startLiveSegmented(
                directory: liveSession.outputDir,
                segmenter: liveSession.segmenter,
                handle: liveSession.handle
            )
            logger.debug("Live segmenter started: \(serverSession.localURL.absoluteString)")
            return serverSession.localURL
        } catch {
            logger.error("Live segmenter failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Start the LiveHLSProxy pipeline: proxy upstream .m3u8 through a local server.
    private func startLiveHLSProxyPipeline(channel: LiveChannel) async -> URL? {
        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlString) else { return nil }

        do {
            let session = try await TransmuxServer.shared.startLive(upstreamURL: url)
            logger.debug("Live proxy started: \(session.localURL.absoluteString)")
            return session.localURL
        } catch {
            logger.error("Live proxy failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Present the player on the appropriate platform.
    @MainActor
    private func presentPlayer(url: URL, title: String) {
        let player = PlayerFactory.shared.createPlayer(for: url)
        player.play()

        #if os(macOS)
        PlayerWindowManager.shared.present(player: player, title: title)
        openWindow(id: "player")
        #else
        activePlayer = player
        playerTitle = title
        showFullscreenPlayer = true
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

    private func channelCount(for categoryId: String?) -> Int {
        viewModel.liveChannels.filter { $0.categoryId == categoryId }.count
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

// MARK: - Category Chip

/// A styled chip button for category selection.
struct CategoryChip: View {
    let title: String
    let icon: String?
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 11, weight: .regular))
                        .opacity(0.7)
                }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Channel List Row

/// A list row for displaying a channel.
struct ChannelListRow: View {
    let displayModel: LiveChannelDisplayModel
    let categoryName: String

    var body: some View {
        HStack(spacing: 12) {
            // Channel Icon
            ChannelIconView(
                url: URL(string: displayModel.channel.streamIcon ?? ""),
                size: CGSize(width: 48, height: 48)
            )
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Channel Info
            VStack(alignment: .leading, spacing: 4) {
                Text(displayModel.channel.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Category
                    Text(categoryName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    // LIVE badge
                    LiveBadge(size: .compact)
                }
            }

            Spacer()

            // Favorite indicator
            if displayModel.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 14))
            }

            // Disclosure indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Live Channel Detail Sheet (Enhanced)

/// Enhanced detail sheet for live channel information.
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
                    // Channel Header
                    headerSection

                    // Quick Actions
                    quickActionsSection

                    // Channel Info
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
                    Button("Done") {
                        onClose()
                    }
                }
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Channel Icon
            if let iconURL = URL(string: channel.streamIcon ?? "") {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "tv")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    case .empty:
                        ProgressView()
                    @unknown default:
                        Image(systemName: "tv")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 100, height: 70)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // LIVE Badge
            LiveBadge(size: .regular)
        }
    }

    // MARK: - Quick Actions
    private var quickActionsSection: some View {
        HStack(spacing: 16) {
            // Play Button
            Button {
                onPlay()
                onClose()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                    Text("Play")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Favorite Button
            Button {
                onFavorite()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 20))
                    Text(isFavorite ? "Favorited" : "Favorite")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isFavorite ? Color.yellow.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundColor(isFavorite ? .yellow : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Info Section
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Category
            LabeledContent("Category", value: categoryName)

            // Stream ID
            LabeledContent("Stream ID", value: "\(channel.streamId)")

            // Added Date
            if let timestamp = Double(channel.added),
               timestamp > 0 {
                let date = Date(timeIntervalSince1970: timestamp)
                LabeledContent("Added", value: date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .padding()
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

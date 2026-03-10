//
//  LiveChannelListViewModel.swift
//  mks-multiplatform-iptv
//
//  Enhanced ViewModel for Live TV channels with EPG and favorites integration.
//  Uses SWR caching strategy and modern Swift concurrency.
//  Loads categories dynamically from the IPTV provider API.
//

import Foundation
import os
import SwiftUI

// MARK: - Channel Loading State

/// Represents the loading state of channels using enum for exhaustive handling.
enum ChannelLoadingState: Sendable, Equatable {
    case idle
    case loading
    case loaded(channelCount: Int)
    case failed(ChannelError)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var channels: Int? {
        if case .loaded(let count) = self { return count }
        return nil
    }

    var error: ChannelError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

// MARK: - Channel Error

/// Typed errors for channel operations.
enum ChannelError: LocalizedError, Sendable, Equatable {
    case networkUnavailable
    case invalidResponse
    case decodingFailed
    case serverError(statusCode: Int)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network connection unavailable"
        case .invalidResponse:
            return "Invalid server response"
        case .decodingFailed:
            return "Failed to decode channel data"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .unknown(let message):
            return message
        }
    }

    static func == (lhs: ChannelError, rhs: ChannelError) -> Bool {
        switch (lhs, rhs) {
        case (.networkUnavailable, .networkUnavailable),
             (.invalidResponse, .invalidResponse),
             (.decodingFailed, .decodingFailed):
            return true
        case (.serverError(let l), .serverError(let r)):
            return l == r
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Channel Sort Option

/// Sorting options for channel list.
enum ChannelSortOption: String, CaseIterable, Identifiable, Sendable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case addedNewest = "Recently Added"
    case addedOldest = "Oldest First"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nameAsc, .nameDesc: "textformat"
        case .addedNewest: "clock.arrow.circlepath"
        case .addedOldest: "clock.arrow.2.circlepath"
        }
    }

    func sort(_ channels: [LiveChannel]) -> [LiveChannel] {
        switch self {
        case .nameAsc:
            return channels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return channels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .addedNewest:
            return channels.sorted { parseAddedDate($0.added) > parseAddedDate($1.added) }
        case .addedOldest:
            return channels.sorted { parseAddedDate($0.added) < parseAddedDate($1.added) }
        }
    }

    private func parseAddedDate(_ added: String) -> TimeInterval {
        Double(added) ?? 0
    }
}

// MARK: - Live Channel List View Model

/// Manages live channel data with EPG integration, favorites support, and provides display models for UI rendering.
/// Loads categories dynamically from the IPTV provider API.
@MainActor
class LiveChannelListViewModel: ObservableObject {

    // MARK: - Dependencies

    let profile: IPTVProfile
    private let liveChannelService: MovieService
    private let cacheManager = CacheManager.shared
    private let favoritesManager = LiveChannelFavoritesManager.shared
    private let epgService = LiveChannelEPGService()
    private let logger = Logger(subsystem: "LiveChannelListViewModel", category: "LiveTV")

    // MARK: - Published State

    /// Current loading state
    @Published private(set) var loadingState: ChannelLoadingState = .idle

    /// Raw channel data from API
    @Published private(set) var liveChannels: [LiveChannel] = []

    /// Display models for UI rendering with EPG data
    @Published private(set) var displayModels: [LiveChannelDisplayModel] = []

    /// Categories loaded dynamically from IPTV provider API
    @Published private(set) var categories: [LiveChannelCategory] = []

    /// Category lookup dictionary for O(1) access
    private var categoryLookup: [String: LiveChannelCategory] = [:]

    /// Current sort option
    @Published var sortOption: ChannelSortOption = .addedNewest

    /// Selected category ID for filtering
    @Published var selectedCategoryId: String?

    /// Search text for filtering
    @Published var searchText: String = ""

    /// EPG state
    @Published private(set) var isEPGLoading = false
    @Published private(set) var isEPGAvailable = false
    @Published private(set) var epgError: ChannelError?

    // MARK: - Private State

    private var didLoadChannels = false
    private var didLoadEPG = false
    private var epgPreloadTask: Task<Void, Never>?

    // MARK: - Initialization

    init(profile: IPTVProfile, liveChannelService: MovieService? = nil) {
        self.profile = profile
        self.liveChannelService = liveChannelService ?? MovieService(profile: profile)
        self.logger.info("LiveChannelListViewModel initialized with profile: \(profile.name)")
    }

    deinit {
        epgPreloadTask?.cancel()
        self.logger.debug("LiveChannelListViewModel deallocated")
    }

    // MARK: - Computed Properties

    /// Filtered display models based on search text and selected category
    var filteredDisplayModels: [LiveChannelDisplayModel] {
        let sorted = sortOption.sort(liveChannels)

        var models = displayModels.filter { model in
            sorted.contains { $0.streamId == model.channel.streamId }
        }

        // Filter by search text
        if !searchText.isEmpty {
            models = models.filter { $0.channel.name.localizedCaseInsensitiveContains(searchText) }
        }

        // Filter by selected category
        if let categoryId = selectedCategoryId {
            if categoryId == "favorites" {
                models = models.filter { favoritesManager.isFavorite($0.id) }
            } else {
                models = models.filter { $0.channel.categoryId == categoryId }
            }
        }

        return models
    }

    /// Channels grouped by category for sidebar
    var channelsByCategory: [String: [LiveChannelDisplayModel]] {
        Dictionary(grouping: filteredDisplayModels) { $0.channel.categoryId ?? "uncategorized" }
    }

    /// Gets category name for a given category ID from the loaded categories
    func categoryName(for categoryId: String?) -> String {
        guard let id = categoryId else { return "Sin categoría" }
        return categoryLookup[id]?.categoryName ?? "Categoría \(id)"
    }

    // MARK: - Data Loading

    /// Loads both channels and categories from API using SWR caching strategy.
    func loadChannels() async {
        guard !didLoadChannels else {
            self.logger.debug("Channels already loaded, skipping")
            return
        }

        // SWR: try cache first
        if let cached = cacheManager.getCachedLiveChannelsSWR() {
            self.logger.info("Loaded \(cached.value.count) channels from cache (stale: \(cached.isStale))")

            liveChannels = sortOption.sort(cached.value)
            didLoadChannels = true

            // Update loading state - CRITICAL for UI to show content
            loadingState = .loaded(channelCount: cached.value.count)

            // Load categories from API (categories are small, always fresh)
            await loadCategories()

            if cached.isStale {
                Task.detached(priority: .background) { [weak self] in
                    await self?.refreshChannelsInBackground()
                }
            }
            return
        }

        // No cache: fetch from network
        await fetchAllData()
    }

    /// Forces a refresh of all data.
    func refreshChannels() async {
        self.logger.info("Refreshing channels and categories")
        didLoadChannels = false
        await fetchAllData()
    }

    private func fetchAllData() async {
        loadingState = .loading

        // Fetch channels (required) and categories (best-effort) independently
        // so a category API failure doesn't block channel loading.
        async let channelsResult: Result<[LiveChannel], Error> = {
            do { return .success(try await liveChannelService.fetchLiveChannels()) }
            catch { return .failure(error) }
        }()

        async let categoriesResult: Result<[LiveChannelCategory], Error> = {
            do { return .success(try await liveChannelService.fetchLiveChannelsCategories()) }
            catch { return .failure(error) }
        }()

        let (chResult, catResult) = await (channelsResult, categoriesResult)

        // Handle channels (critical path)
        switch chResult {
        case .success(let fetchedChannels):
            liveChannels = sortOption.sort(fetchedChannels)
            cacheManager.cacheLiveChannels(fetchedChannels)
            didLoadChannels = true
            loadingState = .loaded(channelCount: fetchedChannels.count)
            self.logger.info("Fetched \(fetchedChannels.count) channels")

        case .failure(let error):
            self.logger.error("Failed to load channels: \(error.localizedDescription)")
            loadingState = .failed(.unknown(error.localizedDescription))
            return
        }

        // Handle categories (best-effort)
        switch catResult {
        case .success(let fetchedCategories):
            applyCategories(fetchedCategories)
            cacheManager.cacheLiveChannelCategories(fetchedCategories)
            self.logger.info("Fetched \(fetchedCategories.count) categories")

        case .failure(let error):
            self.logger.warning("Categories API failed: \(error.localizedDescription)")
            // Try SWR cache, then derive from channels
            if let cached = cacheManager.getCachedLiveChannelCategoriesSWR() {
                applyCategories(cached.value)
                self.logger.info("Using \(cached.value.count) cached categories as fallback")
            } else {
                deriveCategoriresFromChannels()
            }
        }
    }

    /// Loads categories using SWR cache strategy with fallback derivation from channels.
    private func loadCategories() async {
        // SWR: try cache first
        if let cached = cacheManager.getCachedLiveChannelCategoriesSWR() {
            self.logger.info("Loaded \(cached.value.count) categories from cache (stale: \(cached.isStale))")
            applyCategories(cached.value)

            // If fresh, skip network fetch
            if !cached.isStale { return }
        }

        // Fetch from API
        do {
            let fetchedCategories = try await liveChannelService.fetchLiveChannelsCategories()
            applyCategories(fetchedCategories)
            cacheManager.cacheLiveChannelCategories(fetchedCategories)
            self.logger.debug("Fetched and cached \(fetchedCategories.count) categories from API")
        } catch {
            self.logger.warning("Failed to fetch categories from API: \(error.localizedDescription)")

            // Fallback: derive categories from loaded channels if we still have none
            if categories.isEmpty {
                deriveCategoriresFromChannels()
            }
        }
    }

    /// Applies a list of categories to the published state and lookup dictionary.
    private func applyCategories(_ fetchedCategories: [LiveChannelCategory]) {
        categories = fetchedCategories.sorted {
            $0.categoryName.localizedCaseInsensitiveCompare($1.categoryName) == .orderedAscending
        }
        categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryId, $0) })
    }

    /// Derives placeholder categories from the loaded channels when the API is unavailable.
    private func deriveCategoriresFromChannels() {
        let uniqueIds = Set(liveChannels.compactMap { $0.categoryId })
        guard !uniqueIds.isEmpty else { return }

        let derived = uniqueIds.map { id in
            LiveChannelCategory(categoryId: id, categoryName: "Category \(id)", parentId: 0)
        }
        applyCategories(derived)
        self.logger.info("Derived \(derived.count) placeholder categories from channel data")
    }

    private func refreshChannelsInBackground() async {
        self.logger.info("Background-refreshing live channels")

        do {
            let fetched = try await liveChannelService.fetchLiveChannels()
            liveChannels = sortOption.sort(fetched)
            cacheManager.cacheLiveChannels(fetched)
            self.logger.info("Background refresh: \(fetched.count) channels updated")

            // Also refresh categories
            await loadCategories()
        } catch {
            self.logger.error("Background refresh failed (non-fatal): \(error.localizedDescription)")
        }
    }

    // MARK: - EPG Integration

    /// Loads EPG data and builds match table for channels.
    func loadEPGAndBuildDisplayModels() async {
        guard !didLoadEPG else {
            self.logger.debug("EPG already loaded, skipping")
            return
        }

        self.logger.info("Loading EPG data for \(self.liveChannels.count) channels")
        isEPGLoading = true
        epgError = nil

        do {
            try await epgService.loadEPGAndBuildMatchTable(liveChannels: self.liveChannels)
            didLoadEPG = true
            isEPGAvailable = await epgService.isEPGAvailable
            self.logger.info("EPG loaded successfully")

            await buildDisplayModels()
            self.logger.info("Built \(self.displayModels.count) display models")

        } catch {
            self.logger.error("Failed to load EPG: \(error.localizedDescription)")
            epgError = .unknown(error.localizedDescription)
        }

        isEPGLoading = false
    }

    /// Preloads EPG for visible channels.
    func preloadEPG(for visibleStreamIds: Set<Int>) async {
        guard didLoadEPG else {
            self.logger.debug("EPG not loaded, skipping preload")
            return
        }

        self.logger.debug("Preloading EPG for \(visibleStreamIds.count) channels")
        epgPreloadTask?.cancel()

        let visibleChannels = Dictionary(
            uniqueKeysWithValues: liveChannels
                .filter { visibleStreamIds.contains($0.streamId) }
                .map { ($0.streamId, $0) }
        )

        epgPreloadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.epgService.preloadEPG(for: visibleChannels)
            await self.buildDisplayModels()
            self.logger.debug("EPG preload complete")
        }
    }

    private func buildDisplayModels() async {
        let favoriteIds = favoritesManager.favoriteIds
        let modelsDict = await epgService.buildDisplayModels(for: liveChannels, favoriteIds: favoriteIds)

        displayModels = Array(modelsDict.values)
            .sorted { $0.channel.name.localizedCaseInsensitiveCompare($1.channel.name) == .orderedAscending }
    }

    // MARK: - Favorites

    /// Toggles the favorite status of a channel.
    func toggleFavorite(_ streamId: Int) {
        favoritesManager.toggleFavorite(streamId)

        if let index = displayModels.firstIndex(where: { $0.id == streamId }) {
            displayModels[index].isFavorite.toggle()
        }
    }

    /// Checks if a channel is a favorite.
    func isFavorite(_ streamId: Int) -> Bool {
        favoritesManager.isFavorite(streamId)
    }

    // MARK: - Channel Lookup

    /// Gets a channel by stream ID.
    func channel(by streamId: Int) -> LiveChannel? {
        liveChannels.first { $0.streamId == streamId }
    }

    /// Gets a display model by stream ID.
    func displayModel(for streamId: Int) -> LiveChannelDisplayModel? {
        displayModels.first { $0.id == streamId }
    }
}

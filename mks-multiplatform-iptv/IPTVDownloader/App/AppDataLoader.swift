//
//  AppDataLoader.swift
//  mks-multiplatform-iptv
//
//  Handles initial data loading for the app
//  Extracted from ContentView for better separation of concerns
//

import SwiftUI
import IPTVCore

/// Loading status updates during app initialization
enum AppLoadingStatus: Equatable {
    case initializing
    case connecting
    case loadingMovies
    case loadingLiveTV
    case almostReady
    case error(String)

    var displayText: String {
        switch self {
        case .initializing: return "Initializing..."
        case .connecting: return "Connecting to server..."
        case .loadingMovies: return "Loading your movie library..."
        case .loadingLiveTV: return "Preparing live TV channels..."
        case .almostReady: return "Almost ready..."
        case .error(let message): return message
        }
    }
}

/// Manages initial app data loading
@MainActor
@Observable
final class AppDataLoader {
    // MARK: - Published State

    private(set) var isLoading = true
    private(set) var loadingStatus: AppLoadingStatus = .initializing

    // Loaded data
    private(set) var movieCategories: [MovieCategory] = []
    private(set) var seriesCategories: [SeriesCategory] = []
    private(set) var liveChannelCategories: [LiveChannelCategory] = []

    // ViewModels (created during initialization)
    private(set) var mediaViewModel: MediaListViewModel?
    private(set) var liveChannelViewModel: LiveChannelListViewModel?
    private(set) var movieService: MovieService?

    // EPG & Home
    private(set) var epgService: EPGService?
    private(set) var homeViewModel: HomeViewModel?

    // MARK: - Retry State

    private let cacheManager = CacheManager.shared
    private(set) var retryCount = 0
    private let maxRetries = 3

    /// Whether the loading status is an error
    var hasLoadingError: Bool {
        if case .error = loadingStatus { return true }
        return false
    }

    /// Whether any cached data was loaded (categories, media, or channels)
    var hasCachedData: Bool {
        !movieCategories.isEmpty || !seriesCategories.isEmpty || !liveChannelCategories.isEmpty
            || !(mediaViewModel?.movies.isEmpty ?? true)
            || !(mediaViewModel?.series.isEmpty ?? true)
            || !(liveChannelViewModel?.liveChannels.isEmpty ?? true)
    }

    // MARK: - Dependencies

    private let profile: IPTVProfile

    // MARK: - Initialization

    init(profile: IPTVProfile) {
        self.profile = profile
    }

    // MARK: - Public API

    /// Initialize ViewModels with the profile
    func initializeViewModels() {
        guard movieService == nil else { return }

        movieService = MovieService(profile: profile)
        mediaViewModel = MediaListViewModel(movieService: movieService!)
        liveChannelViewModel = LiveChannelListViewModel(profile: profile)

        let epg = EPGService()
        epgService = epg
        homeViewModel = HomeViewModel(epgService: epg)
    }

    /// Load all initial data with cache-first strategy and network retry fallback
    func loadAllData() async {
        initializeViewModels()

        guard movieService != nil else {
            loadingStatus = .error("Profile not available")
            isLoading = false
            return
        }

        // Phase 1: Try loading from cache
        let hasCache = loadCategoriesFromCache()

        if hasCache {
            // Cache hit: show cached content immediately
            MKSLog.app.info("[AppDataLoader] Cache hit — showing cached data immediately")

            loadingStatus = .loadingMovies
            await mediaViewModel?.loadMedia(contentType: .all)

            loadingStatus = .loadingLiveTV
            await liveChannelViewModel?.loadChannels()

            await assembleHomeSections()

            loadingStatus = .almostReady

            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }

            // Background: refresh stale data from network
            Task.detached { [weak self] in
                await self?.refreshAllInBackground()
            }
        } else {
            // No cache: load from network with retry
            MKSLog.app.info("[AppDataLoader] No cache — loading from network")
            await loadFromNetworkWithRetry()
        }

        // Non-blocking background tasks
        Task.detached { [weak self] in
            await self?.loadEPGInBackground()
        }
        Task.detached { [weak self] in
            await self?.homeViewModel?.prefetchMetadata()
        }
    }

    /// Public retry method for the UI retry button
    func retryLoading() async {
        retryCount = 0
        loadingStatus = .initializing
        isLoading = true
        await loadAllData()
    }

    // MARK: - Cache Loading

    /// Synchronously load categories from disk cache. Returns true if any cache was found.
    private func loadCategoriesFromCache() -> Bool {
        var foundCache = false

        if let cached = cacheManager.getCachedMovieCategoriesSWR() {
            movieCategories = cached.value
            foundCache = true
        }
        if let cached = cacheManager.getCachedSeriesCategoriesSWR() {
            seriesCategories = cached.value
            foundCache = true
        }
        if let cached = cacheManager.getCachedLiveChannelCategoriesSWR() {
            liveChannelCategories = cached.value
            foundCache = true
        }

        if foundCache {
            MKSLog.app.info("[AppDataLoader] Loaded categories from cache: \(movieCategories.count) movies, \(seriesCategories.count) series, \(liveChannelCategories.count) live channels")
        }

        return foundCache
    }

    // MARK: - Network Loading with Retry

    private func loadFromNetworkWithRetry() async {
        for attempt in 0...maxRetries {
            retryCount = attempt

            do {
                guard let movieService = movieService else { break }

                loadingStatus = .connecting

                async let movieCategoriesTask = movieService.fetchMovieCategories()
                async let seriesCategoriesTask = movieService.fetchSeriesCategories()
                async let liveChannelCategoriesTask = movieService.fetchLiveChannelsCategories()

                let (fetchedMovieCategories, fetchedSeriesCategories, fetchedLiveChannelCategories) =
                    try await (movieCategoriesTask, seriesCategoriesTask, liveChannelCategoriesTask)

                movieCategories = fetchedMovieCategories
                seriesCategories = fetchedSeriesCategories
                liveChannelCategories = fetchedLiveChannelCategories

                // Cache categories for next launch
                cacheManager.cacheMovieCategories(fetchedMovieCategories)
                cacheManager.cacheSeriesCategories(fetchedSeriesCategories)
                cacheManager.cacheLiveChannelCategories(fetchedLiveChannelCategories)

                MKSLog.app.info("[AppDataLoader] Categories loaded from network: \(movieCategories.count) movies, \(seriesCategories.count) series, \(liveChannelCategories.count) live channels")

                // Load media content
                loadingStatus = .loadingMovies
                await mediaViewModel?.loadMedia(contentType: .all)

                // Load live channels
                loadingStatus = .loadingLiveTV
                await liveChannelViewModel?.loadChannels()

                // Assemble Home sections
                await assembleHomeSections()

                loadingStatus = .almostReady
                try await Task.sleep(nanoseconds: 400_000_000)

                withAnimation(.easeOut(duration: 0.3)) {
                    isLoading = false
                }
                return // Success — exit retry loop

            } catch {
                MKSLog.app.error("[AppDataLoader] Network attempt \(attempt + 1)/\(maxRetries + 1) failed: \(error.localizedDescription)")

                if attempt < maxRetries {
                    // Exponential backoff: 2s, 4s, 8s
                    let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                    loadingStatus = .error("Connection failed. Retrying...")
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    // Final failure
                    MKSLog.app.error("[AppDataLoader] All \(maxRetries + 1) attempts failed")
                    loadingStatus = .error("Connection error. Please check your internet.")
                    isLoading = false
                }
            }
        }
    }

    // MARK: - Background Refresh

    /// Refresh all data in background (categories, media, channels). Failures are non-fatal.
    private func refreshAllInBackground() async {
        guard let movieService = movieService else { return }

        do {
            async let movieCategoriesTask = movieService.fetchMovieCategories()
            async let seriesCategoriesTask = movieService.fetchSeriesCategories()
            async let liveChannelCategoriesTask = movieService.fetchLiveChannelsCategories()

            let (freshMovieCats, freshSeriesCats, freshLiveCats) =
                try await (movieCategoriesTask, seriesCategoriesTask, liveChannelCategoriesTask)

            movieCategories = freshMovieCats
            seriesCategories = freshSeriesCats
            liveChannelCategories = freshLiveCats

            cacheManager.cacheMovieCategories(freshMovieCats)
            cacheManager.cacheSeriesCategories(freshSeriesCats)
            cacheManager.cacheLiveChannelCategories(freshLiveCats)

            // Re-assemble Home with fresh categories
            await assembleHomeSections()

            MKSLog.app.info("[AppDataLoader] Background refresh completed: categories updated")
        } catch {
            MKSLog.app.warning("[AppDataLoader] Background refresh failed (non-fatal): \(error.localizedDescription)")
        }
    }

    // MARK: - Background EPG Loading

    /// Loads EPG in background after Home is already visible, then inserts EPG sections with animation
    private func loadEPGInBackground() async {
        guard let epgService = epgService else { return }

        do {
            try await epgService.loadEPG()

            // Build match table with loaded live channels
            if let channels = liveChannelViewModel?.liveChannels {
                await epgService.buildMatchTable(liveChannels: channels)
            }

            let matchCount = await epgService.matchCount
            MKSLog.app.info("[AppDataLoader] EPG loaded in background. Matched channels: \(matchCount)")

            // Insert EPG sections into the already-visible Home screen
            await homeViewModel?.insertEPGSections()
        } catch {
            // Non-fatal: Home screen works without EPG, just hides EPG sections
            MKSLog.app.warning("[AppDataLoader] EPG background load failed (non-fatal): \(error.localizedDescription)")
        }
    }

    // MARK: - Home Assembly

    private func assembleHomeSections() async {
        guard let homeVM = homeViewModel else { return }

        let movies = mediaViewModel?.movies ?? []
        let series = mediaViewModel?.series ?? []
        let channels = liveChannelViewModel?.liveChannels ?? []

        await homeVM.assembleSections(
            movies: movies,
            series: series,
            liveChannels: channels,
            movieCategories: movieCategories,
            seriesCategories: seriesCategories,
            liveChannelCategories: liveChannelCategories
        )

        // Insert watch history sections (Continue Watching + Recent Channels)
        await homeVM.insertContinueWatchingSection(profileId: profile.id)
        await homeVM.insertRecentChannelsSection(profileId: profile.id)
    }
}

// MARK: - Preview Support

extension AppDataLoader {
    /// Creates a preview loader with mock data
    static func preview(profile: IPTVProfile) -> AppDataLoader {
        let loader = AppDataLoader(profile: profile)
        loader.isLoading = false
        return loader
    }
}

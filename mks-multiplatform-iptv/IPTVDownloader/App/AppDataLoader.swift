//
//  AppDataLoader.swift
//  mks-multiplatform-iptv
//
//  Handles initial data loading for the app
//  Extracted from ContentView for better separation of concerns
//

import SwiftUI

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

    /// Load all initial data (categories, media, channels, EPG, Home)
    func loadAllData() async {
        do {
            initializeViewModels()

            guard let movieService = movieService else {
                loadingStatus = .error("Profile not available")
                return
            }

            // Load categories in parallel
            loadingStatus = .connecting
            async let movieCategoriesTask = movieService.fetchMovieCategories()
            async let seriesCategoriesTask = movieService.fetchSeriesCategories()
            async let liveChannelCategoriesTask = movieService.fetchLiveChannelsCategories()

            let (fetchedMovieCategories, fetchedSeriesCategories, fetchedLiveChannelCategories) =
                try await (movieCategoriesTask, seriesCategoriesTask, liveChannelCategoriesTask)

            movieCategories = fetchedMovieCategories
            seriesCategories = fetchedSeriesCategories
            liveChannelCategories = fetchedLiveChannelCategories

            print("[AppDataLoader] Categories loaded: \(movieCategories.count) movies, \(seriesCategories.count) series, \(liveChannelCategories.count) live channels")

            // Load media content
            loadingStatus = .loadingMovies
            await mediaViewModel?.loadMedia(contentType: .all)

            // Load live channels
            loadingStatus = .loadingLiveTV
            await liveChannelViewModel?.loadChannels()

            // Assemble Home sections immediately (without EPG)
            await assembleHomeSections()

            // Brief delay for smooth transition
            loadingStatus = .almostReady
            try await Task.sleep(nanoseconds: 400_000_000)

            // Complete loading — Home is visible now
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }

            // Fire EPG load in the background (non-blocking)
            Task.detached { [weak self] in
                await self?.loadEPGInBackground()
            }

            // Prefetch enriched metadata for Home-visible items (non-blocking)
            Task.detached { [weak self] in
                await self?.homeViewModel?.prefetchMetadata()
            }

        } catch {
            print("[AppDataLoader] Error loading data: \(error.localizedDescription)")
            loadingStatus = .error("Connection error. Please check your internet.")
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
            print("[AppDataLoader] EPG loaded in background. Matched channels: \(matchCount)")

            // Insert EPG sections into the already-visible Home screen
            await homeViewModel?.insertEPGSections()
        } catch {
            // Non-fatal: Home screen works without EPG, just hides EPG sections
            print("[AppDataLoader] EPG background load failed (non-fatal): \(error.localizedDescription)")
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

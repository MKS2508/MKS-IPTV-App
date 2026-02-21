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
    }

    /// Load all initial data (categories, media, channels)
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

            // Brief delay for smooth transition
            loadingStatus = .almostReady
            try await Task.sleep(nanoseconds: 800_000_000)

            // Complete loading
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }

        } catch {
            print("[AppDataLoader] Error loading data: \(error.localizedDescription)")
            loadingStatus = .error("Connection error. Please check your internet.")
        }
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

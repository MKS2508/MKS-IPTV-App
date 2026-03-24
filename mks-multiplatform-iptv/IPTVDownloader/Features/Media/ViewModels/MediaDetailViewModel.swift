//
//  MediaDetailViewModel.swift
//  mks-multiplatform-iptv
//
//  Unified ViewModel for Movie and Serie details
//  Consolidates MovieDetailViewModel + SerieDetailViewModel into one generic implementation
//

import Foundation

// MARK: - Media Detail Type

/// Represents the type of media detail being loaded
enum MediaDetailType {
    case movie(id: Int)
    case serie(id: Int)

    var id: Int {
        switch self {
        case .movie(let id), .serie(let id):
            return id
        }
    }
}

// MARK: - Media Detail ViewModel

/// Unified ViewModel for loading and caching media details (movies and series)
/// Uses @Observable for automatic SwiftUI integration (iOS 17+, macOS 14+)
@MainActor
@Observable
final class MediaDetailViewModel {
    // MARK: - State

    /// The loaded movie detail (nil if loading serie or not loaded)
    var movieDetail: MovieDetail?

    /// The loaded serie detail (nil if loading movie or not loaded)
    var serieDetail: SerieDetail?

    /// Preview data from grid (available immediately while loading full detail)
    var moviePreview: Movie?
    var seriePreview: Serie?

    /// Loading state
    var isLoading = false

    /// Error state
    var error: Error?

    /// Whether currently refreshing
    var isRefreshing = false

    /// Whether data was loaded from cache
    var loadedFromCache = false

    /// Whether we have full detail loaded (vs just preview)
    var hasFullDetail: Bool {
        movieDetail != nil || serieDetail != nil
    }

    // MARK: - Private Properties

    private let movieService: MovieService
    private let cacheManager = CacheManager.shared
    private var currentType: MediaDetailType?

    // MARK: - Initialization

    init(movieService: MovieService) {
        self.movieService = movieService
    }

    // MARK: - Public API

    /// Set preview from grid (shows immediately while loading full detail)
    func setMoviePreview(_ movie: Movie) {
        self.moviePreview = movie
        self.seriePreview = nil
        self.currentType = .movie(id: movie.streamId)
    }

    /// Set preview from grid (shows immediately while loading full detail)
    func setSeriePreview(_ serie: Serie) {
        self.seriePreview = serie
        self.moviePreview = nil
        self.currentType = .serie(id: serie.seriesId)
    }

    /// Fetch details for a movie (with optional preview for immediate display)
    func fetchMovieDetails(for movieId: Int, preview: Movie? = nil, forceRefresh: Bool = false) async {
        if let preview = preview {
            setMoviePreview(preview)
        }
        currentType = .movie(id: movieId)
        await fetchDetails(forceRefresh: forceRefresh)
    }

    /// Fetch details for a serie (with optional preview for immediate display)
    func fetchSerieDetails(for serieId: Int, preview: Serie? = nil, forceRefresh: Bool = false) async {
        if let preview = preview {
            setSeriePreview(preview)
        }
        currentType = .serie(id: serieId)
        await fetchDetails(forceRefresh: forceRefresh)
    }

    /// Refresh current detail
    func refresh() async {
        await fetchDetails(forceRefresh: true)
    }

    /// Reset all state
    func reset() {
        movieDetail = nil
        serieDetail = nil
        error = nil
        isLoading = false
        isRefreshing = false
        loadedFromCache = false
        currentType = nil
    }

    /// Soft reset: clears error/loading state but preserves loaded detail data.
    /// Reopening the same item is instant since movieDetail/serieDetail are retained.
    func softReset() {
        error = nil
        isLoading = false
        isRefreshing = false
    }

    /// Set movie detail directly (when provided externally)
    func setMovieDetail(_ detail: MovieDetail) {
        self.movieDetail = detail
        self.serieDetail = nil
        self.loadedFromCache = false
        self.isLoading = false
        self.error = nil
        self.currentType = .movie(id: detail.movieData.streamId)

        cacheManager.cacheMovieDetail(detail, id: detail.movieData.streamId)
    }

    /// Set serie detail directly (when provided externally)
    func setSerieDetail(_ detail: SerieDetail, seriesId: Int) {
        var d = detail
        d.seriesId = seriesId
        self.serieDetail = d
        self.movieDetail = nil
        self.loadedFromCache = false
        self.isLoading = false
        self.error = nil
        self.currentType = .serie(id: seriesId)

        cacheManager.cacheSerieDetail(detail, id: seriesId)
    }

    // MARK: - Private Implementation

    private func fetchDetails(forceRefresh: Bool = false) async {
        guard let type = currentType else { return }

        error = nil

        // SWR: try cache first with staleness info
        if !forceRefresh, let cached = loadFromCacheSWR(for: type) {
            loadedFromCache = true

            // Only background-refresh when stale, not on every cache hit
            if cached.isStale {
                Task { await refreshInBackground(type: type) }
            }
            return
        }

        // Load from network
        isLoading = !forceRefresh
        isRefreshing = forceRefresh
        loadedFromCache = false

        do {
            switch type {
            case .movie(let id):
                let detail = try await movieService.fetchMovieDetails(vodId: id)
                movieDetail = detail
                serieDetail = nil
                cacheManager.cacheMovieDetail(detail, id: id)

            case .serie(let id):
                var detail = try await movieService.fetchSeriesDetails(seriesId: id)
                detail.seriesId = id
                serieDetail = detail
                movieDetail = nil
                cacheManager.cacheSerieDetail(detail, id: id)
            }
        } catch {
            self.error = error
            MKSLog.media.error("[MediaDetailVM] Error fetching details: \(error)")
        }

        isLoading = false
        isRefreshing = false
    }

    /// SWR cache lookup: returns CacheResult with staleness info, or nil if miss/expired.
    private func loadFromCacheSWR(for type: MediaDetailType) -> CacheResult<Bool>? {
        switch type {
        case .movie(let id):
            if let cached = cacheManager.getCachedMovieDetailSWR(id: id) {
                movieDetail = cached.value
                serieDetail = nil
                return CacheResult(value: true, age: cached.age, isStale: cached.isStale, key: cached.key)
            }
        case .serie(let id):
            if let cached = cacheManager.getCachedSerieDetailSWR(id: id) {
                serieDetail = cached.value
                movieDetail = nil
                return CacheResult(value: true, age: cached.age, isStale: cached.isStale, key: cached.key)
            }
        }
        return nil
    }

    private func refreshInBackground(type: MediaDetailType) async {
        do {
            switch type {
            case .movie(let id):
                let detail = try await movieService.fetchMovieDetails(vodId: id)
                cacheManager.cacheMovieDetail(detail, id: id)

                // Update UI if still showing same movie
                if movieDetail?.movieData.streamId == id {
                    movieDetail = detail
                }

            case .serie(let id):
                var detail = try await movieService.fetchSeriesDetails(seriesId: id)
                detail.seriesId = id
                cacheManager.cacheSerieDetail(detail, id: id)

                // Update UI if still showing same serie
                if serieDetail?.seasons.first?.id == detail.seasons.first?.id {
                    serieDetail = detail
                }
            }
        } catch {
            MKSLog.media.error("[MediaDetailViewModel] Background refresh failed: \(error)")
        }
    }
}

// MARK: - Convenience Initializers

extension MediaDetailViewModel {
    /// Create a ViewModel pre-loaded with movie detail
    static func with(movieDetail: MovieDetail, movieService: MovieService) -> MediaDetailViewModel {
        let vm = MediaDetailViewModel(movieService: movieService)
        vm.setMovieDetail(movieDetail)
        return vm
    }

    /// Create a ViewModel pre-loaded with serie detail
    static func with(serieDetail: SerieDetail, seriesId: Int, movieService: MovieService) -> MediaDetailViewModel {
        let vm = MediaDetailViewModel(movieService: movieService)
        vm.setSerieDetail(serieDetail, seriesId: seriesId)
        return vm
    }
}

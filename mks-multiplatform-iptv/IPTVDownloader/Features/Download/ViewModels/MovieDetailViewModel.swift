import Foundation
import SwiftUI

@MainActor
class MovieDetailViewModel: ObservableObject {
    @Published var movieDetail: MovieDetail?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isRefreshing = false
    @Published var loadedFromCache = false
    @Published var enrichedMetadata: MetadataResult?
    @Published var metadataCandidates: [ScoredMetadataResult] = []
    @Published var isEnrichingMetadata = false

    private let movieService: MovieService
    private let cacheManager = CacheManager.shared
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }

    func fetchMovieDetails(for movieId: Int, forceRefresh: Bool = false) async {
        self.error = nil

        // SWR: try cache with staleness info
        if !forceRefresh, let cached = cacheManager.getCachedMovieDetailSWR(id: movieId) {
            self.movieDetail = cached.value
            self.loadedFromCache = true
            self.isLoading = false

            if cached.value.tmdbId > 0 && enrichedMetadata == nil {
                Task { await self.enrichMetadata() }
            }

            // Only background-refresh when stale
            if cached.isStale {
                Task { await refreshInBackground(movieId: movieId) }
            }
            return
        }

        // Load from network
        isLoading = !forceRefresh
        isRefreshing = forceRefresh
        loadedFromCache = false

        do {
            let detail = try await movieService.fetchMovieDetails(vodId: movieId)
            self.movieDetail = detail
            self.error = nil
            cacheManager.cacheMovieDetail(detail, id: movieId)

            if detail.tmdbId > 0 {
                Task { await self.enrichMetadata() }
            }
        } catch {
            self.error = error
            self.movieDetail = nil
            print("[MovieDetailVM] Error fetching details: \(error)")
        }

        isLoading = false
        isRefreshing = false
    }
    
    private func refreshInBackground(movieId: Int) async {
        do {
            let detail = try await movieService.fetchMovieDetails(vodId: movieId)
            cacheManager.cacheMovieDetail(detail, id: movieId)

            if self.movieDetail?.movieData.streamId == movieId {
                self.movieDetail = detail
            }
        } catch {
            print("[MovieDetailVM] Background refresh failed: \(error)")
        }
    }
    
    func refresh(movieId: Int) async {
        await fetchMovieDetails(for: movieId, forceRefresh: true)
    }
    
    func reset() {
        movieDetail = nil
        error = nil
        isLoading = false
        isRefreshing = false
        loadedFromCache = false
    }
    
    /// Fetch all metadata candidates from external providers (TMDB, iTunes, TheTVDB).
    ///
    /// Auto-selects the best match. All candidates are stored for user selection.
    /// Called automatically when movie details contain a tmdbId.
    func enrichMetadata() async {
        guard let detail = movieDetail else { return }
        guard !isEnrichingMetadata else { return }
        isEnrichingMetadata = true

        let query = MetadataSearchQuery(
            title: detail.movieData.name,
            year: StringSimilarity.extractYear(from: detail.movieData.name),
            tmdbId: detail.tmdbId,
            genre: detail.genre,
            runtimeMinutes: detail.durationSecs / 60,
            mediaType: .movie
        )
        let candidates = await MetadataEnrichmentService.shared.fetchAllCandidates(query: query)
        self.metadataCandidates = candidates
        self.enrichedMetadata = candidates.first?.result
        isEnrichingMetadata = false
    }

    /// Update the selected metadata (user picked a different candidate or edited).
    func selectMetadata(_ metadata: MetadataResult) {
        self.enrichedMetadata = metadata
    }

    func setMovieDetail(_ detail: MovieDetail) {
        self.movieDetail = detail
        self.loadedFromCache = false
        self.isLoading = false
        self.error = nil

        cacheManager.cacheMovieDetail(detail, id: detail.movieData.streamId)

        if detail.tmdbId > 0 {
            Task { await self.enrichMetadata() }
        }
    }
}

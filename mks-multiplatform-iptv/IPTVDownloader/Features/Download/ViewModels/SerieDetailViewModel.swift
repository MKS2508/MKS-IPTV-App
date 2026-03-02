import Foundation
import SwiftUI

@MainActor
class SerieDetailViewModel: ObservableObject {
    @Published var serieDetail: SerieDetail?
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

    func fetchSerieDetails(for seriesId: Int, forceRefresh: Bool = false) async {
        self.error = nil

        // SWR: try cache with staleness info
        if !forceRefresh, let cached = cacheManager.getCachedSerieDetailSWR(id: seriesId) {
            var detail = cached.value
            detail.seriesId = seriesId
            self.serieDetail = detail
            self.loadedFromCache = true

            if enrichedMetadata == nil {
                Task { await self.enrichMetadata() }
            }

            // Only background-refresh when stale
            if cached.isStale {
                Task { await refreshInBackground(seriesId: seriesId) }
            }
            return
        }

        // Load from network
        isLoading = !forceRefresh
        isRefreshing = forceRefresh
        loadedFromCache = false

        do {
            var detail = try await movieService.fetchSeriesDetails(seriesId: seriesId)
            detail.seriesId = seriesId
            self.serieDetail = detail
            self.error = nil
            cacheManager.cacheSerieDetail(detail, id: seriesId)

            Task { await self.enrichMetadata() }
        } catch {
            self.error = error
            self.serieDetail = nil
            print("[SerieDetailVM] Error fetching details: \(error)")
        }

        isLoading = false
        isRefreshing = false
    }

    private func refreshInBackground(seriesId: Int) async {
        do {
            var detail = try await movieService.fetchSeriesDetails(seriesId: seriesId)
            detail.seriesId = seriesId
            cacheManager.cacheSerieDetail(detail, id: seriesId)

            if let currentDetail = self.serieDetail,
               currentDetail.seasons.first?.id == detail.seasons.first?.id {
                self.serieDetail = detail
            }
        } catch {
            print("[SerieDetailVM] Background refresh failed: \(error)")
        }
    }

    func refresh(seriesId: Int) async {
        await fetchSerieDetails(for: seriesId, forceRefresh: true)
    }

    func reset() {
        serieDetail = nil
        error = nil
        isLoading = false
        isRefreshing = false
        loadedFromCache = false
    }

    /// Fetch all metadata candidates from external providers (TMDB, iTunes, TheTVDB).
    ///
    /// Auto-selects the best match. All candidates are stored for user selection.
    /// Called automatically when series details are loaded.
    func enrichMetadata() async {
        guard let detail = serieDetail else { return }
        guard !isEnrichingMetadata else { return }
        isEnrichingMetadata = true

        let query = MetadataSearchQuery(
            title: detail.info.name,
            year: StringSimilarity.extractYear(from: detail.info.releaseDate),
            genre: detail.info.genre,
            runtimeMinutes: Int(detail.info.episodeRunTime) ?? 0,
            mediaType: .series
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

    // For when SerieDetail is provided directly
    func setSerieDetail(_ detail: SerieDetail, seriesId: Int) {
        var d = detail
        d.seriesId = seriesId
        self.serieDetail = d
        self.loadedFromCache = false

        // Cache it
        cacheManager.cacheSerieDetail(detail, id: seriesId)

        // Auto-enrich metadata
        Task { await self.enrichMetadata() }
    }
}

import Foundation
import SwiftUI

@MainActor
class SerieDetailViewModel: ObservableObject {
    @Published var serieDetail: SerieDetail?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isRefreshing = false
    @Published var loadedFromCache = false

    private let movieService: MovieService
    private let cacheManager = CacheManager.shared
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }

    func fetchSerieDetails(for seriesId: Int, forceRefresh: Bool = false) async {
        // Reset error state
        self.error = nil
        
        // Try to load from cache first if not forcing refresh
        if !forceRefresh, let cachedDetail = cacheManager.getCachedSerieDetail(id: seriesId) {
            self.serieDetail = cachedDetail
            self.loadedFromCache = true
            
            // Refresh in background if cache is older than 30 minutes
            if let cacheAge = cacheManager.getCacheAge(serieId: seriesId), cacheAge > 1800 {
                Task {
                    await refreshInBackground(seriesId: seriesId)
                }
            }
            return
        }
        
        // Load from network
        await MainActor.run {
            isLoading = !forceRefresh
            isRefreshing = forceRefresh
            loadedFromCache = false
        }
        
        do {
            let detail = try await movieService.fetchSeriesDetails(seriesId: seriesId)
            self.serieDetail = detail
            self.error = nil
            
            // Cache the result
            cacheManager.cacheSerieDetail(detail, id: seriesId)
        } catch {
            self.error = error
            self.serieDetail = nil
            print("Error fetching series details: \(error)")
        }
        
        isLoading = false
        isRefreshing = false
    }
    
    private func refreshInBackground(seriesId: Int) async {
        do {
            let detail = try await movieService.fetchSeriesDetails(seriesId: seriesId)
            
            // Update cache
            cacheManager.cacheSerieDetail(detail, id: seriesId)
            
            // Update UI if it's still showing the same series
            // Check if any season/episode info matches to confirm it's the same series
            if let currentDetail = self.serieDetail,
               currentDetail.seasons.first?.id == detail.seasons.first?.id {
                self.serieDetail = detail
            }
        } catch {
            // Silent failure for background refresh
            print("Background refresh failed: \(error)")
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
    
    // For when SerieDetail is provided directly
    func setSerieDetail(_ detail: SerieDetail, seriesId: Int) {
        self.serieDetail = detail
        self.loadedFromCache = false
        
        // Cache it
        cacheManager.cacheSerieDetail(detail, id: seriesId)
    }
}

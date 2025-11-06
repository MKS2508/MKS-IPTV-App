import Foundation
import SwiftUI

@MainActor
class MovieDetailViewModel: ObservableObject {
    @Published var movieDetail: MovieDetail?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isRefreshing = false
    @Published var loadedFromCache = false

    private let movieService: MovieService
    private let cacheManager = CacheManager.shared
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }

    func fetchMovieDetails(for movieId: Int, forceRefresh: Bool = false) async {
        print("🔄 Iniciando fetchMovieDetails para movieId: \(movieId), forceRefresh: \(forceRefresh)")
        print("   - Estado inicial: isLoading=\(isLoading), error=\(error?.localizedDescription ?? "nil")")
        
        // Reset error state
        self.error = nil
        
        // Try to load from cache first if not forcing refresh
        if !forceRefresh, let cachedDetail = cacheManager.getCachedMovieDetail(id: movieId) {
            print("🎯 Cargando desde cache para movieId: \(movieId)")
            self.movieDetail = cachedDetail
            self.loadedFromCache = true
            self.isLoading = false
            
            print("   - Estado después de cache: isLoading=\(isLoading), movieDetail=\(movieDetail?.movieData.name ?? "nil")")
            
            // Refresh in background if cache is older than 30 minutes
            if let cacheAge = cacheManager.getCacheAge(movieId: movieId), cacheAge > 1800 {
                Task {
                    await refreshInBackground(movieId: movieId)
                }
            }
            return
        }
        
        // Load from network
        print("🌐 Cargando desde red para movieId: \(movieId)")
        isLoading = !forceRefresh
        isRefreshing = forceRefresh
        loadedFromCache = false
        
        print("   - Estado durante carga: isLoading=\(isLoading)")
        
        do {
            let detail = try await movieService.fetchMovieDetails(vodId: movieId)
            print("✅ Datos recibidos del API para movieId: \(movieId)")
            self.movieDetail = detail
            self.error = nil
            
            print("   - Estado después de éxito: isLoading=\(isLoading), movieDetail=\(movieDetail?.movieData.name ?? "nil")")
            
            // Cache the result
            cacheManager.cacheMovieDetail(detail, id: movieId)
        } catch {
            print("❌ Error fetching movie details: \(error)")
            self.error = error
            self.movieDetail = nil
            
            print("   - Estado después de error: isLoading=\(isLoading), error=\(error.localizedDescription)")
        }
        
        isLoading = false
        isRefreshing = false
        print("   - Estado final: isLoading=\(isLoading), isRefreshing=\(isRefreshing)")
    }
    
    private func refreshInBackground(movieId: Int) async {
        do {
            let detail = try await movieService.fetchMovieDetails(vodId: movieId)
            
            // Update cache
            cacheManager.cacheMovieDetail(detail, id: movieId)
            
            // Update UI if it's still showing the same movie
            if self.movieDetail?.movieData.streamId == movieId {
                self.movieDetail = detail
            }
        } catch {
            // Silent failure for background refresh
            print("Background refresh failed: \(error)")
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
    
    // For when MovieDetail is provided directly
    func setMovieDetail(_ detail: MovieDetail) {
        print("📋 Asignando MovieDetail directamente: \(detail.movieData.name)")
        print("   - Estado anterior: isLoading=\(isLoading), movieDetail=\(movieDetail?.movieData.name ?? "nil")")
        
        self.movieDetail = detail
        self.loadedFromCache = false
        self.isLoading = false
        self.error = nil
        
        print("   - Estado nuevo: isLoading=\(isLoading), movieDetail=\(movieDetail?.movieData.name ?? "nil")")
        
        // Cache it
        cacheManager.cacheMovieDetail(detail, id: detail.movieData.streamId)
    }
}

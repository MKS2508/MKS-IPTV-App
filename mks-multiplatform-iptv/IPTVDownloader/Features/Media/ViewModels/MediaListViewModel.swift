import Foundation
import IPTVCore

// MediaLibraryItem, MediaType, and TitleParseable protocols are defined in MediaProtocols.swift
// Movie and Serie conformances are also in MediaProtocols.swift

@MainActor
class MediaListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var series: [Serie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var isRefreshing = false
    @Published private(set) var loadedFromCache = false
    
    // MARK: - Private Properties
    
    private var didLoadMovies = false
    private var didLoadSeries = false
    private let movieService: MovieService
    private let cacheManager = CacheManager.shared
    
    // MARK: - Public Types

    enum ContentType: CaseIterable, Identifiable {
        case all
        case movies
        case series

        var id: String { title }

        /// Display title for the content type
        var title: String {
            switch self {
            case .all: return "All"
            case .movies: return "Movies"
            case .series: return "Series"
            }
        }

        /// SF Symbol name for the content type
        var systemImage: String {
            switch self {
            case .all: return "play.rectangle.on.rectangle.fill"
            case .movies: return "film.fill"
            case .series: return "tv.fill"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case nameAsc = "Name A-Z"
        case nameDesc = "Name Z-A"
        case addedAsc = "Oldest First"
        case addedDesc = "Newest First"
    }
    
    // MARK: - Initialization
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }
    
    // MARK: - Public Methods
    
    func loadMedia(contentType: ContentType = .all, categoryId: String? = nil, forceRefresh: Bool = false) async {
        // Skip if already loaded and not forcing refresh
        if !forceRefresh {
            if contentType == .movies && didLoadMovies { return }
            if contentType == .series && didLoadSeries { return }
            if contentType == .all && didLoadMovies && didLoadSeries { return }
        }

        isLoading = !forceRefresh
        isRefreshing = forceRefresh
        error = nil
        loadedFromCache = false

        do {
            if contentType == .movies || contentType == .all {
                // SWR: Try cache first with staleness info
                if !forceRefresh,
                   let cached = cacheManager.getCachedMoviesSWR(categoryId: categoryId) {
                    movies = orderByAddedDesc(cached.value)
                    didLoadMovies = true
                    loadedFromCache = true

                    // Only background-refresh when stale (> 30min), not on every cache hit
                    if cached.isStale {
                        Task { await refreshMoviesInBackground(categoryId: categoryId) }
                    }
                } else {
                    let freshMovies = try await movieService.fetchMovies()
                    movies = orderByAddedDesc(freshMovies)
                    didLoadMovies = true
                    cacheManager.cacheMovies(freshMovies, categoryId: categoryId)
                }
            }

            if contentType == .series || contentType == .all {
                if !forceRefresh,
                   let cached = cacheManager.getCachedSeriesSWR(categoryId: categoryId) {
                    series = orderByAddedDesc(cached.value)
                    didLoadSeries = true
                    loadedFromCache = true

                    if cached.isStale {
                        Task { await refreshSeriesInBackground(categoryId: categoryId) }
                    }
                } else {
                    let freshSeries = try await movieService.fetchSeries()
                    series = orderByAddedDesc(freshSeries)
                    didLoadSeries = true
                    cacheManager.cacheSeries(freshSeries, categoryId: categoryId)
                }
            }
        } catch {
            self.error = error
        }

        isLoading = false
        isRefreshing = false
    }

    private func refreshMoviesInBackground(categoryId: String?) async {
        do {
            let freshMovies = try await movieService.fetchMovies()
            cacheManager.cacheMovies(freshMovies, categoryId: categoryId)

            if didLoadMovies {
                movies = orderByAddedDesc(freshMovies)
            }
        } catch {
            MKSLog.media.error("[MediaListVM] Background movie refresh failed: \(error)")
        }
    }

    private func refreshSeriesInBackground(categoryId: String?) async {
        do {
            let freshSeries = try await movieService.fetchSeries()
            cacheManager.cacheSeries(freshSeries, categoryId: categoryId)

            if didLoadSeries {
                series = orderByAddedDesc(freshSeries)
            }
        } catch {
            MKSLog.media.error("[MediaListVM] Background series refresh failed: \(error)")
        }
    }
    
    func refreshMedia(contentType: ContentType = .all, categoryId: String? = nil) async {
        await loadMedia(contentType: contentType, categoryId: categoryId, forceRefresh: true)
    }
    
    // MARK: - Content Access & Filtering
    
    func getMediaLibraryItems(type: ContentType = .all) -> [any MediaLibraryItem] {
        switch type {
        case .all:
            // Combine both arrays as MediaLibraryItems
            let movieItems = movies.map { $0 as any MediaLibraryItem }
            let seriesItems = series.map { $0 as any MediaLibraryItem }
            return movieItems + seriesItems
        case .movies:
            return movies.map { $0 as any MediaLibraryItem }
        case .series:
            return series.map { $0 as any MediaLibraryItem }
        }
    }
    
    func filterMovies(searchText: String, categoryIds: Set<String> = []) -> [Movie] {
        guard !movies.isEmpty else { return [] }
        
        return movies.filter { movie in
            let matchesSearch = searchText.isEmpty || movie.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = categoryIds.isEmpty || categoryIds.contains(movie.categoryId)
            return matchesSearch && matchesCategory
        }
    }
    
    func filterSeries(searchText: String, categoryIds: Set<String> = []) -> [Serie] {
        guard !series.isEmpty else { return [] }
        
        return series.filter { serie in
            let matchesSearch = searchText.isEmpty || serie.name.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = categoryIds.isEmpty || categoryIds.contains(serie.categoryId)
            return matchesSearch && matchesCategory
        }
    }
    
    // MARK: - Sorting Methods for Movies
    
    func orderByNameAlphabeticallyAsc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func orderByNameAlphabeticallyDesc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted { $0.name.lowercased() > $1.name.lowercased() }
    }
    
    func orderByAddedAsc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted {
            guard let date1 = Double($0.added ?? "0"), let date2 = Double($1.added ?? "0") else {
                return false
            }
            return date1 < date2
        }
    }
    
    func orderByAddedDesc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted {
            guard let date1 = Double($0.added ?? "0"), let date2 = Double($1.added ?? "0") else {
                return false
            }
            return date1 > date2
        }
    }
    
    // MARK: - Sorting Methods for Series
    
    func orderByNameAlphabeticallyAsc(_ series: [Serie]) -> [Serie] {
        return series.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func orderByNameAlphabeticallyDesc(_ series: [Serie]) -> [Serie] {
        return series.sorted { $0.name.lowercased() > $1.name.lowercased() }
    }
    
    func orderByAddedAsc(_ series: [Serie]) -> [Serie] {
        return series.sorted { (s1: Serie, s2: Serie) -> Bool in
            guard let date1 = Double(s1.lastModified), let date2 = Double(s2.lastModified) else {
                return false
            }
            return date1 < date2
        }
    }
    
    func orderByAddedDesc(_ series: [Serie]) -> [Serie] {
        return series.sorted { (s1: Serie, s2: Serie) -> Bool in
            guard let date1 = Double(s1.lastModified), let date2 = Double(s2.lastModified) else {
                return false
            }
            return date1 > date2
        }
    }
    
    // MARK: - Generic Sorting Application
    
    func applySortToMovies(_ sortOption: SortOption) {
        switch sortOption {
        case .nameAsc:
            movies = orderByNameAlphabeticallyAsc(movies)
        case .nameDesc:
            movies = orderByNameAlphabeticallyDesc(movies)
        case .addedAsc:
            movies = orderByAddedAsc(movies)
        case .addedDesc:
            movies = orderByAddedDesc(movies)
        }
    }
    
    func applySortToSeries(_ sortOption: SortOption) {
        switch sortOption {
        case .nameAsc:
            series = orderByNameAlphabeticallyAsc(series)
        case .nameDesc:
            series = orderByNameAlphabeticallyDesc(series)
        case .addedAsc:
            series = orderByAddedAsc(series)
        case .addedDesc:
            series = orderByAddedDesc(series)
        }
    }
    
    func applySort(_ sortOption: SortOption, to contentType: ContentType = .all) {
        if contentType == .all || contentType == .movies {
            applySortToMovies(sortOption)
        }
        
        if contentType == .all || contentType == .series {
            applySortToSeries(sortOption)
        }
    }
    
    // MARK: - Testing & Debug Methods
    
    func loadExampleMovies(_ movies: [Movie]) {
        self.movies = movies
        didLoadMovies = true
    }
    
    func loadExampleSeries(_ series: [Serie]) {
        self.series = series
        didLoadSeries = true
    }
    
    // MARK: - Media Item Lookup
    
    func getMovie(by id: Int) -> Movie? {
        return movies.first { $0.streamId == id }
    }
    
    func getSerie(by id: Int) -> Serie? {
        return series.first { $0.seriesId == id }
    }
}

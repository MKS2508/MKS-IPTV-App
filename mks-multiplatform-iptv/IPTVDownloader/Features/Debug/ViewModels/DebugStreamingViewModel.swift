import Foundation
import Combine
import AVKit

// MARK: - Models

struct DebugStreamItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let type: MediaType
    let fileExtension: String
    let added: String
    let categoryId: String
    let rating: Double?
    
    var streamURL: String?
    var downloadURL: String?
    var resolvedURL: String?
    
    var hasBeenTested: Bool = false
    var playerStatus: AVPlayer.Status?
    var resolutionTime: TimeInterval?
    var errors: [StreamError]?
    
    // Performance metrics
    var urlResolutionTime: TimeInterval?
    var playerInitTime: TimeInterval?
    var firstFrameTime: TimeInterval?
    var totalLatency: TimeInterval?
    var httpStatusCode: Int?
    var redirectCount: Int = 0
    
    static func == (lhs: DebugStreamItem, rhs: DebugStreamItem) -> Bool {
        lhs.id == rhs.id
    }
    
    init(from movie: Movie, profile: IPTVProfile) {
        self.id = movie.streamId
        self.title = movie.formattedTitle
        self.type = .movie
        self.fileExtension = movie.containerExtension ?? "mkv"
        self.added = movie.added ?? "0"
        self.categoryId = movie.categoryId
        self.rating = movie.rating5Based
        
        // Build URLs
        self.streamURL = IPTVConfiguration.buildMovieURL(
            profile: profile,
            vodID: String(movie.streamId),
            vodExtension: movie.containerExtension ?? "mkv"
        )
        self.downloadURL = self.streamURL // Same URL for download
    }
    
    init(from serie: Serie) {
        self.id = serie.seriesId
        self.title = serie.name
        self.type = .series
        self.fileExtension = "mkv" // Series don't have extension in the model
        self.added = serie.lastModified
        self.categoryId = serie.categoryId
        self.rating = serie.rating5Based
        
        // Note: Series need episode selection, so URL is not complete
        self.streamURL = nil
        self.downloadURL = nil
    }
    
    init(from channel: LiveChannel, profile: IPTVProfile) {
        self.id = channel.streamId
        self.title = channel.name
        self.type = .movie // Using movie type for channels as they're continuous streams
        self.fileExtension = "ts"
        self.added = channel.added
        self.categoryId = channel.categoryId ?? "0"
        self.rating = nil
        
        // Build URLs
        self.streamURL = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
        self.downloadURL = self.streamURL
    }
}

struct DebugLog: Identifiable {
    let id = UUID()
    let timestamp: String
    let message: String
    let type: LogType
    let source: DebugStreamingViewModel.LogSource

    enum LogType {
        case info
        case success
        case warning
        case error
    }

    init(message: String, type: LogType = .info, source: DebugStreamingViewModel.LogSource = .local) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        self.timestamp = formatter.string(from: Date())
        self.message = message
        self.type = type
        self.source = source
    }
}

struct StreamError: Identifiable {
    let id = UUID()
    let type: ErrorType
    let description: String
    let timestamp: Date
    let context: String?
    
    enum ErrorType {
        case network
        case urlResolution
        case playerInit
        case codec
        case authentication
        case timeout
        case unknown
        
        var icon: String {
            switch self {
            case .network: return "🌐"
            case .urlResolution: return "🔗"
            case .playerInit: return "🎮"
            case .codec: return "🎬"
            case .authentication: return "🔐"
            case .timeout: return "⏱️"
            case .unknown: return "❓"
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class DebugStreamingViewModel: ObservableObject {
    @Published var items: [DebugStreamItem] = []
    @Published var logs: [DebugLog] = []
    @Published var isLoading = false
    @Published var autoScroll = true
    @Published var verboseMode = false
    @Published var liveTVCategories: [LiveChannelCategory] = []
    @Published var movieCategories: [MovieCategory] = []
    @Published var seriesCategories: [SeriesCategory] = []
    
    let movieService: MovieService
    private var cancellables = Set<AnyCancellable>()
    
    /// Source filter for log display.
    enum LogSource: String, CaseIterable {
        case all = "All"
        case local = "Local"
        case remote = "Remote"
    }

    @Published var logSource: LogSource = .all
    @Published var connectedDevices: [RemoteLogReceiver.ConnectedDevice] = []

    init(movieService: MovieService) {
        self.movieService = movieService

        // Subscribe to ALL MKSLog output (local logs from this process).
        MKSLog.localObserver = { [weak self] message, category, level in
            DispatchQueue.main.async {
                guard let self else { return }
                let type: DebugLog.LogType = switch level {
                case "error": .error
                case "warning": .warning
                default: .info
                }
                let entry = DebugLog(message: "[\(category)] \(message)", type: type, source: .local)
                self.appendLog(entry)
            }
        }

        // Subscribe to remote device logs (macOS receives from iPhone via WS).
        #if os(macOS)
        let receiver = RemoteLogReceiver.shared
        receiver.onLogReceived = { [weak self] entry, device in
            DispatchQueue.main.async {
                guard let self else { return }
                let type: DebugLog.LogType = switch entry.level {
                case "error": .error
                case "warning": .warning
                default: .info
                }
                let msg = "📱 [\(device.name)] [\(entry.tag)] \(entry.message)"
                let log = DebugLog(message: msg, type: type, source: .remote)
                self.appendLog(log)
            }
        }
        receiver.start()
        #endif
    }

    deinit {
        MKSLog.localObserver = nil
        // RemoteLogReceiver.onLogReceived uses [weak self] — goes nil automatically.
    }

    // MARK: - Log Management

    private func appendLog(_ entry: DebugLog) {
        // Filter by source if not showing all
        if logSource != .all && entry.source != logSource { return }

        logs.append(entry)
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }
    
    // MARK: - Public Methods
    
    func loadContent(type: DebugStreamingView.ContentTab, liveTVCategory: String = "all") async {
        isLoading = true
        log("🔄 Loading \(type.rawValue)...", type: .info)
        
        do {
            switch type {
            case .movies:
                let movies = try await movieService.fetchMovies(page: 1)
                // Sort by added date (most recent first)
                let sortedMovies = movies
                    .filter { $0.added != nil }
                    .sorted { (Int($0.added ?? "0") ?? 0) > (Int($1.added ?? "0") ?? 0) }
                    .prefix(10)
                
                items = sortedMovies.map { DebugStreamItem(from: $0, profile: movieService.profile) }
                log("✅ Loaded \(items.count) movies", type: .success)
                
            case .series:
                let series = try await movieService.fetchSeries(page: 1)
                // Sort by last modified (most recent first)
                let sortedSeries = series
                    .sorted { (Int($0.lastModified) ?? 0) > (Int($1.lastModified) ?? 0) }
                    .prefix(10)
                
                items = sortedSeries.map { DebugStreamItem(from: $0) }
                log("✅ Loaded \(items.count) series", type: .success)
                
            case .mixed:
                // Load both and mix
                async let moviesTask = movieService.fetchMovies(page: 1)
                async let seriesTask = movieService.fetchSeries(page: 1)
                
                let (movies, series) = try await (moviesTask, seriesTask)
                
                let movieItems = movies
                    .filter { $0.added != nil }
                    .sorted { (Int($0.added ?? "0") ?? 0) > (Int($1.added ?? "0") ?? 0) }
                    .prefix(5)
                    .map { DebugStreamItem(from: $0, profile: movieService.profile) }
                
                let seriesItems = series
                    .sorted { (Int($0.lastModified) ?? 0) > (Int($1.lastModified) ?? 0) }
                    .prefix(5)
                    .map { DebugStreamItem(from: $0) }
                
                items = (movieItems + seriesItems).sorted { $0.added > $1.added }
                log("✅ Loaded \(items.count) items (mixed)", type: .success)
                
            case .liveTV:
                // Load categories if not already loaded
                if liveTVCategories.isEmpty {
                    liveTVCategories = try await movieService.fetchLiveChannelsCategories()
                    log("✅ Loaded \(liveTVCategories.count) Live TV categories", type: .info)
                }
                
                // Load channels
                let allChannels = try await movieService.fetchLiveChannels()
                log("✅ Loaded \(allChannels.count) total live channels", type: .info)
                
                // Filter by category if needed
                let filteredChannels: [LiveChannel]
                if liveTVCategory == "all" {
                    // Get 20 channels from different categories
                    var selectedChannels: [LiveChannel] = []
                    let categoriesWithChannels = Dictionary(grouping: allChannels, by: { $0.categoryId })
                    
                    // Get up to 4 channels from each of the first 5 categories
                    for (index, (_, channels)) in categoriesWithChannels.enumerated() {
                        if index >= 5 { break }
                        let channelsToAdd = Array(channels.prefix(4))
                        selectedChannels.append(contentsOf: channelsToAdd)
                        if selectedChannels.count >= 20 { break }
                    }
                    
                    filteredChannels = Array(selectedChannels.prefix(20))
                    log("✅ Selected \(filteredChannels.count) channels from various categories", type: .info)
                } else {
                    // Filter by specific category
                    filteredChannels = allChannels.filter { $0.categoryId == liveTVCategory }
                        .prefix(20)
                        .map { $0 }
                    log("✅ Filtered \(filteredChannels.count) channels for category: \(liveTVCategory)", type: .info)
                }
                
                items = filteredChannels.map { DebugStreamItem(from: $0, profile: movieService.profile) }
            }
            
            // Log item details if verbose
            if verboseMode {
                for item in items {
                    log("  📦 \(item.title) - ID: \(item.id), Ext: \(item.fileExtension)", type: .info)
                }
            }
            
        } catch {
            log("❌ Failed to load content: \(error.localizedDescription)", type: .error)
            items = []
        }
        
        isLoading = false
    }
    
    func fetchDetails(for item: DebugStreamItem) async {
        log("🔍 Fetching detailed info for ID: \(item.id)", type: .info)
        
        do {
            switch item.type {
            case .movie:
                let details = try await movieService.fetchMovieDetails(movieId: item.id)
                log("✅ Got movie details:", type: .success)
                log("  Duration: \(details.duration)", type: .info)
                log("  Director: \(details.director)", type: .info)
                log("  Genre: \(details.genre)", type: .info)
                log("  Plot: \(details.plot.prefix(100))...", type: .info)
                
            case .series:
                let details = try await movieService.fetchSeriesDetails(seriesId: item.id)
                log("✅ Got series details:", type: .success)
                log("  Seasons: \(details.seasons.count)", type: .info)
                log("  Episodes: \(details.info.episodeRunTime)", type: .info)
                log("  Genre: \(details.info.genre)", type: .info)
                
                // Show first season episodes if available
                if let firstSeason = details.seasons.first,
                   let episodes = details.episodes[firstSeason.id] {
                    log("  Season 1 has \(episodes.count) episodes", type: .info)
                    if verboseMode, let firstEpisode = episodes.first {
                        let episodeURL = IPTVConfiguration.buildSeriesURL(
                            profile: movieService.profile,
                            vodID: firstEpisode.id,
                            vodExtension: firstEpisode.containerExtension
                        )
                        log("  First episode URL: \(episodeURL)", type: .info)
                    }
                }
            }
        } catch {
            log("❌ Failed to fetch details: \(error.localizedDescription)", type: .error)
        }
    }
    
    func updateItemState(_ id: Int, 
                        hasBeenTested: Bool? = nil, 
                        resolvedURL: String? = nil, 
                        playerStatus: AVPlayer.Status? = nil,
                        urlResolutionTime: TimeInterval? = nil,
                        playerInitTime: TimeInterval? = nil,
                        totalLatency: TimeInterval? = nil,
                        httpStatusCode: Int? = nil,
                        redirectCount: Int? = nil) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            var updatedItem = items[index]
            
            if let hasBeenTested = hasBeenTested {
                updatedItem.hasBeenTested = hasBeenTested
            }
            if let resolvedURL = resolvedURL {
                updatedItem.resolvedURL = resolvedURL
            }
            if let playerStatus = playerStatus {
                updatedItem.playerStatus = playerStatus
            }
            if let urlResolutionTime = urlResolutionTime {
                updatedItem.urlResolutionTime = urlResolutionTime
            }
            if let playerInitTime = playerInitTime {
                updatedItem.playerInitTime = playerInitTime
            }
            if let totalLatency = totalLatency {
                updatedItem.totalLatency = totalLatency
            }
            if let httpStatusCode = httpStatusCode {
                updatedItem.httpStatusCode = httpStatusCode
            }
            if let redirectCount = redirectCount {
                updatedItem.redirectCount = redirectCount
            }
            
            items[index] = updatedItem
        }
    }
    
    /// Log a message from the DebugStreamingView itself (user actions, test results).
    /// These go to MKSLog (which feeds back through localObserver → logs array).
    func log(_ message: String, type: DebugLog.LogType = .info) {
        switch type {
        case .error:   MKSLog.debug.error(message)
        case .warning: MKSLog.debug.warning(message)
        case .success: MKSLog.debug.info(message)
        case .info:    MKSLog.debug.info(message)
        }
    }
    
    func clearLogs() {
        logs.removeAll()
        log("🗑️ Logs cleared", type: .info)
    }
    
    func addError(to itemId: Int, error: StreamError) {
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            var updatedItem = items[index]
            if updatedItem.errors == nil {
                updatedItem.errors = []
            }
            updatedItem.errors?.append(error)
            items[index] = updatedItem
        }
    }
    
    func exportLogsAsText() -> String {
        var output = "IPTV Debug Stream Logs\n"
        output += "Generated: \(Date())\n"
        output += "Total Logs: \(logs.count)\n"
        output += String(repeating: "=", count: 50) + "\n\n"
        
        for log in logs {
            let typeEmoji: String
            switch log.type {
            case .info: typeEmoji = "ℹ️"
            case .success: typeEmoji = "✅"
            case .warning: typeEmoji = "⚠️"
            case .error: typeEmoji = "❌"
            }
            output += "[\(log.timestamp)] \(typeEmoji) \(log.message)\n"
        }
        
        return output
    }
    
    // MARK: - Category URL Generation
    
    func loadAllCategories() async {
        log("🔄 Loading all categories...", type: .info)
        
        do {
            async let movieCategoriesTask = movieService.fetchMovieCategories()
            async let seriesCategoriesTask = movieService.fetchSeriesCategories()
            async let liveTVCategoriesTask = movieService.fetchLiveChannelsCategories()
            
            let (fetchedMovieCategories, fetchedSeriesCategories, fetchedLiveTVCategories) = try await (movieCategoriesTask, seriesCategoriesTask, liveTVCategoriesTask)
            
            movieCategories = fetchedMovieCategories
            seriesCategories = fetchedSeriesCategories
            liveTVCategories = fetchedLiveTVCategories
            
            log("✅ Loaded categories:", type: .success)
            log("  - Movies: \(movieCategories.count) categories", type: .info)
            log("  - Series: \(seriesCategories.count) categories", type: .info)
            log("  - Live TV: \(liveTVCategories.count) categories", type: .info)
            
        } catch {
            log("❌ Failed to load categories: \(error.localizedDescription)", type: .error)
        }
    }
    
    func generateCategoryURLs(
        contentType: DebugStreamingView.ContentTab,
        selectedCategoryIds: Set<String>,
        format: CategoryURLFormat
    ) async -> String {
        
        log("🔄 Generating \(format == .json ? "JSON" : "text") URLs for \(contentType.rawValue)...", type: .info)
        
        do {
            switch contentType {
            case .liveTV:
                return try await generateLiveTVCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
            case .movies:
                return try await generateMovieCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
            case .series:
                return try await generateSeriesCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
            case .mixed:
                return try await generateMixedCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
            }
        } catch {
            let errorMsg = "❌ Failed to generate URLs: \(error.localizedDescription)"
            log(errorMsg, type: .error)
            return errorMsg
        }
    }
    
    private func generateLiveTVCategoryURLs(selectedCategoryIds: Set<String>, format: CategoryURLFormat) async throws -> String {
        log("📺 Loading live channels for selected categories...", type: .info)
        
        let allChannels = try await movieService.fetchLiveChannels()
        let filteredChannels = selectedCategoryIds.isEmpty ? allChannels : allChannels.filter { selectedCategoryIds.contains($0.categoryId ?? "0") }
        let filteredCategories = selectedCategoryIds.isEmpty ? liveTVCategories : liveTVCategories.filter { selectedCategoryIds.contains($0.categoryId) }
        
        log("✅ Loaded \(filteredChannels.count) channels from \(filteredCategories.count) categories", type: .success)
        
        return CategoryURLGenerator.generateLiveChannelURLs(
            channels: filteredChannels,
            categories: filteredCategories,
            profile: movieService.profile,
            format: format
        )
    }
    
    private func generateMovieCategoryURLs(selectedCategoryIds: Set<String>, format: CategoryURLFormat) async throws -> String {
        log("🎬 Loading movies for selected categories...", type: .info)
        
        // Load all movies (this might take time for large libraries)
        var allMovies: [Movie] = []
        var currentPage = 1
        let maxPages = 5 // Limit to avoid excessive loading
        
        repeat {
            let movies = try await movieService.fetchMovies(page: currentPage)
            allMovies.append(contentsOf: movies)
            currentPage += 1
            
            log("  Loaded page \(currentPage - 1): \(movies.count) movies", type: .info)
        } while currentPage <= maxPages
        
        let filteredMovies = selectedCategoryIds.isEmpty ? allMovies : allMovies.filter { selectedCategoryIds.contains($0.categoryId) }
        let filteredCategories = selectedCategoryIds.isEmpty ? movieCategories : movieCategories.filter { selectedCategoryIds.contains($0.categoryId) }
        
        log("✅ Loaded \(filteredMovies.count) movies from \(filteredCategories.count) categories", type: .success)
        
        return CategoryURLGenerator.generateMovieURLs(
            movies: filteredMovies,
            categories: filteredCategories,
            profile: movieService.profile,
            format: format
        )
    }
    
    private func generateSeriesCategoryURLs(selectedCategoryIds: Set<String>, format: CategoryURLFormat) async throws -> String {
        log("📺 Loading series for selected categories...", type: .info)
        
        // Load all series
        var allSeries: [Serie] = []
        var currentPage = 1
        let maxPages = 5 // Limit to avoid excessive loading
        
        repeat {
            let series = try await movieService.fetchSeries(page: currentPage)
            allSeries.append(contentsOf: series)
            currentPage += 1
            
            log("  Loaded page \(currentPage - 1): \(series.count) series", type: .info)
        } while currentPage <= maxPages
        
        let filteredSeries = selectedCategoryIds.isEmpty ? allSeries : allSeries.filter { selectedCategoryIds.contains($0.categoryId) }
        let filteredCategories = selectedCategoryIds.isEmpty ? seriesCategories : seriesCategories.filter { selectedCategoryIds.contains($0.categoryId) }
        
        log("✅ Loaded \(filteredSeries.count) series from \(filteredCategories.count) categories", type: .success)
        
        return CategoryURLGenerator.generateSeriesURLs(
            series: filteredSeries,
            categories: filteredCategories,
            profile: movieService.profile,
            format: format,
            includeEpisodes: false
        )
    }
    
    private func generateMixedCategoryURLs(selectedCategoryIds: Set<String>, format: CategoryURLFormat) async throws -> String {
        log("🎯 Generating mixed content URLs...", type: .info)
        
        async let movieURLs = generateMovieCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
        async let seriesURLs = generateSeriesCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
        async let liveURLs = generateLiveTVCategoryURLs(selectedCategoryIds: selectedCategoryIds, format: format)
        
        let (movies, series, live) = try await (movieURLs, seriesURLs, liveURLs)
        
        switch format {
        case .text:
            return "\(movies)\n\(series)\n\(live)"
        case .json:
            // For JSON, we need to combine arrays properly
            return combineJSONArrays(movies: movies, series: series, live: live)
        }
    }
    
    private func combineJSONArrays(movies: String, series: String, live: String) -> String {
        // This is a simplified combination - in production, you'd parse and merge properly
        let combined = "{\n  \"movies\": \(movies),\n  \"series\": \(series),\n  \"live_channels\": \(live)\n}"
        return combined
    }
    
    func generateSeriesEpisodeURLs(
        for serie: Serie,
        categoryName: String,
        format: CategoryURLFormat
    ) async -> String {
        log("📺 Generating episode URLs for: \(serie.name)", type: .info)
        
        do {
            return try await CategoryURLGenerator.generateEpisodeURLs(
                for: serie,
                category: categoryName,
                profile: movieService.profile,
                movieService: movieService,
                format: format
            )
        } catch {
            let errorMsg = "❌ Failed to generate episode URLs: \(error.localizedDescription)"
            log(errorMsg, type: .error)
            return errorMsg
        }
    }
    
    // MARK: - Private Methods
    
    private func measureTime<T>(operation: () async throws -> T) async rethrows -> (result: T, time: TimeInterval) {
        let start = Date()
        let result = try await operation()
        let time = Date().timeIntervalSince(start)
        return (result, time)
    }
}
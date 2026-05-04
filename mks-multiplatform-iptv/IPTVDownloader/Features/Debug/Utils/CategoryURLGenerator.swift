import Foundation
import IPTVCore

struct CategoryURLItem: Codable {
    let id: String
    let name: String
    let url: String
    let type: String
    let category: String
    let containerExtension: String?
    let streamId: Int?
    
    init(id: String, name: String, url: String, type: String, category: String, containerExtension: String? = nil, streamId: Int? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
        self.category = category
        self.containerExtension = containerExtension
        self.streamId = streamId
    }
}

enum CategoryURLFormat {
    case text
    case json
}

class CategoryURLGenerator {
    
    static func generateLiveChannelURLs(
        channels: [LiveChannel],
        categories: [LiveChannelCategory],
        profile: IPTVProfile,
        format: CategoryURLFormat
    ) -> String {
        let groupedChannels = Dictionary(grouping: channels, by: { $0.categoryId ?? "0" })
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryId, $0.categoryName) })
        
        switch format {
        case .text:
            return generateLiveChannelTextFormat(groupedChannels: groupedChannels, categoryMap: categoryMap, profile: profile)
        case .json:
            return generateLiveChannelJSONFormat(groupedChannels: groupedChannels, categoryMap: categoryMap, profile: profile)
        }
    }
    
    static func generateMovieURLs(
        movies: [Movie],
        categories: [MovieCategory],
        profile: IPTVProfile,
        format: CategoryURLFormat
    ) -> String {
        let groupedMovies = Dictionary(grouping: movies, by: { $0.categoryId })
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryId, $0.categoryName) })
        
        switch format {
        case .text:
            return generateMovieTextFormat(groupedMovies: groupedMovies, categoryMap: categoryMap, profile: profile)
        case .json:
            return generateMovieJSONFormat(groupedMovies: groupedMovies, categoryMap: categoryMap, profile: profile)
        }
    }
    
    static func generateSeriesURLs(
        series: [Serie],
        categories: [SeriesCategory],
        profile: IPTVProfile,
        format: CategoryURLFormat,
        includeEpisodes: Bool = false
    ) -> String {
        let groupedSeries = Dictionary(grouping: series, by: { $0.categoryId })
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.categoryId, $0.categoryName) })
        
        switch format {
        case .text:
            return generateSeriesTextFormat(groupedSeries: groupedSeries, categoryMap: categoryMap, profile: profile, includeEpisodes: includeEpisodes)
        case .json:
            return generateSeriesJSONFormat(groupedSeries: groupedSeries, categoryMap: categoryMap, profile: profile, includeEpisodes: includeEpisodes)
        }
    }
    
    // MARK: - Text Format Generators
    
    private static func generateLiveChannelTextFormat(
        groupedChannels: [String: [LiveChannel]],
        categoryMap: [String: String],
        profile: IPTVProfile
    ) -> String {
        var result = "=== LIVE TV CHANNELS ===\n\n"
        
        for (categoryId, channels) in groupedChannels.sorted(by: { $0.key < $1.key }) {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            result += "=== CATEGORY: \(categoryName) ===\n"
            
            for (index, channel) in channels.enumerated() {
                let url = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                result += "\(index + 1). \(channel.name) - \(url)\n"
            }
            result += "\n"
        }
        
        return result
    }
    
    private static func generateMovieTextFormat(
        groupedMovies: [String: [Movie]],
        categoryMap: [String: String],
        profile: IPTVProfile
    ) -> String {
        var result = "=== MOVIES ===\n\n"
        
        for (categoryId, movies) in groupedMovies.sorted(by: { $0.key < $1.key }) {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            result += "=== CATEGORY: \(categoryName) ===\n"
            
            for (index, movie) in movies.enumerated() {
                let url = IPTVConfiguration.buildMovieURL(
                    profile: profile,
                    vodID: String(movie.streamId),
                    vodExtension: movie.containerExtension ?? "mp4"
                )
                result += "\(index + 1). \(movie.formattedTitle) - \(url)\n"
            }
            result += "\n"
        }
        
        return result
    }
    
    private static func generateSeriesTextFormat(
        groupedSeries: [String: [Serie]],
        categoryMap: [String: String],
        profile: IPTVProfile,
        includeEpisodes: Bool
    ) -> String {
        var result = "=== SERIES ===\n\n"
        
        for (categoryId, series) in groupedSeries.sorted(by: { $0.key < $1.key }) {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            result += "=== CATEGORY: \(categoryName) ===\n"
            
            for (index, serie) in series.enumerated() {
                result += "\(index + 1). \(serie.name)\n"
                if includeEpisodes {
                    result += "   Note: Episode URLs require individual episode data - use episode picker for specific URLs\n"
                } else {
                    result += "   Series ID: \(serie.seriesId) (Use episode picker for specific episode URLs)\n"
                }
            }
            result += "\n"
        }
        
        return result
    }
    
    // MARK: - JSON Format Generators
    
    private static func generateLiveChannelJSONFormat(
        groupedChannels: [String: [LiveChannel]],
        categoryMap: [String: String],
        profile: IPTVProfile
    ) -> String {
        var items: [CategoryURLItem] = []
        
        for (categoryId, channels) in groupedChannels {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            
            for channel in channels {
                let url = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                let item = CategoryURLItem(
                    id: "live_\(channel.streamId)",
                    name: channel.name,
                    url: url,
                    type: "live_channel",
                    category: categoryName,
                    containerExtension: "ts",
                    streamId: channel.streamId
                )
                items.append(item)
            }
        }
        
        return generateJSONString(from: items)
    }
    
    private static func generateMovieJSONFormat(
        groupedMovies: [String: [Movie]],
        categoryMap: [String: String],
        profile: IPTVProfile
    ) -> String {
        var items: [CategoryURLItem] = []
        
        for (categoryId, movies) in groupedMovies {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            
            for movie in movies {
                let url = IPTVConfiguration.buildMovieURL(
                    profile: profile,
                    vodID: String(movie.streamId),
                    vodExtension: movie.containerExtension ?? "mp4"
                )
                let item = CategoryURLItem(
                    id: "movie_\(movie.streamId)",
                    name: movie.formattedTitle,
                    url: url,
                    type: "movie",
                    category: categoryName,
                    containerExtension: movie.containerExtension,
                    streamId: movie.streamId
                )
                items.append(item)
            }
        }
        
        return generateJSONString(from: items)
    }
    
    private static func generateSeriesJSONFormat(
        groupedSeries: [String: [Serie]],
        categoryMap: [String: String],
        profile: IPTVProfile,
        includeEpisodes: Bool
    ) -> String {
        var items: [CategoryURLItem] = []
        
        for (categoryId, series) in groupedSeries {
            let categoryName = categoryMap[categoryId] ?? "Unknown Category"
            
            for serie in series {
                let item = CategoryURLItem(
                    id: "series_\(serie.seriesId)",
                    name: serie.name,
                    url: includeEpisodes ? "requires_episode_data" : "use_episode_picker",
                    type: "series",
                    category: categoryName,
                    streamId: serie.seriesId
                )
                items.append(item)
            }
        }
        
        return generateJSONString(from: items)
    }
    
    private static func generateJSONString(from items: [CategoryURLItem]) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(items)
            return String(data: jsonData, encoding: .utf8) ?? "Failed to encode JSON"
        } catch {
            return "JSON encoding error: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Episode URL Generator (async)
    
    static func generateEpisodeURLs(
        for serie: Serie,
        category: String,
        profile: IPTVProfile,
        movieService: MovieService,
        format: CategoryURLFormat
    ) async throws -> String {
        
        let details = try await movieService.fetchSeriesDetails(seriesId: serie.seriesId)
        
        switch format {
        case .text:
            return generateEpisodeTextFormat(serie: serie, details: details, category: category, profile: profile)
        case .json:
            return generateEpisodeJSONFormat(serie: serie, details: details, category: category, profile: profile)
        }
    }
    
    /// Returns the episodes for a season, probing by season.id first and
    /// then by String(season.seasonNumber) as a fallback.
    /// Xtream IPTV panels key episodes by season number, not by season ID.
    private static func episodes(for season: SerieDetail.Season, in details: SerieDetail) -> [SerieDetail.Episode] {
        details.episodes[season.id]
            ?? details.episodes[String(season.seasonNumber)]
            ?? []
    }

    private static func generateEpisodeTextFormat(
        serie: Serie,
        details: SerieDetail,
        category: String,
        profile: IPTVProfile
    ) -> String {
        var result = "=== SERIES: \(serie.name) ===\n"
        result += "Category: \(category)\n\n"
        
        for season in details.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            result += "--- Season \(season.seasonNumber) ---\n"
            
            for episode in episodes(for: season, in: details).sorted(by: { $0.episodeNum < $1.episodeNum }) {
                let url = IPTVConfiguration.buildSeriesURL(
                    profile: profile,
                    vodID: episode.id,
                    vodExtension: episode.containerExtension
                )
                result += "S\(season.seasonNumber)E\(episode.episodeNum). \(episode.title) - \(url)\n"
            }
            result += "\n"
        }
        
        return result
    }
    
    private static func generateEpisodeJSONFormat(
        serie: Serie,
        details: SerieDetail,
        category: String,
        profile: IPTVProfile
    ) -> String {
        var items: [CategoryURLItem] = []
        
        for season in details.seasons {
            for episode in episodes(for: season, in: details) {
                let url = IPTVConfiguration.buildSeriesURL(
                    profile: profile,
                    vodID: episode.id,
                    vodExtension: episode.containerExtension
                )
                let item = CategoryURLItem(
                    id: "episode_\(episode.id)",
                    name: "\(serie.name) - S\(season.seasonNumber)E\(episode.episodeNum) - \(episode.title)",
                    url: url,
                    type: "episode",
                    category: category,
                    containerExtension: episode.containerExtension
                )
                items.append(item)
            }
        }
        
        return generateJSONString(from: items)
    }
}

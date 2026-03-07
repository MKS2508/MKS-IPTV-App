import Foundation

struct SerieDetail: Codable {
    /// Set from the calling context after decoding (the API response doesn't include it).
    var seriesId: Int = 0

    let seasons: [Season]
    let info: SerieInfo
    let episodes: [String: [Episode]]

    enum CodingKeys: String, CodingKey {
        case seasons, info, episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasons = try container.decode([Season].self, forKey: .seasons)
        info = try container.decode(SerieInfo.self, forKey: .info)

        // Handle both dictionary and array formats for episodes
        if let episodesDict = try? container.decode([String: [Episode]].self, forKey: .episodes) {
            episodes = Self.markDuplicates(in: episodesDict)
        } else if let episodesArray = try? container.decode([Episode].self, forKey: .episodes) {
            // Group episodes by season when API returns an array
            var grouped: [String: [Episode]] = [:]
            for episode in episodesArray {
                let seasonKey = String(episode.season)
                grouped[seasonKey, default: []].append(episode)
            }
            episodes = Self.markDuplicates(in: grouped)
        } else {
            episodes = [:]
        }
    }

    /// Mark duplicate episodes with duplicateIndex > 0
    private static func markDuplicates(in episodesDict: [String: [Episode]]) -> [String: [Episode]] {
        var result: [String: [Episode]] = [:]
        for (seasonKey, seasonEpisodes) in episodesDict {
            var seen: [Int: Int] = [:] // episodeNum -> count
            var marked: [Episode] = []
            for var episode in seasonEpisodes {
                let count = seen[episode.episodeNum, default: 0]
                if count > 0 {
                    episode.duplicateIndex = count
                }
                seen[episode.episodeNum, default: 0] += 1
                marked.append(episode)
            }
            result[seasonKey] = marked
        }
        return result
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seasons, forKey: .seasons)
        try container.encode(info, forKey: .info)
        try container.encode(episodes, forKey: .episodes)
    }
    
    struct Season: Codable {
        let airDate: String
        let episodeCount: Int
        let id: String
        let name: String
        @CodableStringInt var seasonNumber: Int
        let overview: String
        let cover: String?
        let coverBig: String?
        
        enum CodingKeys: String, CodingKey {
            case airDate = "air_date"
            case episodeCount = "episode_count"
            case id
            case name
            case seasonNumber = "season_number"
            case overview
            case cover
            case coverBig = "cover_big"
        }
    }
    
    struct SerieInfo: Codable {
        let name: String
        let cover: String?
        let youtubeTrailer: String?
        let genre: String
        let releaseDate: String
        let plot: String
        let cast: String
        let rating: String
        let rating5Based: Double
        let director: String?
        let backdropPath: [String]
        let lastModified: String
        let episodeRunTime: String
        let categoryId: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case cover
            case youtubeTrailer = "youtube_trailer"
            case genre
            case releaseDate = "releaseDate"
            case plot
            case cast
            case rating
            case rating5Based = "rating_5based"
            case director
            case backdropPath = "backdrop_path"
            case lastModified = "last_modified"
            case episodeRunTime = "episode_run_time"
            case categoryId = "category_id"
        }
    }
    
    struct Episode: Identifiable, Codable {
        let id: String
        let episodeNum: Int
        let title: String
        let containerExtension: String
        let added: String
        let info: EpisodeInfo
        let season: Int
        let customSid: String?
        let directSource: String?
        
        /// Set during decoding when duplicate episode is detected
        var duplicateIndex: Int = 0
        
        /// Title with duplicate suffix if applicable
        var displayTitle: String {
            if duplicateIndex > 0 {
                return "\(title) - duplicado"
            }
            return title
        }
        
        enum CodingKeys: String, CodingKey {
            case id
            case episodeNum = "episode_num"
            case title
            case containerExtension = "container_extension"
            case added
            case info
            case season
            case customSid = "custom_sid"
            case directSource = "direct_source"
            case duplicateIndex
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            episodeNum = try container.decode(Int.self, forKey: .episodeNum)
            title = try container.decode(String.self, forKey: .title)
            containerExtension = try container.decode(String.self, forKey: .containerExtension)
            added = try container.decode(String.self, forKey: .added)
            info = try container.decode(EpisodeInfo.self, forKey: .info)
            season = try container.decode(Int.self, forKey: .season)
            customSid = try container.decodeIfPresent(String.self, forKey: .customSid)
            directSource = try container.decodeIfPresent(String.self, forKey: .directSource)
            duplicateIndex = try container.decodeIfPresent(Int.self, forKey: .duplicateIndex) ?? 0
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(episodeNum, forKey: .episodeNum)
            try container.encode(title, forKey: .title)
            try container.encode(containerExtension, forKey: .containerExtension)
            try container.encode(added, forKey: .added)
            try container.encode(info, forKey: .info)
            try container.encode(season, forKey: .season)
            try container.encodeIfPresent(customSid, forKey: .customSid)
            try container.encodeIfPresent(directSource, forKey: .directSource)
            if duplicateIndex > 0 {
                try container.encode(duplicateIndex, forKey: .duplicateIndex)
            }
        }
    }
    
    struct EpisodeInfo: Codable {
        let movieImage: String
        let releaseDate: String
        let youtubeTrailer: String?
        let plot: String
        let cast: String
        let rating: Int
        let rating5Based: Double
        let director: String?
        let durationSecs: Int
        let duration: String
        
        enum CodingKeys: String, CodingKey {
            case movieImage = "movie_image"
            case releaseDate = "releaseDate"
            case youtubeTrailer = "youtube_trailer"
            case plot
            case cast
            case rating
            case rating5Based = "rating_5based"
            case director
            case durationSecs = "duration_secs"
            case duration
        }
    }
}

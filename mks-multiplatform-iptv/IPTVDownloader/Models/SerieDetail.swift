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
    
    struct Episode: Codable {
        let id: String
        let episodeNum: Int
        let title: String
        let containerExtension: String
        let added: String
        let info: EpisodeInfo
        let season: Int
        let customSid: String?
        let directSource: String?
        
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

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
        episodes = Self.decodeEpisodes(from: container)
    }

    // MARK: - Bulletproof Episode Parser

    /// Xtream Codes is wildly inconsistent — this handles every known format
    /// and tolerates individual episode decode failures without losing the rest.
    private static func decodeEpisodes(from container: KeyedDecodingContainer<CodingKeys>) -> [String: [Episode]] {
        // 1. Standard dictionary: {"1": [episodes], "2": [episodes]}
        if let dict = try? container.decode([String: [Episode]].self, forKey: .episodes), !dict.isEmpty {
            MKSLog.media.debug("Episodes: dict format, \(dict.count) seasons")
            return markDuplicates(in: dict)
        }

        // 2. 2D array: [[s0eps], [s1eps], ...] — Los Simpson and others use this
        if let array2D = try? container.decode([[Episode]].self, forKey: .episodes), !array2D.isEmpty {
            MKSLog.media.debug("Episodes: 2D array format, \(array2D.count) seasons, \(array2D.flatMap { $0 }.count) eps")
            return groupAndMark(array2D.flatMap { $0 })
        }

        // 3. Flat array: [ep1, ep2, ...]
        if let flat = try? container.decode([Episode].self, forKey: .episodes), !flat.isEmpty {
            MKSLog.media.debug("Episodes: flat array, \(flat.count) eps")
            return groupAndMark(flat)
        }

        // 4. Int-keyed dictionary: {1: [episodes], 2: [episodes]}
        if let intDict = try? container.decode([Int: [Episode]].self, forKey: .episodes), !intDict.isEmpty {
            MKSLog.media.debug("Episodes: int-keyed dict, \(intDict.count) seasons")
            var grouped: [String: [Episode]] = [:]
            for (key, value) in intDict {
                grouped[String(key)] = value
            }
            return markDuplicates(in: grouped)
        }

        // 5. Nuclear fallback: raw JSON → iterate episode objects individually
        //    This catches cases where Codable fails on the whole collection
        //    but individual episodes might still decode if we're lenient enough.
        if let rawEpisodes = try? Self.parseEpisodesFromRawJSON(container) {
            return rawEpisodes
        }

        MKSLog.media.warning("Episodes: all formats failed — empty dict")
        return [:]
    }

    /// Parse episodes from raw JSON structure, tolerating individual episode failures.
    private static func parseEpisodesFromRawJSON(_ container: KeyedDecodingContainer<CodingKeys>) -> [String: [Episode]]? {
        // Decode as raw JSON object, then iterate
        guard let rawValue = try? container.decode(AnyCodableValue.self, forKey: .episodes),
              let topLevel = rawValue.value else { return nil }

        var allEpisodes: [Episode] = []
        var failCount = 0

        switch topLevel {
        case let array as [Any]:
            for item in array {
                if let subArray = item as? [Any] {
                    // 2D array — iterate inner array
                    for subItem in subArray {
                        if let ep = tryDecodeEpisode(from: subItem) {
                            allEpisodes.append(ep)
                        } else {
                            failCount += 1
                        }
                    }
                } else {
                    // Flat array — single episode object
                    if let ep = tryDecodeEpisode(from: item) {
                        allEpisodes.append(ep)
                    } else {
                        failCount += 1
                    }
                }
            }
        case let dict as [String: Any]:
            for (_, value) in dict {
                if let epArray = value as? [Any] {
                    for item in epArray {
                        if let ep = tryDecodeEpisode(from: item) {
                            allEpisodes.append(ep)
                        } else {
                            failCount += 1
                        }
                    }
                }
            }
        default:
            return nil
        }

        if allEpisodes.isEmpty { return nil }

        if failCount > 0 {
            MKSLog.media.warning("Episodes: raw fallback decoded \(allEpisodes.count) eps, \(failCount) failed individually")
        } else {
            MKSLog.media.debug("Episodes: raw fallback decoded \(allEpisodes.count) eps")
        }
        return groupAndMark(allEpisodes)
    }

    /// Attempt to decode a single Episode from a raw JSON dictionary.
    private static func tryDecodeEpisode(from raw: Any) -> Episode? {
        guard let dict = raw as? [String: Any] else { return nil }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(Episode.self, from: data)
        } catch {
            MKSLog.media.debug("Episode decode failed: \(error.localizedDescription) — raw id=\(dict["id"] ?? "?")")
            return nil
        }
    }

    private static func groupAndMark(_ episodes: [Episode]) -> [String: [Episode]] {
        var grouped: [String: [Episode]] = [:]
        for episode in episodes {
            let key = String(episode.season)
            grouped[key, default: []].append(episode)
        }
        return markDuplicates(in: grouped)
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
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? c.decode(String.self, forKey: .id)) ?? ""
            episodeNum = (try? c.decode(Int.self, forKey: .episodeNum)) ?? 0
            title = (try? c.decode(String.self, forKey: .title)) ?? ""
            containerExtension = (try? c.decode(String.self, forKey: .containerExtension)) ?? "mkv"
            added = (try? c.decode(String.self, forKey: .added)) ?? ""
            info = (try? c.decode(EpisodeInfo.self, forKey: .info)) ?? EpisodeInfo()
            season = (try? c.decode(Int.self, forKey: .season)) ?? 0
            customSid = try? c.decodeIfPresent(String.self, forKey: .customSid)
            directSource = try? c.decodeIfPresent(String.self, forKey: .directSource)
            duplicateIndex = (try? c.decodeIfPresent(Int.self, forKey: .duplicateIndex)) ?? 0
        }

        init(
            id: String = "",
            episodeNum: Int = 0,
            title: String = "",
            containerExtension: String = "mkv",
            added: String = "",
            info: EpisodeInfo = EpisodeInfo(),
            season: Int = 0,
            customSid: String? = nil,
            directSource: String? = nil,
            duplicateIndex: Int = 0
        ) {
            self.id = id
            self.episodeNum = episodeNum
            self.title = title
            self.containerExtension = containerExtension
            self.added = added
            self.info = info
            self.season = season
            self.customSid = customSid
            self.directSource = directSource
            self.duplicateIndex = duplicateIndex
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
        var movieImage: String
        var releaseDate: String
        var youtubeTrailer: String?
        var plot: String
        var cast: String
        var rating: Int
        var rating5Based: Double
        var director: String?
        var durationSecs: Int
        var duration: String

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

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            movieImage = (try? c.decodeIfPresent(String.self, forKey: .movieImage)) ?? ""
            releaseDate = (try? c.decodeIfPresent(String.self, forKey: .releaseDate)) ?? ""
            youtubeTrailer = try? c.decodeIfPresent(String.self, forKey: .youtubeTrailer)
            plot = (try? c.decodeIfPresent(String.self, forKey: .plot)) ?? ""
            cast = (try? c.decodeIfPresent(String.self, forKey: .cast)) ?? ""
            rating = Self.decodeFlexibleInt(from: c, forKey: .rating)
            rating5Based = Self.decodeFlexibleDouble(from: c, forKey: .rating5Based)
            director = try? c.decodeIfPresent(String.self, forKey: .director)
            durationSecs = Self.decodeFlexibleInt(from: c, forKey: .durationSecs)
            duration = (try? c.decodeIfPresent(String.self, forKey: .duration)) ?? ""
        }

        init(
            movieImage: String = "",
            releaseDate: String = "",
            youtubeTrailer: String? = nil,
            plot: String = "",
            cast: String = "",
            rating: Int = 0,
            rating5Based: Double = 0,
            director: String? = nil,
            durationSecs: Int = 0,
            duration: String = ""
        ) {
            self.movieImage = movieImage
            self.releaseDate = releaseDate
            self.youtubeTrailer = youtubeTrailer
            self.plot = plot
            self.cast = cast
            self.rating = rating
            self.rating5Based = rating5Based
            self.director = director
            self.durationSecs = durationSecs
            self.duration = duration
        }

        /// Decode Int that might come as Int, Double, String, or null
        private static func decodeFlexibleInt(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
            if let v = try? c.decodeIfPresent(String.self, forKey: key), let parsed = Int(v) { return parsed }
            return 0
        }

        /// Decode Double that might come as Double, Int, String, or null
        private static func decodeFlexibleDouble(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double {
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(v) }
            if let v = try? c.decodeIfPresent(String.self, forKey: key), let parsed = Double(v) { return parsed }
            return 0
        }
    }
}

// MARK: - AnyCodableValue (helper for raw JSON fallback)

/// Minimal type-erased Codable wrapper used only for the raw JSON episode fallback.
private struct AnyCodableValue: Codable {
    let value: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = value {
            if let str = value as? String {
                try container.encode(str)
            } else if let num = value as? Double {
                try container.encode(num)
            } else if let bool = value as? Bool {
                try container.encode(bool)
            } else {
                try container.encodeNil()
            }
        } else {
            try container.encodeNil()
        }
    }
}

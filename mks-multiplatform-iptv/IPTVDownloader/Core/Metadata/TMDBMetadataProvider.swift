import Foundation

/// Metadata provider using The Movie Database (TMDB) API v3.
///
/// Primary provider — the IPTV server already exposes `tmdb_id` for most content,
/// enabling exact ID lookups with maximum confidence.
actor TMDBMetadataProvider: MetadataProvider {
    nonisolated let name = "TMDB"

    private let session: URLSession
    private let apiKey: String
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p"

    init(session: URLSession = .shared, apiKey: String = APIKeys.tmdb) {
        self.session = session
        self.apiKey = apiKey
    }

    nonisolated func isAvailable() -> Bool {
        !APIKeys.tmdb.isEmpty && APIKeys.tmdb != "TMDB_API_KEY_PLACEHOLDER"
    }

    // MARK: - Search

    func search(query: MetadataSearchQuery) async throws -> [MetadataResult] {
        // If tmdbId is available, do exact lookup (highest confidence)
        if let tmdbId = query.tmdbId {
            if let result = try await fetchById(tmdbId: tmdbId, mediaType: query.mediaType) {
                return [result]
            }
        }

        // Otherwise, search by title
        let endpoint = query.mediaType == .movie ? "/search/movie" : "/search/tv"
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: StringSimilarity.cleanTitle(query.title)),
            URLQueryItem(name: "language", value: "es-ES"),
            URLQueryItem(name: "page", value: "1")
        ]
        if let year = query.year {
            let yearKey = query.mediaType == .movie ? "year" : "first_air_date_year"
            components.queryItems?.append(URLQueryItem(name: yearKey, value: String(year)))
        }

        guard let url = components.url else {
            throw MetadataError.parsingFailed("Invalid TMDB search URL")
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MetadataError.providerUnavailable("TMDB")
        }

        let searchResponse = try JSONDecoder().decode(TMDBSearchResponse.self, from: data)
        return searchResponse.results.prefix(5).map { item in
            mapSearchItem(item, mediaType: query.mediaType)
        }
    }

    // MARK: - Fetch by ID

    func fetchById(tmdbId: Int, mediaType: MetadataMediaType) async throws -> MetadataResult? {
        let endpoint = mediaType == .movie ? "/movie/\(tmdbId)" : "/tv/\(tmdbId)"
        var components = URLComponents(string: "\(baseURL)\(endpoint)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "append_to_response", value: "credits,images"),
            URLQueryItem(name: "language", value: "es-ES")
        ]

        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        if mediaType == .movie {
            let detail = try JSONDecoder().decode(TMDBMovieDetail.self, from: data)
            return mapMovieDetail(detail)
        } else {
            let detail = try JSONDecoder().decode(TMDBTVDetail.self, from: data)
            return mapTVDetail(detail)
        }
    }

    // MARK: - Mapping

    private func mapSearchItem(_ item: TMDBSearchItem, mediaType: MetadataMediaType) -> MetadataResult {
        let title = item.title ?? item.name ?? ""
        let dateString = item.releaseDate ?? item.firstAirDate
        let year = dateString.flatMap { extractYear(from: $0) }

        return MetadataResult(
            title: title,
            originalTitle: item.originalTitle ?? item.originalName,
            year: year,
            releaseDate: dateString,
            genre: mapGenreIds(item.genreIds, mediaType: mediaType),
            plot: item.overview,
            rating: item.voteAverage,
            ratingSource: "tmdb",
            posterURL: item.posterPath.map { "\(imageBaseURL)/w500\($0)" },
            backdropURL: item.backdropPath.map { "\(imageBaseURL)/w1280\($0)" },
            artworkURLs: [
                item.posterPath.map { "\(imageBaseURL)/original\($0)" },
                item.backdropPath.map { "\(imageBaseURL)/original\($0)" }
            ].compactMap { $0 },
            tmdbId: item.id,
            providerName: name,
            confidence: 0.5, // Base confidence for search results; resolver will re-score
            mediaType: mediaType
        )
    }

    private func mapMovieDetail(_ detail: TMDBMovieDetail) -> MetadataResult {
        let directors = detail.credits?.crew?
            .filter { $0.job?.lowercased() == "director" }
            .map(\.name) ?? []
        let cast = detail.credits?.cast?.prefix(10).map(\.name) ?? []
        let year = detail.releaseDate.flatMap { extractYear(from: $0) }

        return MetadataResult(
            title: detail.title,
            originalTitle: detail.originalTitle,
            year: year,
            releaseDate: detail.releaseDate,
            genre: detail.genres.map(\.name),
            plot: detail.overview,
            director: directors.joined(separator: ", "),
            cast: Array(cast),
            rating: detail.voteAverage,
            ratingSource: "tmdb",
            runtimeMinutes: detail.runtime,
            posterURL: detail.posterPath.map { "\(imageBaseURL)/w500\($0)" },
            backdropURL: detail.backdropPath.map { "\(imageBaseURL)/w1280\($0)" },
            artworkURLs: [
                detail.posterPath.map { "\(imageBaseURL)/original\($0)" },
                detail.backdropPath.map { "\(imageBaseURL)/original\($0)" }
            ].compactMap { $0 },
            tmdbId: detail.id,
            imdbId: detail.imdbId,
            providerName: name,
            confidence: 1.0, // Exact ID match
            mediaType: .movie
        )
    }

    private func mapTVDetail(_ detail: TMDBTVDetail) -> MetadataResult {
        let cast = detail.credits?.cast?.prefix(10).map(\.name) ?? []
        let creators = detail.createdBy?.map(\.name) ?? []
        let year = detail.firstAirDate.flatMap { extractYear(from: $0) }

        return MetadataResult(
            title: detail.name,
            originalTitle: detail.originalName,
            year: year,
            releaseDate: detail.firstAirDate,
            genre: detail.genres.map(\.name),
            plot: detail.overview,
            director: creators.joined(separator: ", "),
            cast: Array(cast),
            rating: detail.voteAverage,
            ratingSource: "tmdb",
            runtimeMinutes: detail.episodeRunTime?.first,
            posterURL: detail.posterPath.map { "\(imageBaseURL)/w500\($0)" },
            backdropURL: detail.backdropPath.map { "\(imageBaseURL)/w1280\($0)" },
            artworkURLs: [
                detail.posterPath.map { "\(imageBaseURL)/original\($0)" },
                detail.backdropPath.map { "\(imageBaseURL)/original\($0)" }
            ].compactMap { $0 },
            tmdbId: detail.id,
            providerName: name,
            confidence: 1.0,
            mediaType: .series,
            showTitle: detail.name
        )
    }

    // MARK: - Helpers

    private func extractYear(from dateString: String) -> Int? {
        guard dateString.count >= 4 else { return nil }
        return Int(dateString.prefix(4))
    }

    /// Map TMDB genre IDs to names using a static lookup table.
    /// Covers the most common movie and TV genres.
    private func mapGenreIds(_ ids: [Int], mediaType: MetadataMediaType) -> [String] {
        ids.compactMap { Self.genreMap[$0] }
    }

    private static let genreMap: [Int: String] = [
        // Movie genres
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
        80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
        14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
        9648: "Mystery", 10749: "Romance", 878: "Science Fiction",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
        // TV genres
        10759: "Action & Adventure", 10762: "Kids", 10763: "News",
        10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
        10767: "Talk", 10768: "War & Politics"
    ]
}

// MARK: - TMDB API Response Models

private struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchItem]
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case results
        case totalResults = "total_results"
    }
}

private struct TMDBSearchItem: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let genreIds: [Int]
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case originalTitle = "original_title"
        case originalName = "original_name"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case genreIds = "genre_ids"
        case voteAverage = "vote_average"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
    }
}

private struct TMDBMovieDetail: Decodable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String?
    let releaseDate: String?
    let runtime: Int?
    let genres: [TMDBGenre]
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let imdbId: String?
    let credits: TMDBCredits?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, credits
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case imdbId = "imdb_id"
    }
}

private struct TMDBTVDetail: Decodable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let firstAirDate: String?
    let genres: [TMDBGenre]
    let voteAverage: Double?
    let posterPath: String?
    let backdropPath: String?
    let episodeRunTime: [Int]?
    let createdBy: [TMDBCreator]?
    let credits: TMDBCredits?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, genres, credits
        case originalName = "original_name"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case episodeRunTime = "episode_run_time"
        case createdBy = "created_by"
    }
}

private struct TMDBGenre: Decodable {
    let id: Int
    let name: String
}

private struct TMDBCredits: Decodable {
    let cast: [TMDBCastMember]?
    let crew: [TMDBCrewMember]?
}

private struct TMDBCastMember: Decodable {
    let name: String
    let character: String?
    let order: Int?
}

private struct TMDBCrewMember: Decodable {
    let name: String
    let job: String?
}

private struct TMDBCreator: Decodable {
    let name: String
}

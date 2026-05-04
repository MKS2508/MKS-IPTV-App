import Foundation
import IPTVCore

/// Metadata provider using TheTVDB API v4.
///
/// Particularly strong for TV series and episode metadata.
/// Uses JWT token authentication with automatic refresh on 401.
actor TheTVDBMetadataProvider: MetadataProvider {
    nonisolated let name = "TheTVDB"

    private let session: URLSession
    private let apiKey: String
    private let baseURL = "https://api4.thetvdb.com/v4"

    /// Cached JWT token and its expiration date
    private var cachedToken: String?
    private var tokenExpiration: Date?

    /// Token validity: 1 month minus 1 day safety margin
    private let tokenTTL: TimeInterval = 29 * 24 * 3600

    init(session: URLSession = .shared, apiKey: String = APIKeys.tvdb) {
        self.session = session
        self.apiKey = apiKey
    }

    nonisolated func isAvailable() -> Bool {
        !APIKeys.tvdb.isEmpty && APIKeys.tvdb != "TVDB_API_KEY_PLACEHOLDER"
    }

    // MARK: - Authentication

    /// Obtain a JWT token via POST /login, caching it for reuse.
    private func getToken() async throws -> String {
        // Return cached token if still valid
        if let token = cachedToken,
           let expiration = tokenExpiration,
           Date() < expiration {
            return token
        }

        // Request new token
        guard let url = URL(string: "\(baseURL)/login") else {
            throw MetadataError.parsingFailed("Invalid TheTVDB login URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["apikey": apiKey]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MetadataError.providerUnavailable("TheTVDB login failed")
        }

        let loginResponse = try JSONDecoder().decode(TVDBLoginResponse.self, from: data)
        cachedToken = loginResponse.data.token
        tokenExpiration = Date().addingTimeInterval(tokenTTL)
        return loginResponse.data.token
    }

    /// Invalidate cached token (called on 401 before retry).
    private func invalidateToken() {
        cachedToken = nil
        tokenExpiration = nil
    }

    /// Build an authenticated GET request with the JWT token.
    private func authenticatedRequest(url: URL) async throws -> URLRequest {
        let token = try await getToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Perform an authenticated GET request, retrying once on 401.
    private func authenticatedData(from url: URL) async throws -> (Data, URLResponse) {
        let request = try await authenticatedRequest(url: url)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // Token expired — refresh and retry once
            invalidateToken()
            let retryRequest = try await authenticatedRequest(url: url)
            return try await session.data(for: retryRequest)
        }

        return (data, response)
    }

    // MARK: - Search

    func search(query: MetadataSearchQuery) async throws -> [MetadataResult] {
        let cleanedTitle = StringSimilarity.cleanTitle(query.title)
        let searchType = query.mediaType == .movie ? "movie" : "series"

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: cleanedTitle),
            URLQueryItem(name: "type", value: searchType),
            URLQueryItem(name: "limit", value: "5")
        ]
        if let year = query.year {
            components.queryItems?.append(URLQueryItem(name: "year", value: String(year)))
        }

        guard let url = components.url else {
            throw MetadataError.parsingFailed("Invalid TheTVDB search URL")
        }

        let (data, response) = try await authenticatedData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MetadataError.providerUnavailable("TheTVDB")
        }

        let searchResponse = try JSONDecoder().decode(TVDBSearchResponse.self, from: data)
        return (searchResponse.data ?? []).prefix(5).compactMap { item in
            mapSearchItem(item, mediaType: query.mediaType)
        }
    }

    // MARK: - Fetch by ID (cross-reference via IMDB ID)

    func fetchById(tmdbId: Int, mediaType: MetadataMediaType) async throws -> MetadataResult? {
        // TheTVDB doesn't use TMDB IDs directly.
        // We'd need an IMDB ID for cross-reference, which we don't have at this point.
        // Return nil — the resolver will use search-based matching instead.
        nil
    }

    // MARK: - Extended Detail Fetch

    /// Fetch extended details for a series by its TVDB ID.
    private func fetchSeriesDetail(tvdbId: Int) async throws -> MetadataResult? {
        guard let url = URL(string: "\(baseURL)/series/\(tvdbId)/extended") else { return nil }

        let (data, response) = try await authenticatedData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let detailResponse = try JSONDecoder().decode(TVDBSeriesDetailResponse.self, from: data)
        return mapSeriesDetail(detailResponse.data)
    }

    /// Fetch extended details for a movie by its TVDB ID.
    private func fetchMovieDetail(tvdbId: Int) async throws -> MetadataResult? {
        guard let url = URL(string: "\(baseURL)/movies/\(tvdbId)/extended") else { return nil }

        let (data, response) = try await authenticatedData(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let detailResponse = try JSONDecoder().decode(TVDBMovieDetailResponse.self, from: data)
        return mapMovieDetail(detailResponse.data)
    }

    // MARK: - Mapping

    private func mapSearchItem(_ item: TVDBSearchItem, mediaType: MetadataMediaType) -> MetadataResult? {
        guard let itemName = item.name ?? item.translations?["eng"] else { return nil }

        let year = item.year.flatMap { Int($0) }
        let posterURL = item.imageUrl ?? item.thumbnail

        return MetadataResult(
            title: itemName,
            originalTitle: item.originalName,
            year: year,
            releaseDate: item.firstAirTime,
            genre: item.genres?.compactMap(\.name) ?? [],
            plot: item.overview ?? item.overviews?["eng"],
            posterURL: posterURL,
            artworkURLs: [posterURL].compactMap { $0 },
            imdbId: item.remoteIds?.first(where: { $0.sourceName == "IMDB" })?.id,
            providerName: name,
            confidence: 0.4, // Base confidence; resolver will re-score
            mediaType: mediaType
        )
    }

    private func mapSeriesDetail(_ detail: TVDBSeriesDetail?) -> MetadataResult? {
        guard let detail = detail else { return nil }

        let directors = detail.characters?
            .filter { $0.type == "Director" }
            .map(\.name) ?? []
        let cast = detail.characters?
            .filter { $0.type == "Actor" }
            .prefix(10)
            .map(\.name) ?? []

        let year = detail.firstAired.flatMap { extractYear(from: $0) }
        let posterURL = detail.artworks?
            .first(where: { $0.type == 2 })?.image ?? detail.image
        let backdropURL = detail.artworks?
            .first(where: { $0.type == 3 })?.image

        return MetadataResult(
            title: detail.name ?? "",
            originalTitle: detail.originalName,
            year: year,
            releaseDate: detail.firstAired,
            genre: detail.genres?.compactMap(\.name) ?? [],
            plot: detail.overview,
            director: directors.joined(separator: ", "),
            cast: Array(cast),
            rating: detail.score,
            ratingSource: "tvdb",
            runtimeMinutes: detail.averageRuntime,
            posterURL: posterURL,
            backdropURL: backdropURL,
            artworkURLs: detail.artworks?.compactMap(\.image) ?? [],
            providerName: name,
            confidence: 0.9,
            mediaType: .series,
            showTitle: detail.name
        )
    }

    private func mapMovieDetail(_ detail: TVDBMovieDetail?) -> MetadataResult? {
        guard let detail = detail else { return nil }

        let directors = detail.characters?
            .filter { $0.type == "Director" }
            .map(\.name) ?? []
        let cast = detail.characters?
            .filter { $0.type == "Actor" }
            .prefix(10)
            .map(\.name) ?? []

        let year = detail.year.flatMap { Int($0) }
        let posterURL = detail.artworks?
            .first(where: { $0.type == 2 })?.image ?? detail.image
        let backdropURL = detail.artworks?
            .first(where: { $0.type == 3 })?.image

        return MetadataResult(
            title: detail.name ?? "",
            originalTitle: detail.originalName,
            year: year,
            genre: detail.genres?.compactMap(\.name) ?? [],
            plot: detail.overview,
            director: directors.joined(separator: ", "),
            cast: Array(cast),
            rating: detail.score,
            ratingSource: "tvdb",
            runtimeMinutes: detail.runtime,
            posterURL: posterURL,
            backdropURL: backdropURL,
            artworkURLs: detail.artworks?.compactMap(\.image) ?? [],
            providerName: name,
            confidence: 0.9,
            mediaType: .movie
        )
    }

    // MARK: - Helpers

    private func extractYear(from dateString: String) -> Int? {
        guard dateString.count >= 4 else { return nil }
        return Int(dateString.prefix(4))
    }
}

// MARK: - TheTVDB API Response Models

private struct TVDBLoginResponse: Decodable {
    let status: String
    let data: TVDBLoginData
}

private struct TVDBLoginData: Decodable {
    let token: String
}

// MARK: - Search Models

private struct TVDBSearchResponse: Decodable {
    let data: [TVDBSearchItem]?
}

private struct TVDBSearchItem: Decodable {
    let objectID: String?
    let name: String?
    let originalName: String?
    let overview: String?
    let overviews: [String: String]?
    let translations: [String: String]?
    let year: String?
    let firstAirTime: String?
    let imageUrl: String?
    let thumbnail: String?
    let genres: [TVDBGenre]?
    let remoteIds: [TVDBRemoteId]?

    enum CodingKeys: String, CodingKey {
        case objectID
        case name
        case originalName = "original_name"
        case overview
        case overviews
        case translations
        case year
        case firstAirTime = "first_air_time"
        case imageUrl = "image_url"
        case thumbnail
        case genres
        case remoteIds = "remote_ids"
    }
}

private struct TVDBRemoteId: Decodable {
    let id: String?
    let type: Int?
    let sourceName: String?
}

private struct TVDBGenre: Decodable {
    let id: Int?
    let name: String?
}

// MARK: - Series Detail Models

private struct TVDBSeriesDetailResponse: Decodable {
    let data: TVDBSeriesDetail?
}

private struct TVDBSeriesDetail: Decodable {
    let id: Int?
    let name: String?
    let originalName: String?
    let overview: String?
    let firstAired: String?
    let image: String?
    let score: Double?
    let averageRuntime: Int?
    let genres: [TVDBGenre]?
    let characters: [TVDBCharacter]?
    let artworks: [TVDBArtwork]?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, image, score, genres, characters, artworks
        case originalName = "original_name"
        case firstAired = "firstAired"
        case averageRuntime = "averageRuntime"
    }
}

// MARK: - Movie Detail Models

private struct TVDBMovieDetailResponse: Decodable {
    let data: TVDBMovieDetail?
}

private struct TVDBMovieDetail: Decodable {
    let id: Int?
    let name: String?
    let originalName: String?
    let overview: String?
    let year: String?
    let image: String?
    let score: Double?
    let runtime: Int?
    let genres: [TVDBGenre]?
    let characters: [TVDBCharacter]?
    let artworks: [TVDBArtwork]?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, year, image, score, runtime, genres, characters, artworks
        case originalName = "original_name"
    }
}

// MARK: - Shared Detail Models

private struct TVDBCharacter: Decodable {
    let name: String
    let type: String?
    let peopleType: String?
}

private struct TVDBArtwork: Decodable {
    let id: Int?
    let image: String?
    let type: Int?
    let language: String?
}

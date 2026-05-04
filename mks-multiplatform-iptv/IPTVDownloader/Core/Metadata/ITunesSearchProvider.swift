import Foundation
import IPTVCore

/// Metadata provider using Apple's iTunes Search API.
///
/// Does not require an API key. Provides high-quality artwork URLs
/// and content advisory ratings. Best used as a secondary provider
/// to supplement TMDB data with Apple-specific metadata and artwork.
actor ITunesSearchProvider: MetadataProvider {
    nonisolated let name = "iTunes Search"

    private let session: URLSession
    private let baseURL = "https://itunes.apple.com/search"

    init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func isAvailable() -> Bool { true }

    // MARK: - Search

    func search(query: MetadataSearchQuery) async throws -> [MetadataResult] {
        var components = URLComponents(string: baseURL)!
        let entity: String
        switch query.mediaType {
        case .movie:
            entity = "movie"
        case .series, .episode:
            entity = "tvShow"
        }

        let cleanedTitle = StringSimilarity.cleanTitle(query.title)
        components.queryItems = [
            URLQueryItem(name: "term", value: cleanedTitle),
            URLQueryItem(name: "media", value: "movie"),
            URLQueryItem(name: "entity", value: entity),
            URLQueryItem(name: "country", value: "ES"),
            URLQueryItem(name: "limit", value: "10")
        ]

        guard let url = components.url else {
            throw MetadataError.parsingFailed("Invalid iTunes Search URL")
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MetadataError.providerUnavailable("iTunes Search")
        }

        let searchResponse = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return searchResponse.results.compactMap { item in
            mapSearchResult(item, mediaType: query.mediaType)
        }
    }

    /// iTunes does not support TMDB ID lookups
    func fetchById(tmdbId: Int, mediaType: MetadataMediaType) async throws -> MetadataResult? {
        nil
    }

    // MARK: - Mapping

    private func mapSearchResult(_ item: ITunesSearchItem, mediaType: MetadataMediaType) -> MetadataResult? {
        guard let trackName = item.trackName ?? item.collectionName else { return nil }

        let year: Int? = item.releaseDate.flatMap { dateString in
            guard dateString.count >= 4 else { return nil }
            return Int(dateString.prefix(4))
        }

        // iTunes artwork URLs use 100x100 by default; replace with high-res
        let artworkURL = item.artworkUrl100?
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
        let hiResArtwork = item.artworkUrl100?
            .replacingOccurrences(of: "100x100bb", with: "1200x1200bb")

        let genre = item.primaryGenreName.map { [$0] } ?? []
        let runtimeMinutes = item.trackTimeMillis.map { $0 / 60_000 }

        return MetadataResult(
            title: trackName,
            year: year,
            releaseDate: item.releaseDate,
            genre: genre,
            plot: item.longDescription ?? item.shortDescription,
            director: item.artistName,
            rating: nil,
            runtimeMinutes: runtimeMinutes,
            posterURL: artworkURL,
            artworkURLs: [artworkURL, hiResArtwork].compactMap { $0 },
            providerName: name,
            confidence: 0.4, // Base confidence; resolver will re-score
            mediaType: mediaType,
            itunesTrackId: item.trackId,
            contentAdvisoryRating: item.contentAdvisoryRating
        )
    }
}

// MARK: - iTunes API Response Models

private struct ITunesSearchResponse: Decodable {
    let resultCount: Int
    let results: [ITunesSearchItem]
}

private struct ITunesSearchItem: Decodable {
    let trackId: Int?
    let trackName: String?
    let collectionName: String?
    let artistName: String?
    let primaryGenreName: String?
    let releaseDate: String?
    let trackTimeMillis: Int?
    let artworkUrl100: String?
    let longDescription: String?
    let shortDescription: String?
    let contentAdvisoryRating: String?
}

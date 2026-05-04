//
//  IPTVService.swift
//  IPTVCore
//
//  Xtream Codes API client. Thread-safe via actor isolation.
//  Bound to a single IPTVProfile for the lifetime of the instance.
//

import Foundation

public enum IPTVAPIError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case decodingError
    case decodingFailure(DecodingError)
    case networkError(Error)
}

public actor IPTVService {
    private let client: RawHTTPClient
    public nonisolated let profile: IPTVProfile

    public init(profile: IPTVProfile, client: RawHTTPClient = .shared) {
        self.profile = profile
        self.client = client
    }

    // MARK: - Movies

    public func fetchMovies() async throws -> [Movie] {
        try await get(action: "get_vod_streams", as: [Movie].self)
    }

    public func fetchMovieDetails(vodId: Int) async throws -> MovieDetail {
        try await get(
            action: "get_vod_info",
            extraQuery: [URLQueryItem(name: "vod_id", value: String(vodId))],
            as: MovieDetail.self
        )
    }

    public func fetchMovieCategories() async throws -> [MovieCategory] {
        try await get(action: "get_vod_categories", as: [MovieCategory].self)
    }

    // MARK: - Series

    public func fetchSeries() async throws -> [Serie] {
        try await get(action: "get_series", as: [Serie].self)
    }

    public func fetchSeriesDetails(seriesId: Int) async throws -> SerieDetail {
        try await get(
            action: "get_series_info",
            extraQuery: [URLQueryItem(name: "series_id", value: String(seriesId))],
            as: SerieDetail.self
        )
    }

    public func fetchSeriesCategories() async throws -> [SeriesCategory] {
        try await get(action: "get_series_categories", as: [SeriesCategory].self)
    }

    // MARK: - Live

    public func fetchLiveChannels() async throws -> [LiveChannel] {
        try await get(action: "get_live_streams", as: [LiveChannel].self)
    }

    public func fetchLiveChannelsCategories() async throws -> [LiveChannelCategory] {
        try await get(action: "get_live_categories", as: [LiveChannelCategory].self)
    }

    // MARK: - Internals

    private func get<T: Decodable>(
        action: String,
        extraQuery: [URLQueryItem] = [],
        as type: T.Type
    ) async throws -> T {
        guard var components = URLComponents(string: profile.baseURL) else {
            throw IPTVAPIError.invalidURL
        }
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: action)
        ] + extraQuery

        guard let url = components.url else { throw IPTVAPIError.invalidURL }

        MKSLog.network.debug("IPTVService GET \(action)")

        let data: Data
        let response: RawHTTPResponse
        do {
            (data, response) = try await client.get(url)
        } catch {
            MKSLog.network.error("IPTVService transport error for \(action): \(error)")
            throw IPTVAPIError.networkError(error)
        }

        guard response.statusCode == 200 else {
            MKSLog.network.error("IPTVService HTTP \(response.statusCode) for \(action)")
            throw IPTVAPIError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            MKSLog.network.error("IPTVService decode failed for \(action): \(decodingError)")
            throw IPTVAPIError.decodingFailure(decodingError)
        }
    }
}

//
//  TVTMDBService.swift
//  mks-multiplataforma-tvos-iptv
//
//  Lightweight TMDB v3 API client for tvOS.
//  Uses URLSession (HTTPS to api.themoviedb.org – no ATS issue).
//  Results are cached via TVCacheManager with a 7-day freshness TTL.
//

import Foundation
import IPTVCore

// MARK: - TMDBEnrichment

/// Enriched metadata from The Movie Database.
/// Codable so it can be persisted via TVCacheManager.
struct TMDBEnrichment: Codable, Sendable {
    let tmdbId: Int
    let title: String?
    let posterURL: String?      // https://image.tmdb.org/t/p/w500{poster_path}
    let backdropURL: String?    // https://image.tmdb.org/t/p/w1280{backdrop_path}
    let plot: String?
    let genre: [String]
    let cast: [String]
    let director: String?
    let rating: Double?
    let year: Int?
    let imdbId: String?
    let runtimeMinutes: Int?
}

// MARK: - TVTMDBService

actor TVTMDBService {
    static let shared = TVTMDBService()

    private let session = URLSession.shared
    private let apiKey = "2825e3f7b4b9c3192e7e71b1d8043fed"
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p"

    private init() {}

    // MARK: - Public API

    /// Fetch full movie detail by exact TMDB ID.
    func fetchMovie(tmdbId: Int) async throws -> TMDBEnrichment {
        var components = URLComponents(string: "\(baseURL)/movie/\(tmdbId)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "append_to_response", value: "credits"),
            URLQueryItem(name: "language", value: "es-ES")
        ]
        let detail = try await fetch(TMDBMovieDetail.self, from: components)
        return mapMovie(detail)
    }

    /// Search for a movie by title and optional year, returns best match enrichment.
    func searchMovie(title: String, year: Int?) async throws -> TMDBEnrichment? {
        var components = URLComponents(string: "\(baseURL)/search/movie")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: "es-ES"),
            URLQueryItem(name: "page", value: "1")
        ]
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        components.queryItems = items

        let response = try await fetch(TMDBSearchResponse.self, from: components)
        guard let first = response.results.first else { return nil }

        // Do exact detail fetch for full credits
        return try await fetchMovie(tmdbId: first.id)
    }

    /// Fetch full TV series detail by exact TMDB ID.
    func fetchSerie(tmdbId: Int) async throws -> TMDBEnrichment {
        var components = URLComponents(string: "\(baseURL)/tv/\(tmdbId)")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "append_to_response", value: "credits"),
            URLQueryItem(name: "language", value: "es-ES")
        ]
        let detail = try await fetch(TMDBTVDetail.self, from: components)
        return mapTV(detail)
    }

    /// Search for a TV series by title and optional year, returns best match enrichment.
    func searchSerie(title: String, year: Int?) async throws -> TMDBEnrichment? {
        var components = URLComponents(string: "\(baseURL)/search/tv")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "language", value: "es-ES"),
            URLQueryItem(name: "page", value: "1")
        ]
        if let year { items.append(URLQueryItem(name: "first_air_date_year", value: String(year))) }
        components.queryItems = items

        let response = try await fetch(TMDBSearchResponse.self, from: components)
        guard let first = response.results.first else { return nil }

        return try await fetchSerie(tmdbId: first.id)
    }

    // MARK: - Private Helpers

    private func fetch<T: Decodable>(_ type: T.Type, from components: URLComponents) async throws -> T {
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func extractYear(from dateString: String?) -> Int? {
        guard let s = dateString, s.count >= 4 else { return nil }
        return Int(s.prefix(4))
    }

    // MARK: - Mapping

    private func mapMovie(_ d: TMDBMovieDetail) -> TMDBEnrichment {
        let directors = d.credits?.crew?
            .filter { $0.job?.lowercased() == "director" }
            .map(\.name) ?? []
        let cast = d.credits?.cast?.prefix(10).map(\.name) ?? []

        return TMDBEnrichment(
            tmdbId: d.id,
            title: d.title,
            posterURL: d.posterPath.map { "\(imageBase)/w500\($0)" },
            backdropURL: d.backdropPath.map { "\(imageBase)/w1280\($0)" },
            plot: d.overview,
            genre: d.genres.map(\.name),
            cast: Array(cast),
            director: directors.joined(separator: ", ").nilIfEmpty,
            rating: d.voteAverage,
            year: extractYear(from: d.releaseDate),
            imdbId: d.imdbId,
            runtimeMinutes: d.runtime
        )
    }

    private func mapTV(_ d: TMDBTVDetail) -> TMDBEnrichment {
        let creators = d.createdBy?.map(\.name) ?? []
        let cast = d.credits?.cast?.prefix(10).map(\.name) ?? []

        return TMDBEnrichment(
            tmdbId: d.id,
            title: d.name,
            posterURL: d.posterPath.map { "\(imageBase)/w500\($0)" },
            backdropURL: d.backdropPath.map { "\(imageBase)/w1280\($0)" },
            plot: d.overview,
            genre: d.genres.map(\.name),
            cast: Array(cast),
            director: creators.joined(separator: ", ").nilIfEmpty,
            rating: d.voteAverage,
            year: extractYear(from: d.firstAirDate),
            imdbId: nil,
            runtimeMinutes: d.episodeRunTime?.first
        )
    }
}

// MARK: - TMDB API Response Models (private)

private struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchItem]
}

private struct TMDBSearchItem: Decodable {
    let id: Int
}

private struct TMDBMovieDetail: Decodable {
    let id: Int
    let title: String
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
        case releaseDate  = "release_date"
        case voteAverage  = "vote_average"
        case posterPath   = "poster_path"
        case backdropPath = "backdrop_path"
        case imdbId       = "imdb_id"
    }
}

private struct TMDBTVDetail: Decodable {
    let id: Int
    let name: String
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
        case firstAirDate  = "first_air_date"
        case voteAverage   = "vote_average"
        case posterPath    = "poster_path"
        case backdropPath  = "backdrop_path"
        case episodeRunTime = "episode_run_time"
        case createdBy     = "created_by"
    }
}

private struct TMDBGenre: Decodable { let name: String }

private struct TMDBCredits: Decodable {
    let cast: [TMDBCastMember]?
    let crew: [TMDBCrewMember]?
}

private struct TMDBCastMember: Decodable { let name: String }
private struct TMDBCrewMember: Decodable { let name: String; let job: String? }
private struct TMDBCreator: Decodable { let name: String }

// MARK: - String Helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

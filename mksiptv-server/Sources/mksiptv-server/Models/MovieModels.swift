//
//  MovieModels.swift
//  mksiptv-server
//
//  Request/Response models for Movie management endpoints.
//

import Vapor
import IPTVCore

// MARK: - Response Models

/// Movie list item response
public struct MovieResponse: Content {
    public let id: Int
    public let name: String
    public let cover: String?
    public let rating: String?
    public let categoryId: String
    public let streamExtension: String?
    public let isAdult: Bool

    public init(
        id: Int,
        name: String,
        cover: String?,
        rating: String?,
        categoryId: String,
        streamExtension: String?,
        isAdult: Bool
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.rating = rating
        self.categoryId = categoryId
        self.streamExtension = streamExtension
        self.isAdult = isAdult
    }

    /// Create from Movie model
    public init(from movie: Movie) {
        self.id = movie.streamId
        self.name = movie.name
        self.cover = movie.streamIcon
        self.rating = movie.rating
        self.categoryId = movie.categoryId
        self.streamExtension = movie.containerExtension
        self.isAdult = movie.isAdult == "1"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cover
        case rating
        case categoryId
        case streamExtension = "extension"
        case isAdult
    }
}

/// Paginated movies list response
public struct MoviesListResponse: Content {
    public let movies: [MovieResponse]
    public let page: Int
    public let perPage: Int
    public let total: Int

    public init(movies: [MovieResponse], page: Int, perPage: Int, total: Int) {
        self.movies = movies
        self.page = page
        self.perPage = perPage
        self.total = total
    }
}

/// Movie detail response
public struct MovieDetailResponse: Content {
    public let id: Int
    public let name: String
    public let cover: String
    public let backdrop: String?
    public let plot: String
    public let genre: String
    public let cast: [String]
    public let director: String
    public let duration: String
    public let releaseDate: String
    public let rating: String?
    public let youtubeTrailer: String?
    public let backdropPaths: [String]?

    public init(
        id: Int,
        name: String,
        cover: String,
        backdrop: String?,
        plot: String,
        genre: String,
        cast: [String],
        director: String,
        duration: String,
        releaseDate: String,
        rating: String?,
        youtubeTrailer: String?,
        backdropPaths: [String]?
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.backdrop = backdrop
        self.plot = plot
        self.genre = genre
        self.cast = cast
        self.director = director
        self.duration = duration
        self.releaseDate = releaseDate
        self.rating = rating
        self.youtubeTrailer = youtubeTrailer
        self.backdropPaths = backdropPaths
    }

    /// Create from MovieDetail model
    public init(from detail: MovieDetail) {
        self.id = detail.movieData.streamId
        self.name = detail.movieData.name
        self.cover = detail.movieImage
        self.backdrop = detail.backdrop
        self.plot = detail.plot
        self.genre = detail.genre
        self.cast = detail.cast
        self.director = detail.director
        self.duration = detail.duration
        self.releaseDate = detail.releaseDate
        self.rating = detail.rating
        self.youtubeTrailer = detail.youtubeTrailer
        self.backdropPaths = detail.backdropPath
    }
}

/// Stream URL response
public struct StreamURLResponse: Content {
    public let movieId: Int
    public let url: String
    public let streamExtension: String
    public let headers: [String: String]?

    public init(movieId: Int, url: String, streamExtension: String, headers: [String: String]? = nil) {
        self.movieId = movieId
        self.url = url
        self.streamExtension = streamExtension
        self.headers = headers
    }

    enum CodingKeys: String, CodingKey {
        case movieId
        case url
        case streamExtension = "extension"
        case headers
    }
}

/// Category response
public struct CategoryResponse: Content {
    public let id: String
    public let name: String
    public let parentId: Int

    public init(id: String, name: String, parentId: Int) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }

    /// Create from MovieCategory model
    public init(from category: MovieCategory) {
        self.id = category.categoryId
        self.name = category.categoryName
        self.parentId = category.parentId
    }
}

// MARK: - Query Parameters

/// Movies list query parameters
public struct MoviesQuery: Content {
    public let category: String?
    public let search: String?
    public let limit: Int?
    public let offset: Int?
    public let sort: String?

    public init(category: String? = nil, search: String? = nil, limit: Int? = nil, offset: Int? = nil, sort: String? = nil) {
        self.category = category
        self.search = search
        self.limit = limit
        self.offset = offset
        self.sort = sort
    }

    /// Default values
    public var defaultLimit: Int { limit ?? 50 }
    public var defaultOffset: Int { offset ?? 0 }
    public var sortField: SortField { SortField(rawValue: sort ?? "name") ?? .name }

    public enum SortField: String {
        case name
        case added
        case rating
    }
}

// MARK: - Error Responses

/// Movie error response
public struct MovieErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Movie Error Types

public enum MovieError: String {
    case notFound = "MOVIE_NOT_FOUND"
    case noActiveProfile = "NO_ACTIVE_PROFILE"
    case upstreamError = "UPSTREAM_ERROR"
    case invalidParameter = "INVALID_PARAMETER"
}

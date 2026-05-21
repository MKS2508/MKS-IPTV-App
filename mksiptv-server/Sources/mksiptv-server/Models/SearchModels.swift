//
//  SearchModels.swift
//  mksiptv-server
//
//  Request/Response models for unified search endpoints.
//

import Vapor
import IPTVCore

// MARK: - Response Models

/// Unified search result across all media types
public struct SearchResult: Content {
    public let id: Int
    public let name: String
    public let type: MediaType
    public let icon: String?
    public let categoryId: String?
    public let categoryName: String?
    public let rating: String?

    // For movies/series
    public let streamId: Int?

    // For live channels
    public let channelNumber: Int?

    public init(
        id: Int,
        name: String,
        type: MediaType,
        icon: String? = nil,
        categoryId: String? = nil,
        categoryName: String? = nil,
        rating: String? = nil,
        streamId: Int? = nil,
        channelNumber: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.rating = rating
        self.streamId = streamId
        self.channelNumber = channelNumber
    }

    /// Create from Movie
    public init(from movie: Movie, categoryName: String? = nil) {
        self.init(
            id: movie.streamId,
            name: movie.name,
            type: .movie,
            icon: movie.streamIcon,
            categoryId: movie.categoryId,
            categoryName: categoryName,
            rating: movie.rating,
            streamId: movie.streamId,
            channelNumber: nil
        )
    }

    /// Create from Series
    public init(from series: Serie, categoryName: String? = nil) {
        self.init(
            id: series.seriesId,
            name: series.name,
            type: .series,
            icon: series.cover,
            categoryId: series.categoryId,
            categoryName: categoryName,
            rating: series.rating,
            streamId: series.seriesId,
            channelNumber: nil
        )
    }

    /// Create from LiveChannel
    public init(from channel: LiveChannel, categoryName: String? = nil) {
        self.init(
            id: channel.streamId,
            name: channel.name,
            type: .liveChannel,
            icon: channel.streamIcon,
            categoryId: channel.categoryId,
            categoryName: categoryName,
            rating: nil,
            streamId: nil,
            channelNumber: channel.num
        )
    }
}

/// Unified search response with results and metadata
public struct SearchResponse: Content {
    public let query: String
    public let total: Int
    public let results: [SearchResult]
    public let counts: [String: Int]

    public init(
        query: String,
        total: Int,
        results: [SearchResult],
        counts: [String: Int]
    ) {
        self.query = query
        self.total = total
        self.results = results
        self.counts = counts
    }

    /// Helper to get count for specific media type
    public func count(for type: MediaType) -> Int {
        return counts[type.rawValue] ?? 0
    }
}

// MARK: - Query Parameters

/// Search query parameters
public struct SearchQuery: Content {
    public let q: String?
    public let type: String?
    public let limit: Int?
    public let offset: Int?

    public init(q: String? = nil, type: String? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.q = q
        self.type = type
        self.limit = limit
        self.offset = offset
    }

    /// Default values
    public var defaultLimit: Int { limit ?? 50 }
    public var defaultOffset: Int { offset ?? 0 }

    /// Validate and parse media type filter
    public func mediaType() -> MediaType? {
        guard let typeString = type, !typeString.isEmpty else {
            return nil
        }

        // Try exact match first
        if let mediaType = MediaType(rawValue: typeString) {
            return mediaType
        }

        // Try case-insensitive match
        switch typeString.lowercased() {
        case "movie", "movies":
            return .movie
        case "series", "serie":
            return .series
        case "live_channel", "livechannel", "live", "channel":
            return .liveChannel
        default:
            return nil
        }
    }

    /// Validate required parameters
    public func validate() throws {
        guard let query = q, !query.isEmpty else {
            throw Abort(.badRequest, reason: "MISSING_QUERY: q parameter is required")
        }

        // Validate type if provided
        if let typeString = type, !typeString.isEmpty {
            if mediaType() == nil {
                throw Abort(.unprocessableEntity, reason: "INVALID_TYPE: type must be one of: movie, series, live_channel")
            }
        }
    }
}

// MARK: - Error Responses

/// Search error response
public struct SearchErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Search Error Types

public enum SearchError: String {
    case missingQuery = "MISSING_QUERY"
    case invalidType = "INVALID_TYPE"
    case noActiveProfile = "NO_ACTIVE_PROFILE"
    case upstreamError = "UPSTREAM_ERROR"
}

//
//  SearchRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for unified search functionality.
//

import Vapor
import IPTVCore

// MARK: - Search Routes Collection

/// Unified search routes across all media types
public struct SearchRoutes: RouteCollection {
    private let profileStore: ProfileStore
    private let searchService: SearchService

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
        self.searchService = SearchService(profileStore: profileStore)
    }

    public func boot(routes: RoutesBuilder) throws {
        // Main search endpoint
        routes.get("search", use: searchHandler)

        // Search suggestions endpoint
        routes.get("search", "suggestions", use: suggestionsHandler)
    }

    // MARK: - Endpoint Handlers

    /// GET /search?q={query}&type={type}&limit={limit}&offset={offset}
    /// Unified search across movies, series, and live channels
    func searchHandler(req: Request) async throws -> SearchResponse {
        // Parse and validate query parameters
        let query = req.query[String.self, at: "q"]
        let type = req.query[String.self, at: "type"]
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 50
        let offset = (try? req.query.get(Int.self, at: "offset")) ?? 0

        MKSLog.api.debug("Search request - query: \(query ?? "nil"), type: \(type ?? "all"), limit: \(limit), offset: \(offset)")

        // Validate required parameters
        guard let searchQuery = query, !searchQuery.isEmpty else {
            MKSLog.api.warning("Search request missing required 'q' parameter")
            throw Abort(.badRequest, reason: "MISSING_QUERY: q parameter is required")
        }

        // Validate and parse media type filter
        let mediaType: MediaType?
        if let typeString = type, !typeString.isEmpty {
            switch typeString.lowercased() {
            case "movie", "movies":
                mediaType = .movie
            case "series", "serie":
                mediaType = .series
            case "live_channel", "livechannel", "live", "channel":
                mediaType = .liveChannel
            default:
                MKSLog.api.warning("Search request with invalid type: \(typeString)")
                throw Abort(.unprocessableEntity, reason: "INVALID_TYPE: type must be one of: movie, series, live_channel")
            }
        } else {
            mediaType = nil
        }

        // Validate pagination parameters
        let validatedLimit = min(max(limit, 1), 200) // Cap at 200
        let validatedOffset = max(offset, 0)

        do {
            // Perform search
            let response = try await searchService.search(
                query: searchQuery,
                type: mediaType,
                limit: validatedLimit,
                offset: validatedOffset
            )

            MKSLog.api.info("Search successful - query: '\(searchQuery)', total results: \(response.total), returned: \(response.results.count)")

            return response

        } catch let abort as Abort {
            // Re-throw Abort errors as-is
            throw abort
        } catch {
            MKSLog.api.error("Search failed with error: \(error)")
            throw Abort(.internalServerError, reason: "SEARCH_FAILED: \(error.localizedDescription)")
        }
    }

    /// GET /search/suggestions?q={query}&type={type}&limit={limit}
    /// Get search suggestions based on partial query
    func suggestionsHandler(req: Request) async throws -> [SearchResult] {
        // Parse and validate query parameters
        let query = req.query[String.self, at: "q"]
        let type = req.query[String.self, at: "type"]
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 5

        MKSLog.api.debug("Suggestions request - query: \(query ?? "nil"), type: \(type ?? "all"), limit: \(limit)")

        // Validate required parameters
        guard let searchQuery = query, !searchQuery.isEmpty else {
            MKSLog.api.warning("Suggestions request missing required 'q' parameter")
            throw Abort(.badRequest, reason: "MISSING_QUERY: q parameter is required")
        }

        // Validate and parse media type filter
        let mediaType: MediaType?
        if let typeString = type, !typeString.isEmpty {
            switch typeString.lowercased() {
            case "movie", "movies":
                mediaType = .movie
            case "series", "serie":
                mediaType = .series
            case "live_channel", "livechannel", "live", "channel":
                mediaType = .liveChannel
            default:
                MKSLog.api.warning("Suggestions request with invalid type: \(typeString)")
                throw Abort(.unprocessableEntity, reason: "INVALID_TYPE: type must be one of: movie, series, live_channel")
            }
        } else {
            mediaType = nil
        }

        // Validate limit
        let validatedLimit = min(max(limit, 1), 20) // Cap at 20 for suggestions

        do {
            // Get suggestions
            let suggestions = try await searchService.suggestions(
                query: searchQuery,
                type: mediaType,
                limit: validatedLimit
            )

            MKSLog.api.info("Suggestions successful - query: '\(searchQuery)', returned: \(suggestions.count)")

            return suggestions

        } catch let abort as Abort {
            // Re-throw Abort errors as-is
            throw abort
        } catch {
            MKSLog.api.error("Suggestions failed with error: \(error)")
            throw Abort(.internalServerError, reason: "SUGGESTIONS_FAILED: \(error.localizedDescription)")
        }
    }
}

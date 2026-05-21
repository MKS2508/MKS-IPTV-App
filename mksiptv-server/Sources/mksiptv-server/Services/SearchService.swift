//
//  SearchService.swift
//  mksiptv-server
//
//  Unified search service across Movies, Series, and Live Channels.
//

import Vapor
import IPTVCore

// MARK: - Search Service

/// Unified search service that aggregates results from all media types
public actor SearchService {
    private let profileStore: ProfileStore

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    /// Perform unified search across all media types
    /// - Parameters:
    ///   - query: Search term
    ///   - type: Optional media type filter
    ///   - limit: Maximum number of results to return
    ///   - offset: Number of results to skip
    /// - Returns: SearchResponse with aggregated results
    public func search(
        query: String,
        type: MediaType? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SearchResponse {
        MKSLog.api.debug("Performing unified search - query: '\(query)', type: \(type?.rawValue ?? "all"), limit: \(limit), offset: \(offset)")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found for search")
            throw Abort(.badRequest, reason: "No active profile found")
        }

        let service = IPTVService(profile: profile)
        var allResults: [SearchResult] = []
        var counts: [String: Int] = [
            MediaType.movie.rawValue: 0,
            MediaType.series.rawValue: 0,
            MediaType.liveChannel.rawValue: 0
        ]

        // Only search types that match the filter (or all if no filter)
        let shouldSearchMovies = type == nil || type == .movie
        let shouldSearchSeries = type == nil || type == .series
        let shouldSearchChannels = type == nil || type == .liveChannel

        // Search movies
        if shouldSearchMovies {
            do {
                let movies = try await service.fetchMovies()
                let filtered = movies.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }

                // Fetch categories for names (optional, if we want to include them)
                // For now, we'll skip category names to avoid extra API calls
                let movieResults = filtered.map { SearchResult(from: $0) }
                allResults.append(contentsOf: movieResults)
                counts[MediaType.movie.rawValue] = filtered.count

                MKSLog.api.debug("Found \(filtered.count) movies matching '\(query)'")
            } catch {
                MKSLog.api.error("Failed to search movies: \(error)")
                // Continue with other types even if one fails
            }
        }

        // Search series
        if shouldSearchSeries {
            do {
                let series = try await service.fetchSeries()
                let filtered = series.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }

                let seriesResults = filtered.map { SearchResult(from: $0) }
                allResults.append(contentsOf: seriesResults)
                counts[MediaType.series.rawValue] = filtered.count

                MKSLog.api.debug("Found \(filtered.count) series matching '\(query)'")
            } catch {
                MKSLog.api.error("Failed to search series: \(error)")
                // Continue with other types even if one fails
            }
        }

        // Search live channels
        if shouldSearchChannels {
            do {
                let channels = try await service.fetchLiveChannels()
                let filtered = channels.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                }

                let channelResults = filtered.map { SearchResult(from: $0) }
                allResults.append(contentsOf: channelResults)
                counts[MediaType.liveChannel.rawValue] = filtered.count

                MKSLog.api.debug("Found \(filtered.count) channels matching '\(query)'")
            } catch {
                MKSLog.api.error("Failed to search live channels: \(error)")
                // Continue with other types even if one fails
            }
        }

        // Sort results by relevance (exact match first, then starts with, then contains)
        allResults.sort { result1, result2 in
            let name1 = result1.name.lowercased()
            let name2 = result2.name.lowercased()
            let queryLower = query.lowercased()

            // Exact match first
            let exact1 = name1 == queryLower
            let exact2 = name2 == queryLower
            if exact1 && !exact2 { return true }
            if !exact1 && exact2 { return false }

            // Then starts with
            let starts1 = name1.hasPrefix(queryLower)
            let starts2 = name2.hasPrefix(queryLower)
            if starts1 && !starts2 { return true }
            if !starts1 && starts2 { return false }

            // Finally alphabetical
            return name1 < name2
        }

        // Apply pagination
        let total = allResults.count
        let startIndex = min(offset, total)
        let endIndex = min(offset + limit, total)
        let paginatedResults = Array(allResults[startIndex..<endIndex])

        MKSLog.api.info("Search complete - total results: \(total), returning: \(paginatedResults.count)")

        return SearchResponse(
            query: query,
            total: total,
            results: paginatedResults,
            counts: counts
        )
    }

    /// Get search suggestions based on partial query
    /// - Parameters:
    ///   - query: Partial search term
    ///   - type: Optional media type filter
    ///   - limit: Maximum suggestions per type
    /// - Returns: Array of search result suggestions
    public func suggestions(
        query: String,
        type: MediaType? = nil,
        limit: Int = 5
    ) async throws -> [SearchResult] {
        MKSLog.api.debug("Getting search suggestions - query: '\(query)', type: \(type?.rawValue ?? "all")")

        // Reuse search with higher limit and get first results
        let response = try await search(
            query: query,
            type: type,
            limit: limit * 3, // Get more to have better suggestions
            offset: 0
        )

        // Return top results as suggestions
        return Array(response.results.prefix(limit))
    }
}

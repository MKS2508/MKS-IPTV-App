//
//  SerieRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for Series management.
//

import Vapor
import IPTVCore

// MARK: - Series Routes Collection

/// Series management routes
public struct SerieRoutes: RouteCollection {
    private let profileStore: ProfileStore

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    public func boot(routes: RoutesBuilder) throws {
        // Grouped routes under /series
        let series = routes.grouped("series")

        // List and category endpoints
        series.get(use: listSeries)
        series.get("categories", use: listSeriesCategories)

        // Individual series routes
        series.get(":id", use: getSerieDetail)
        series.get(":id", "seasons", ":seasonNumber", use: getSeasonEpisodes)
        series.get(":id", "stream-url", use: getEpisodeStreamURL)
    }

    // MARK: - Endpoint Handlers

    /// GET /series - List series (with optional category filter and pagination)
    func listSeries(req: Request) async throws -> SeriesListResponse {
        MKSLog.api.debug("Listing series")

        // Parse query parameters
        let category: String? = req.query["category"]
        let page: String = req.query["page"] ?? "1"
        let limit: String = req.query["limit"] ?? "20"
        let currentPage = Int(page) ?? 1
        let limitValue = Int(limit) ?? 20

        // Get active profile
        guard let activeProfile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.badRequest, reason: "No active profile. Please activate a profile first.")
        }

        // Fetch series from IPTV service
        let service = IPTVService(profile: activeProfile)
        let allSeries = try await service.fetchSeries()

        MKSLog.api.info("Fetched \(allSeries.count) series from IPTV API")

        // Filter by category if provided
        var filteredSeries = allSeries
        if let categoryId = category {
            filteredSeries = allSeries.filter { $0.categoryId == categoryId }
            MKSLog.api.debug("Filtered to \(filteredSeries.count) series in category \(categoryId)")
        }

        // Paginate
        let startIndex = (currentPage - 1) * limitValue
        let endIndex = min(startIndex + limitValue, filteredSeries.count)
        let paginatedSeries = startIndex < filteredSeries.count
            ? Array(filteredSeries[startIndex..<endIndex])
            : []

        let totalPages = (filteredSeries.count + limitValue - 1) / limitValue

        let responses = paginatedSeries.map { SerieResponse(from: $0) }

        return SeriesListResponse(
            series: responses,
            page: currentPage,
            totalPages: totalPages,
            totalItems: filteredSeries.count
        )
    }

    /// GET /series/categories - List series categories
    func listSeriesCategories(req: Request) async throws -> [SeriesCategoryResponse] {
        MKSLog.api.debug("Listing series categories")

        // Get active profile
        guard let activeProfile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.badRequest, reason: "No active profile. Please activate a profile first.")
        }

        // Fetch categories from IPTV service
        let service = IPTVService(profile: activeProfile)
        let categories = try await service.fetchSeriesCategories()

        MKSLog.api.info("Fetched \(categories.count) series categories from IPTV API")

        return categories.map { SeriesCategoryResponse(from: $0) }
    }

    /// GET /series/:id - Get series detail with seasons
    func getSerieDetail(req: Request) async throws -> SerieDetailResponse {
        guard let idString = req.parameters.get("id"),
              let seriesId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid series ID format")
        }

        MKSLog.api.debug("Fetching series detail: \(idString)")

        // Get active profile
        guard let activeProfile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.badRequest, reason: "No active profile. Please activate a profile first.")
        }

        // Fetch series details from IPTV service
        let service = IPTVService(profile: activeProfile)
        let detail = try await service.fetchSeriesDetails(seriesId: seriesId)

        MKSLog.api.info("Fetched series detail for \(seriesId): \(detail.info.name)")

        return SerieDetailResponse(from: detail, seriesId: seriesId)
    }

    /// GET /series/:id/seasons/:seasonNumber - Get episodes for a specific season
    func getSeasonEpisodes(req: Request) async throws -> EpisodesResponse {
        guard let idString = req.parameters.get("id"),
              let seriesId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid series ID format")
        }

        guard let seasonString = req.parameters.get("seasonNumber"),
              let seasonNumber = Int(seasonString) else {
            throw Abort(.badRequest, reason: "Invalid season number format")
        }

        MKSLog.api.debug("Fetching episodes for series \(idString), season \(seasonString)")

        // Get active profile
        guard let activeProfile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.badRequest, reason: "No active profile. Please activate a profile first.")
        }

        // Fetch series details from IPTV service
        let service = IPTVService(profile: activeProfile)
        let detail = try await service.fetchSeriesDetails(seriesId: seriesId)

        // Find episodes for the requested season
        let seasonKey = String(seasonNumber)
        guard let episodes = detail.episodes[seasonKey], !episodes.isEmpty else {
            MKSLog.api.warning("Season \(seasonString) not found for series \(idString)")
            throw Abort(.notFound, reason: "Season \(seasonString) does not exist for this series")
        }

        MKSLog.api.info("Found \(episodes.count) episodes for season \(seasonString)")

        let responses = episodes.map { EpisodeResponse(from: $0) }

        return EpisodesResponse(
            seriesId: seriesId,
            seasonNumber: seasonNumber,
            episodes: responses
        )
    }

    /// GET /series/:id/stream-url?season=1&episode=3 - Get streaming URL for specific episode
    func getEpisodeStreamURL(req: Request) async throws -> EpisodeStreamURLResponse {
        guard let idString = req.parameters.get("id"),
              let seriesId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid series ID format")
        }

        guard let seasonString: String = req.query["season"],
              let seasonNumber = Int(seasonString) else {
            throw Abort(.badRequest, reason: "Missing or invalid 'season' query parameter")
        }

        guard let episodeString: String = req.query["episode"],
              let episodeNumber = Int(episodeString) else {
            throw Abort(.badRequest, reason: "Missing or invalid 'episode' query parameter")
        }

        MKSLog.api.debug("Fetching stream URL for series \(idString), S\(seasonString)E\(episodeString)")

        // Get active profile
        guard let activeProfile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.badRequest, reason: "No active profile. Please activate a profile first.")
        }

        // Fetch series details from IPTV service
        let service = IPTVService(profile: activeProfile)
        let detail = try await service.fetchSeriesDetails(seriesId: seriesId)

        // Find the requested season
        let seasonKey = String(seasonNumber)
        guard let episodes = detail.episodes[seasonKey], !episodes.isEmpty else {
            MKSLog.api.warning("Season \(seasonString) not found for series \(idString)")
            throw Abort(.notFound, reason: "Season \(seasonString) does not exist for this series")
        }

        // Find the requested episode
        guard let episode = episodes.first(where: { $0.episodeNum == episodeNumber }) else {
            MKSLog.api.warning("Episode \(episodeString) not found in season \(seasonString)")
            throw Abort(.notFound, reason: "Episode S\(seasonString)E\(episodeString) not found")
        }

        // Build stream URL
        let streamId = Int(episode.id) ?? 0
        let streamURL = "\(activeProfile.baseURL)/series/\(activeProfile.username)/\(activeProfile.password)/\(streamId).\(episode.containerExtension)"

        MKSLog.api.info("Generated stream URL for episode \(episodeString): \(streamURL)")

        return EpisodeStreamURLResponse(
            seriesId: seriesId,
            season: seasonNumber,
            episode: episodeNumber,
            episodeStreamId: streamId,
            url: streamURL,
            containerExtension: episode.containerExtension
        )
    }
}

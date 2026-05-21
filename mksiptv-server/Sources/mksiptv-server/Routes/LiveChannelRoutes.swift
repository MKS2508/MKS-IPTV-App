//
//  LiveChannelRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for live channel management.
//

import Vapor
import IPTVCore

// MARK: - Live Channel Routes Collection

/// Live channel management routes
public struct LiveChannelRoutes: RouteCollection {
    private let profileStore: ProfileStore

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    public func boot(routes: RoutesBuilder) throws {
        // Grouped routes under /live-channels
        let liveChannels = routes.grouped("live-channels")

        // List and filter endpoints
        liveChannels.get(use: listChannels)
        liveChannels.get("categories", use: listCategories)

        // Individual channel routes (before :id to avoid conflicts)
        liveChannels.get(":id", use: getChannelDetail)
        liveChannels.get(":id", "stream-url", use: getStreamURL)
        liveChannels.get(":id", "epg", use: getChannelEPG)
    }

    // MARK: - Endpoint Handlers

    /// GET /live-channels - List all channels with optional filters
    func listChannels(req: Request) async throws -> ChannelsListResponse {
        MKSLog.api.debug("Listing live channels")

        // Get active profile
        let profile = try await getActiveProfile()

        // Fetch channels from IPTV service
        let service = IPTVService(profile: profile)
        let channels = try await service.fetchLiveChannels()

        // Apply query filters
        var filteredChannels = channels

        // Filter by category
        if let category = req.query[String.self, at: "category"] {
            MKSLog.api.debug("Filtering by category: \(category)")
            filteredChannels = filteredChannels.filter { $0.categoryId == category }
        }

        // Search by name
        if let search = req.query[String.self, at: "search"] {
            MKSLog.api.debug("Searching: \(search)")
            let searchTerm = search.lowercased()
            filteredChannels = filteredChannels.filter {
                $0.name.lowercased().contains(searchTerm)
            }
        }

        // Convert to response models
        let responses = filteredChannels.map { LiveChannelResponse(from: $0) }

        return ChannelsListResponse(
            channels: responses,
            page: 1,
            totalPages: nil,
            totalChannels: channels.count
        )
    }

    /// GET /live-channels/categories - List all categories
    func listCategories(req: Request) async throws -> [LiveChannelCategoryResponse] {
        MKSLog.api.debug("Listing live channel categories")

        // Get active profile
        let profile = try await getActiveProfile()

        // Fetch categories from IPTV service
        let service = IPTVService(profile: profile)
        let categories = try await service.fetchLiveChannelsCategories()

        // Convert to response models
        return categories.map { LiveChannelCategoryResponse(from: $0) }
    }

    /// GET /live-channels/:id - Get channel details
    func getChannelDetail(req: Request) async throws -> LiveChannelDetailResponse {
        guard let idString = req.parameters.get("id"),
              let channelId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid channel ID format")
        }

        MKSLog.api.debug("Fetching channel detail: \(idString)")

        // Get active profile
        let profile = try await getActiveProfile()

        // Fetch channels from IPTV service
        let service = IPTVService(profile: profile)
        let channels = try await service.fetchLiveChannels()

        // Find requested channel
        guard let channel = channels.first(where: { $0.streamId == channelId }) else {
            throw Abort(.notFound, reason: "Channel with id \(idString) not found")
        }

        return LiveChannelDetailResponse(from: channel)
    }

    /// GET /live-channels/:id/stream-url - Get stream URL for channel
    func getStreamURL(req: Request) async throws -> LiveStreamURLResponse {
        guard let idString = req.parameters.get("id"),
              let channelId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid channel ID format")
        }

        MKSLog.api.debug("Fetching stream URL for channel: \(idString)")

        // Get active profile
        let profile = try await getActiveProfile()

        // Verify channel exists
        let service = IPTVService(profile: profile)
        let channels = try await service.fetchLiveChannels()

        guard channels.contains(where: { $0.streamId == channelId }) else {
            throw Abort(.notFound, reason: "Channel with id \(idString) not found")
        }

        // Build stream URL using IPTVConfiguration
        let streamURL = IPTVConfiguration.buildLiveChannelURL(
            profile: profile,
            channelID: channelId
        )

        let headers = IPTVConfiguration.defaultRequestHeaders()

        return LiveStreamURLResponse(
            channelId: channelId,
            url: streamURL,
            headers: headers
        )
    }

    /// GET /live-channels/:id/epg - Get EPG for channel
    func getChannelEPG(req: Request) async throws -> LiveChannelEPGResponse {
        guard let idString = req.parameters.get("id"),
              let channelId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid channel ID format")
        }

        MKSLog.api.debug("Fetching EPG for channel: \(idString)")

        // Get active profile
        let profile = try await getActiveProfile()

        // Verify channel exists
        let service = IPTVService(profile: profile)
        let channels = try await service.fetchLiveChannels()

        guard channels.contains(where: { $0.streamId == channelId }) else {
            throw Abort(.notFound, reason: "Channel with id \(idString) not found")
        }

        // EPG fetching is out of scope for this ticket
        // Return empty response with channel ID
        MKSLog.api.debug("EPG not implemented yet, returning empty programmes list")

        return LiveChannelEPGResponse(
            channelId: channelId,
            programmes: []
        )
    }

    // MARK: - Helpers

    /// Get active profile or throw error
    private func getActiveProfile() async throws -> IPTVProfile {
        guard let profile = try await profileStore.getActiveProfile() else {
            MKSLog.api.error("No active profile found")
            throw Abort(.serviceUnavailable, reason: "No active profile. Please activate a profile first.")
        }
        return profile
    }
}

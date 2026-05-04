//
//  LiveChannelEPGService.swift
//  mks-multiplatform-iptv
//
//  Actor-based service that coordinates EPG data for Live TV channels.
//  Provides caching, batch preloading, and thread-safe access.
//

import Foundation
import os
import IPTVCore

// MARK: - Live Channel EPG Service

/// Actor that coordinates EPG data fetching and caching for Live TV channels.
/// Provides batch preloading for visible channels and maintains a cache with TTL.
actor LiveChannelEPGService {
    // MARK: - Configuration

    /// Cache time-to-live in seconds (60 seconds default)
    private let cacheTTL: TimeInterval = 60

    // MARK: - Dependencies

    private let epgService: EPGService
    private let logger = Logger(subsystem: "LiveChannelEPGService", category: "EPG")

    // MARK: - State

    /// Cache of display models by stream ID
    private var displayModelCache: [Int: LiveChannelDisplayModel] = [:]

    /// Cache timestamps for invalidation
    private var cacheTimestamps: [Int: Date] = [:]

    /// Whether EPG has been loaded
    private var isEPGLoaded = false

    /// Set of preloaded stream IDs
    private var preloadedIds: Set<Int> = []

    // MARK: - Initialization

    init() {
        self.epgService = EPGService()
    }

    /// Preloads EPG for visible channels
    /// - Parameter channels: Dictionary of stream ID to LiveChannel for preload
    func preloadEPG(for channels: [Int: LiveChannel]) async {
        guard isEPGLoaded else {
            logger.debug("EPG not loaded, skipping preload")
            return
        }

        let idsToPreload = channels.keys.filter { !preloadedIds.contains($0) }
        guard !idsToPreload.isEmpty else { return }

        logger.debug("Preloading EPG for \(idsToPreload.count) channels")

        for streamId in idsToPreload {
            // This will cache the display model
            if let channel = channels[streamId] {
                _ = await getDisplayModel(for: channel, isFavorite: false)
                preloadedIds.insert(streamId)
            }
        }

        logger.debug("Preload complete for \(idsToPreload.count) channels")
    }

    // MARK: - Public API

    /// Loads EPG data and builds match table for the given channels
    /// - Parameter liveChannels: Array of live channels to match with EPG
    /// - Throws: EPGError if loading fails
    func loadEPGAndBuildMatchTable(liveChannels: [LiveChannel]) async throws {
        logger.info("Loading EPG data for \(liveChannels.count) channels...")

        do {
            try await epgService.loadEPG()
            await epgService.buildMatchTable(liveChannels: liveChannels)
            isEPGLoaded = true
            logger.info("EPG loaded and match table built successfully")
        } catch {
            logger.error("Failed to load EPG: \(error.localizedDescription)")
            throw error
        }
    }

    /// Gets or creates a cached display model for a channel
    /// - Parameters:
    ///   - channel: The live channel
    ///   - isFavorite: Whether the channel is a favorite
    /// - Returns: A display model with EPG data if available
    func getDisplayModel(for channel: LiveChannel, isFavorite: Bool) async -> LiveChannelDisplayModel {
        let streamId = channel.streamId

        // Check cache
        if let cached = displayModelCache[streamId], !isCacheExpired(for: streamId) {
            // Update favorite status if changed
            if cached.isFavorite != isFavorite {
                return LiveChannelDisplayModel(
                    channel: cached.channel,
                    currentProgramme: cached.currentProgramme,
                    upcomingProgrammes: cached.upcomingProgrammes,
                    isFavorite: isFavorite
                )
            }
            return cached
        }

        // Build new display model
        let model = await buildDisplayModel(for: channel, isFavorite: isFavorite)

        // Cache it
        displayModelCache[streamId] = model
        cacheTimestamps[streamId] = Date()

        return model
    }

    /// Gets display model by stream ID (requires prior channel data)
    /// - Parameter streamId: The channel's stream ID
    /// - Returns: Cached display model or nil
    func getCachedDisplayModel(for streamId: Int) -> LiveChannelDisplayModel? {
        guard !isCacheExpired(for: streamId) else {
            displayModelCache[streamId] = nil
            cacheTimestamps[streamId] = nil
            return nil
        }
        return displayModelCache[streamId]
    }

    /// Gets current programme for a channel
    /// - Parameter streamId: The channel's stream ID
    /// - Returns: Current programme if available
    func getCurrentProgramme(for streamId: Int) async -> EPGProgramme? {
        guard isEPGLoaded else { return nil }
        return await epgService.currentProgramme(for: streamId)
    }

    /// Gets upcoming programmes for a channel
    /// - Parameters:
    ///   - streamId: The channel's stream ID
    ///   - limit: Maximum number of programmes to return
    /// - Returns: Array of upcoming programmes
    func getUpcomingProgrammes(for streamId: Int, limit: Int = 5) async -> [EPGProgramme] {
        guard isEPGLoaded else { return [] }
        return await epgService.upcomingProgrammes(for: streamId, limit: limit)
    }

    /// Whether EPG data is available
    var isEPGAvailable: Bool {
        isEPGLoaded
    }

    /// Clears the EPG cache
    func clearCache() {
        displayModelCache.removeAll()
        cacheTimestamps.removeAll()
        preloadedIds.removeAll()
        logger.info("EPG cache cleared")
    }

    /// Clears cache for channels that are no longer visible
    /// - Parameter visibleIds: Set of currently visible stream IDs
    func clearCacheForInvisibleChannels(visibleIds: Set<Int>) {
        let idsToRemove = displayModelCache.keys.filter { !visibleIds.contains($0) }
        for id in idsToRemove {
            displayModelCache.removeValue(forKey: id)
            cacheTimestamps.removeValue(forKey: id)
            preloadedIds.remove(id)
        }

        if !idsToRemove.isEmpty {
            logger.debug("Cleared cache for \(idsToRemove.count) invisible channels")
        }
    }

    // MARK: - Batch Operations

    /// Builds display models for multiple channels efficiently
    /// - Parameters:
    ///   - channels: Array of channels to build models for
    ///   - favoriteIds: Set of favorite stream IDs
    /// - Returns: Dictionary of stream ID to display model
    func buildDisplayModels(
        for channels: [LiveChannel],
        favoriteIds: Set<Int>
    ) async -> [Int: LiveChannelDisplayModel] {
        var models: [Int: LiveChannelDisplayModel] = [:]

        for channel in channels {
            let isFavorite = favoriteIds.contains(channel.streamId)
            let model = await getDisplayModel(for: channel, isFavorite: isFavorite)
            models[channel.streamId] = model
        }

        return models
    }

    // MARK: - Private Helpers

    private func buildDisplayModel(
        for channel: LiveChannel,
        isFavorite: Bool
    ) async -> LiveChannelDisplayModel {
        guard isEPGLoaded else {
            return LiveChannelDisplayModel.withoutEPG(channel: channel, isFavorite: isFavorite)
        }

        let current = await epgService.currentProgramme(for: channel.streamId)
        let upcoming = await epgService.upcomingProgrammes(for: channel.streamId, limit: 5)

        if let currentProgramme = current {
            return LiveChannelDisplayModel.withEPG(
                channel: channel,
                currentProgramme: currentProgramme,
                upcomingProgrammes: upcoming,
                isFavorite: isFavorite
            )
        } else {
            return LiveChannelDisplayModel.withoutEPG(channel: channel, isFavorite: isFavorite)
        }
    }

    private func isCacheExpired(for streamId: Int) -> Bool {
        guard let timestamp = cacheTimestamps[streamId] else { return true }
        return Date().timeIntervalSince(timestamp) > cacheTTL
    }
}

// MARK: - Convenience Extensions

extension LiveChannelEPGService {
    /// Refreshes EPG data for a specific channel
    /// - Parameter streamId: The channel's stream ID
    func refreshChannelEPG(for streamId: Int) async {
        displayModelCache.removeValue(forKey: streamId)
        cacheTimestamps.removeValue(forKey: streamId)
        preloadedIds.remove(streamId)
        logger.debug("Refreshed EPG cache for channel \(streamId)")
    }
}

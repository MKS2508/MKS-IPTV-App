//
//  FootballService.swift
//  mks-multiplatform-iptv
//
//  Main actor-based service for football data management.
//  Handles fetching, caching, and matching fixtures to channels.
//

import Foundation
import os

// MARK: - Football Service

/// Main service for football data management.
/// Coordinates data fetching, caching, and channel matching.
actor FootballService {
    // MARK: - Properties

    private let logger = Logger(subsystem: "FootballService", category: "Football")
    private let config: FootballConfig
    private let dataProvider: FootballDataProvider

    /// In-memory cache of matched events by channel stream ID
    private var cachedMatchedChannels: [Int: FootballMatchedChannel] = [:]

    /// Cached fixtures
    private var cachedFixtures: [FootballFixture] = []

    /// Last fetch timestamp
    private var lastFetchTime: Date?

    /// Currently loading flag
    private var isLoading = false

    // MARK: - Initialization

    init(config: FootballConfig = .default) {
        self.config = config

        // Select data provider based on configuration
        switch config.provider {
        case .apiFootball:
            self.dataProvider = APIFootballProvider(config: config)
        case .mock:
            self.dataProvider = MockFootballDataProvider()
        }

        logger.info("FootballService initialized with provider: \(config.provider.displayName)")
    }

    // MARK: - Public API

    /// Load and match football fixtures for today.
    /// - Parameter liveChannels: Available live channels to match against
    /// - Returns: Dictionary of streamId -> matched event
    func loadAndMatchFixtures(liveChannels: [LiveChannel]) async throws -> [Int: FootballMatchedChannel] {
        // Check cache freshness
        if !self.cachedMatchedChannels.isEmpty {
            if let lastFetch = self.lastFetchTime,
               Date().timeIntervalSince(lastFetch) < config.cacheTTL {
                self.logger.debug("Returning cached football events (\(self.cachedMatchedChannels.count) matches)")
                return self.cachedMatchedChannels
            }
        }

        guard !self.isLoading else {
            self.logger.debug("Already loading football data, returning cache")
            return self.cachedMatchedChannels
        }

        self.isLoading = true
        defer { self.isLoading = false }

        do {
            // Fetch fixtures
            let fixtures = try await self.dataProvider.fetchFixtures(
                date: Date(),
                leagueIds: self.config.leagueIds,
                season: self.config.season
            )

            self.logger.info("Fetched \(fixtures.count) fixtures for today")

            // Cache fixtures
            self.cachedFixtures = fixtures

            // Match fixtures to channels
            let matched = self.matchFixturesToChannels(fixtures: fixtures, channels: liveChannels)

            // Update cache
            self.cachedMatchedChannels = matched
            self.lastFetchTime = Date()

            // Persist to disk
            await self.persistCache(fixtures: fixtures, matched: matched)

            self.logger.info("Matched \(matched.count) fixtures to channels")

            return matched

        } catch {
            self.logger.error("Failed to load fixtures: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get matched event for a specific channel.
    /// - Parameter streamId: Channel's stream ID
    /// - Returns: Matched event if available
    func getMatchedEvent(for streamId: Int) -> FootballMatchedChannel? {
        cachedMatchedChannels[streamId]
    }

    /// Get all fixtures for today.
    /// - Returns: All cached fixtures
    func getTodayFixtures() -> [FootballFixture] {
        cachedFixtures
    }

    /// Get all matched events.
    /// - Returns: All cached matches
    func getAllMatchedEvents() -> [Int: FootballMatchedChannel] {
        cachedMatchedChannels
    }

    /// Get fixtures grouped by competition.
    /// - Returns: Dictionary of league name -> fixtures
    func getFixturesByCompetition() -> [String: [FootballFixture]] {
        Dictionary(grouping: cachedFixtures) { $0.league.name }
    }

    /// Get channels that have live matches.
    /// - Returns: Stream IDs with live matches
    func getLiveMatchChannelIds() -> [Int] {
        cachedMatchedChannels
            .filter { $0.value.isLive }
            .map { $0.key }
    }

    /// Clear cache.
    func clearCache() {
        cachedMatchedChannels.removeAll()
        cachedFixtures.removeAll()
        lastFetchTime = nil
        logger.info("Football cache cleared")
    }

    // MARK: - Matching Logic

    /// Match fixtures to available channels.
    private func matchFixturesToChannels(
        fixtures: [FootballFixture],
        channels: [LiveChannel]
    ) -> [Int: FootballMatchedChannel] {
        var result: [Int: FootballMatchedChannel] = [:]

        // Build channel lookup by category
        var channelsByCategory: [String: [LiveChannel]] = [:]
        for channel in channels {
            if let categoryId = channel.categoryId {
                channelsByCategory[categoryId, default: []].append(channel)
            }
        }

        // Process each fixture
        for fixture in fixtures {
            // Find matching rule for this competition
            guard let rule = FootballMatchRule.findRule(for: fixture.league) else {
                logger.debug("No matching rule for competition: \(fixture.league.name)")
                continue
            }

            // Find candidate channels
            var candidateChannels: [LiveChannel] = []

            // 1. Try category match
            for categoryId in rule.categoryIds {
                if let categoryChannels = channelsByCategory[categoryId] {
                    candidateChannels.append(contentsOf: categoryChannels)
                }
            }

            // 2. Filter by keywords if we have candidates
            if !candidateChannels.isEmpty {
                let keywordMatches = candidateChannels.filter { channel in
                    let channelNameLower = channel.name.lowercased()
                    return rule.channelKeywords.contains { keyword in
                        channelNameLower.contains(keyword.lowercased())
                    }
                }

                // Use keyword matches if found, otherwise use category matches
                let matchedChannels = keywordMatches.isEmpty ? candidateChannels : keywordMatches

                if !matchedChannels.isEmpty {
                    // Create channel options with quality info
                    let options = matchedChannels.map { channel in
                        FootballChannelOption(channel: channel, matchReason: .categoryId(rule.categoryIds.first ?? "unknown"))
                    }

                    // Sort by quality (FHD > HD > SD)
                    let sortedOptions = options.sorted { $0.quality > $1.quality }

                    // Determine match confidence
                    let confidence: MatchConfidence = !keywordMatches.isEmpty ? .high : .medium

                    // Create matched result
                    let matched = FootballMatchedChannel(
                        fixture: fixture,
                        channels: sortedOptions,
                        matchConfidence: confidence
                    )

                    // Store for each channel
                    for option in sortedOptions {
                        result[option.channel.streamId] = matched
                    }

                    logger.debug("Matched \(fixture.matchDisplay) to \(sortedOptions.count) channels")
                }
            }
        }

        return result
    }

    // MARK: - Cache Persistence

    private func persistCache(
        fixtures: [FootballFixture],
        matched: [Int: FootballMatchedChannel]
    ) async {
        // Create a simplified cache structure for persistence
        let cache = FootballEventsCache(
            fixtures: fixtures,
            fetchedAt: Date(),
            fetchDate: Date()
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cache)
            let url = cacheManager.cacheDirectory.appendingPathComponent("football_events.json")
            try data.write(to: url)
            logger.debug("Persisted football cache to disk")
        } catch {
            logger.error("Failed to persist football cache: \(error.localizedDescription)")
        }
    }

    private var cacheManager: CacheManager {
        CacheManager.shared
    }
}

// MARK: - API-Football Provider (Placeholder)

/// API-Football provider implementation.
/// Requires API key to function.
actor APIFootballProvider: FootballDataProvider {
    let name = "API-Football"
    private let config: FootballConfig

    var isConfigured: Bool {
        config.hasAPIKey
    }

    init(config: FootballConfig) {
        self.config = config
    }

    func fetchFixtures(
        date: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture] {
        guard isConfigured else {
            throw FootballServiceError.noAPIKey
        }

        // TODO: Implement actual API call to API-Football via RapidAPI
        // Endpoint: GET /fixtures?date=YYYY-MM-DD&league=140&season=2024
        // Headers: x-rapidapi-key: YOUR_API_KEY
        //
        // For now, fall back to mock data
        let mockProvider = MockFootballDataProvider()
        return try await mockProvider.fetchFixtures(date: date, leagueIds: leagueIds, season: season)
    }

    func fetchLiveFixtures(leagueIds: [Int]) async throws -> [FootballFixture] {
        guard isConfigured else {
            throw FootballServiceError.noAPIKey
        }

        // TODO: Implement actual API call
        // Endpoint: GET /fixtures?live=all

        let mockProvider = MockFootballDataProvider()
        return try await mockProvider.fetchLiveFixtures(leagueIds: leagueIds)
    }

    func fetchFixtures(
        from: Date,
        to: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture] {
        guard isConfigured else {
            throw FootballServiceError.noAPIKey
        }

        // TODO: Implement actual API call
        // Endpoint: GET /fixtures?from=YYYY-MM-DD&to=YYYY-MM-DD

        let mockProvider = MockFootballDataProvider()
        return try await mockProvider.fetchFixtures(from: from, to: to, leagueIds: leagueIds, season: season)
    }
}

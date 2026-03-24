//
//  EPGService.swift
//  mks-multiplatform-iptv
//
//  Actor that fetches, caches, and serves EPG data
//  Uses dobleM XMLTV source with 4-hour refresh interval
//

import Foundation

/// Actor that manages EPG data fetching, caching, and querying
actor EPGService {

    // MARK: - Configuration

    private let epgURL = "https://raw.githubusercontent.com/davidmuma/EPG_dobleM/master/guiatv.xml"
    private let refreshInterval: TimeInterval = 14400 // 4 hours

    // MARK: - State

    private var epgData: EPGData?
    private var programmeIndex: [String: [EPGProgramme]] = [:] // channelId → programmes
    private let matchingService = EPGMatchingService()
    private let parser = EPGXMLParser()
    private let cacheManager = CacheManager.shared

    // MARK: - Public API

    /// Load EPG data from cache or network
    func loadEPG() async throws {
        // Check memory cache
        if let existing = epgData, !isStale(existing) {
            return
        }

        // Check disk cache
        if let cached = cacheManager.getCachedEPG(), !isStale(cached) {
            epgData = cached
            buildProgrammeIndex()
            MKSLog.live.debug("[EPGService] Loaded EPG from disk cache (\(cached.channels.count) channels, \(cached.programmes.count) programmes)")
            return
        }

        // Fetch from network
        try await fetchAndParseEPG()
    }

    /// Build match table between live channels and EPG channels.
    /// Checks disk cache first; falls back to full Levenshtein matching on miss.
    func buildMatchTable(liveChannels: [LiveChannel]) async {
        // Try loading from cache first
        if let cached = cacheManager.getCachedMatchTable() {
            await matchingService.loadCachedTable(cached)
            MKSLog.live.debug("[EPGService] Match table loaded from cache (\(cached.count) entries)")
            return
        }

        guard let data = epgData else { return }
        await matchingService.buildMatchTable(liveChannels: liveChannels, epgChannels: data.channels)

        // Save computed table to cache
        let table = await matchingService.matchTable
        cacheManager.cacheMatchTable(table)
    }

    /// Get the current programme for a live channel
    func currentProgramme(for liveChannelId: Int) async -> EPGProgramme? {
        guard let epgChannelId = await matchingService.epgChannelId(for: liveChannelId) else {
            return nil
        }
        return programmeIndex[epgChannelId]?.first { $0.isNow }
    }

    /// Get upcoming programmes for a live channel
    func upcomingProgrammes(for liveChannelId: Int, limit: Int = 5) async -> [EPGProgramme] {
        guard let epgChannelId = await matchingService.epgChannelId(for: liveChannelId) else {
            return []
        }
        let now = Date()
        return (programmeIndex[epgChannelId] ?? [])
            .filter { $0.start > now }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// Get all channels that have a current programme airing
    func channelsWithCurrentProgramme() -> [(epgChannelId: String, programme: EPGProgramme)] {
        var results: [(String, EPGProgramme)] = []
        for (channelId, programmes) in programmeIndex {
            if let current = programmes.first(where: { $0.isNow }) {
                results.append((channelId, current))
            }
        }
        return results
    }

    /// Get all upcoming programmes across all channels (sorted by start time)
    func allUpcomingProgrammes(limit: Int = 20) -> [EPGProgramme] {
        let now = Date()
        let threeHours = now.addingTimeInterval(3 * 3600)
        return programmeIndex.values
            .flatMap { $0 }
            .filter { $0.start > now && $0.start < threeHours }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// Get the EPG channel for a given EPG channel ID
    func epgChannel(for epgChannelId: String) -> EPGChannel? {
        epgData?.channels.first { $0.id == epgChannelId }
    }

    /// Get the matched EPG channel ID for a live channel
    func matchedEPGChannelId(for liveChannelId: Int) async -> String? {
        await matchingService.epgChannelId(for: liveChannelId)
    }

    /// Whether EPG data is available
    var isAvailable: Bool {
        epgData != nil && !(epgData?.channels.isEmpty ?? true)
    }

    /// Number of matched channels
    var matchCount: Int {
        get async {
            await matchingService.matchTable.count
        }
    }

    // MARK: - Private

    private func fetchAndParseEPG() async throws {
        guard let url = URL(string: epgURL) else {
            throw EPGError.invalidURL
        }

        MKSLog.live.debug("[EPGService] Fetching EPG from \(epgURL)...")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EPGError.fetchFailed(URLError(.badServerResponse))
        }

        guard !data.isEmpty else {
            throw EPGError.noData
        }

        MKSLog.live.debug("[EPGService] Downloaded \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")

        // Set time window: 1 hour ago → 24 hours from now
        let now = Date()
        parser.timeWindowStart = now.addingTimeInterval(-3600)
        parser.timeWindowEnd = now.addingTimeInterval(24 * 3600)

        let parsed = try parser.parse(data: data)

        epgData = parsed
        buildProgrammeIndex()

        // Cache to disk
        cacheManager.cacheEPG(parsed)

        MKSLog.live.debug("[EPGService] Parsed EPG: \(parsed.channels.count) channels, \(parsed.programmes.count) programmes")
    }

    private func buildProgrammeIndex() {
        guard let data = epgData else { return }

        // Prune programmes that have already ended (stale cache entries)
        let now = Date()
        let liveProgrammes = data.programmes.filter { $0.stop > now.addingTimeInterval(-3600) }

        programmeIndex = Dictionary(grouping: liveProgrammes, by: { $0.channelId })
    }

    private func isStale(_ data: EPGData) -> Bool {
        Date().timeIntervalSince(data.fetchedAt) > refreshInterval
    }
}

//
//  FootballChannelMatching.swift
//  mks-multiplatform-iptv
//
//  Models for matching football fixtures to IPTV channels.
//  Handles mirrors, quality preferences, and category mapping.
//

import Foundation

// MARK: - Matched Channel

/// Result of matching a football fixture to available IPTV channels.
struct FootballMatchedChannel: Identifiable, Sendable {
    let id: String
    let fixture: FootballFixture
    let channels: [FootballChannelOption]
    let bestChannel: FootballChannelOption?
    let matchConfidence: MatchConfidence

    init(
        fixture: FootballFixture,
        channels: [FootballChannelOption],
        matchConfidence: MatchConfidence
    ) {
        self.fixture = fixture
        self.channels = channels
        self.matchConfidence = matchConfidence
        self.bestChannel = channels.first { $0.quality == .fhd } ?? channels.first
        self.id = "\(fixture.id)_\(fixture.date.timeIntervalSince1970)"
    }

    // MARK: - Computed Properties

    /// Whether any channel is available for this fixture
    var hasChannel: Bool {
        !channels.isEmpty
    }

    /// Whether the match is currently live
    var isLive: Bool {
        fixture.isLive
    }

    /// All mirror channel IDs
    var channelIds: [Int] {
        channels.map { $0.channel.streamId }
    }

    /// Best channel stream ID
    var bestChannelId: Int? {
        bestChannel?.channel.streamId
    }

    /// Display string for UI badge
    var badgeDisplay: String {
        if isLive, let score = fixture.scoreDisplay {
            return "\(fixture.teams.home.shortName ?? String(fixture.teams.home.name.prefix(3).uppercased())) \(score) \(fixture.teams.away.shortName ?? String(fixture.teams.away.name.prefix(3).uppercased()))"
        } else {
            return "\(fixture.formattedTime) \(fixture.shortDisplay)"
        }
    }

    /// Compact display for channel cards
    var compactDisplay: String {
        if isLive {
            return "\(fixture.statusDisplay) \(fixture.teams.home.name) \(fixture.goals?.home ?? 0) - \(fixture.goals?.away ?? 0) \(fixture.teams.away.name)"
        } else {
            return "\(fixture.formattedTime) \(fixture.matchDisplay)"
        }
    }
}

// MARK: - Channel Option

/// A single channel option for a fixture (includes quality info).
struct FootballChannelOption: Identifiable, Sendable {
    let id: Int
    let channel: LiveChannel
    let quality: ChannelQuality
    let mirrorNumber: Int?
    let matchReason: ChannelMatchReason

    init(channel: LiveChannel, matchReason: ChannelMatchReason) {
        self.channel = channel
        self.matchReason = matchReason
        self.id = channel.streamId
        self.quality = ChannelQuality.from(channelName: channel.name)
        self.mirrorNumber = Self.extractMirrorNumber(from: channel.name)
    }

    /// Display name with quality
    var displayWithQuality: String {
        if let mirror = mirrorNumber {
            return "\(channel.name) (Mirror \(mirror))"
        }
        return channel.name
    }

    /// Extracts mirror number from channel name (e.g., "Liga de Campeones 2" → 2)
    private static func extractMirrorNumber(from name: String) -> Int? {
        let pattern = #"\b(\d+)\s*(?:HD|FHD|SD|4K)?$"#
        if let match = name.range(of: pattern, options: .regularExpression) {
            let numberString = String(name[match]).filter { $0.isNumber }
            return Int(numberString)
        }
        return nil
    }
}

// MARK: - Channel Quality

/// Video quality levels for channel sorting.
enum ChannelQuality: Int, Comparable, Sendable {
    case uhd4k = 4
    case fhd = 3
    case hd = 2
    case sd = 1
    case unknown = 0

    /// Parse quality from channel name.
    static func from(channelName: String) -> ChannelQuality {
        let name = channelName.uppercased()
        if name.contains("4K") || name.contains("UHD") { return .uhd4k }
        if name.contains("FHD") || name.contains("1080") { return .fhd }
        if name.contains("HD") || name.contains("720") { return .hd }
        if name.contains("SD") { return .sd }
        return .unknown
    }

    var displayName: String {
        switch self {
        case .uhd4k: return "4K"
        case .fhd: return "FHD"
        case .hd: return "HD"
        case .sd: return "SD"
        case .unknown: return ""
        }
    }

    static func < (lhs: ChannelQuality, rhs: ChannelQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Match Confidence

/// How confident the match is between fixture and channel.
enum MatchConfidence: Int, Sendable {
    case exact = 3      // Category + keywords match perfectly
    case high = 2       // Category match with competition keywords
    case medium = 1     // Only category match
    case low = 0        // Fuzzy match only

    var displayName: String {
        switch self {
        case .exact: return "Exacta"
        case .high: return "Alta"
        case .medium: return "Media"
        case .low: return "Baja"
        }
    }
}

// MARK: - Channel Match Reason

/// Why a channel was matched to a fixture.
enum ChannelMatchReason: Sendable {
    case categoryId(String)
    case keywordMatch([String])
    case exactNameMatch
    case fuzzyMatch(similarity: Double)

    var description: String {
        switch self {
        case .categoryId(let id):
            return "Category: \(id)"
        case .keywordMatch(let keywords):
            return "Keywords: \(keywords.joined(separator: ", "))"
        case .exactNameMatch:
            return "Exact name match"
        case .fuzzyMatch(let similarity):
            return String(format: "Fuzzy: %.0f%%", similarity * 100)
        }
    }
}

// MARK: - Match Rule

/// Rule for matching fixtures to channels.
struct FootballMatchRule: Sendable {
    let competitionId: Int                    // API-Football league ID
    let competitionNames: [String]            // Names to match (lowercase)
    let categoryIds: [String]                 // IPTV category IDs
    let channelKeywords: [String]             // Keywords in channel names
    let priority: Int                         // Higher = checked first

    /// Predefined match rules for supported competitions.
    static let defaultRules: [FootballMatchRule] = [
        // Champions League
        FootballMatchRule(
            competitionId: 2,
            competitionNames: ["champions league", "uefa champions league", "ucl"],
            categoryIds: ["109"],
            channelKeywords: ["liga de campeones", "champions", "ucl"],
            priority: 100
        ),
        // La Liga
        FootballMatchRule(
            competitionId: 140,
            competitionNames: ["la liga", "laliga", "primera división", "primera division"],
            categoryIds: ["147", "148", "149"],
            channelKeywords: ["laliga", "la liga", "m+ laliga", "dazn laliga"],
            priority: 90
        ),
        // Premier League
        FootballMatchRule(
            competitionId: 39,
            competitionNames: ["premier league", "premier", "epl"],
            categoryIds: ["190"],
            channelKeywords: ["premier league", "premier", "pl"],
            priority: 80
        ),
        // Serie A
        FootballMatchRule(
            competitionId: 135,
            competitionNames: ["serie a", "serie a tim", "italian serie a"],
            categoryIds: ["191"],
            channelKeywords: ["serie a", "calcio", "italiana"],
            priority: 70
        ),
        // Bundesliga
        FootballMatchRule(
            competitionId: 78,
            competitionNames: ["bundesliga", "german bundesliga"],
            categoryIds: ["189"],
            channelKeywords: ["bundesliga", "alemana"],
            priority: 70
        ),
        // Segunda División
        FootballMatchRule(
            competitionId: 141,
            competitionNames: ["segunda división", "segunda division", "laliga smartbank"],
            categoryIds: ["149"],
            channelKeywords: ["segunda", "laliga smartbank", "smartbank"],
            priority: 60
        ),
        // Copa del Rey
        FootballMatchRule(
            competitionId: 143,
            competitionNames: ["copa del rey", "copa de españa"],
            categoryIds: ["107", "108"],
            channelKeywords: ["copa del rey", "copa"],
            priority: 50
        )
    ]

    /// Find matching rule for a fixture's competition.
    static func findRule(for leagueInfo: FootballLeagueInfo) -> FootballMatchRule? {
        defaultRules.first { rule in
            rule.competitionId == leagueInfo.id ||
            rule.competitionNames.contains { leagueInfo.name.lowercased().contains($0) }
        }
    }
}

// MARK: - Football Events Cache (Simplified for persistence)

/// Simplified cache structure for disk persistence.
struct FootballEventsCache: Codable, Sendable {
    let fixtures: [FootballFixture]
    let fetchedAt: Date
    let fetchDate: Date

    /// Whether the cache is still fresh
    func isFresh(ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) < ttl
    }

    /// Whether the cache is for today
    var isForToday: Bool {
        Calendar.current.isDate(fetchDate, inSameDayAs: Date())
    }
}

// MARK: - Football Service Error

/// Errors from football service operations.
enum FootballServiceError: Error, LocalizedError, Sendable {
    case noAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimitExceeded(retryAfter: Int?)
    case apiError(message: String)
    case noData
    case cacheExpired

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured for football data"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from football API"
        case .rateLimitExceeded(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded. Retry after \(seconds) seconds"
            }
            return "Rate limit exceeded"
        case .apiError(let message):
            return "API error: \(message)"
        case .noData:
            return "No football data available"
        case .cacheExpired:
            return "Football data cache has expired"
        }
    }
}

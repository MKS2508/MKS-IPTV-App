//
//  FootballConfig.swift
//  mks-multiplatform-iptv
//
//  Configuration for football data providers.
//  Supports multiple providers with easy switching.
//

import Foundation
import IPTVCore

// MARK: - Football Provider

/// Available football data providers.
enum FootballProvider: String, CaseIterable, Sendable {
    case apiFootball = "api-football"
    case mock = "mock"  // For testing without API key

    var displayName: String {
        switch self {
        case .apiFootball: return "API-Football"
        case .mock: return "Mock Data (Testing)"
        }
    }
}

// MARK: - Football Configuration

/// Configuration for football data services.
struct FootballConfig: Sendable {
    /// Active provider
    let provider: FootballProvider

    /// API key (required for real providers)
    let apiKey: String?

    /// Base URL for API
    let baseURL: String

    /// Cache TTL in seconds (default: 4 hours)
    let cacheTTL: TimeInterval

    /// Leagues to fetch (La Liga, Champions League, etc.)
    let leagueIds: [Int]

    /// Season year (current season)
    let season: Int

    /// Whether to include live scores
    let enableLiveScores: Bool

    /// Live scores refresh interval in seconds (default: 60)
    let liveScoresRefreshInterval: TimeInterval

    // MARK: - Default Configuration

    /// Default configuration without API key (uses mock data).
    static let `default` = FootballConfig(
        provider: .mock,
        apiKey: nil,
        baseURL: "https://api-football-v1.p.rapidapi.com/v3",
        cacheTTL: 14400,  // 4 hours
        leagueIds: FootballLeague.defaultLeagueIds,
        season: FootballLeague.currentSeason,
        enableLiveScores: false,
        liveScoresRefreshInterval: 60
    )

    /// Configuration with API-Football API key.
    static func withAPIKey(_ apiKey: String) -> FootballConfig {
        FootballConfig(
            provider: .apiFootball,
            apiKey: apiKey,
            baseURL: "https://api-football-v1.p.rapidapi.com/v3",
            cacheTTL: 14400,
            leagueIds: FootballLeague.defaultLeagueIds,
            season: FootballLeague.currentSeason,
            enableLiveScores: true,
            liveScoresRefreshInterval: 60
        )
    }

    /// Whether API key is configured.
    var hasAPIKey: Bool {
        guard let key = apiKey, !key.isEmpty else { return false }
        return true
    }
}

// MARK: - Football League

/// Known football leagues with their API IDs.
enum FootballLeague: Int, CaseIterable, Sendable {
    case championsLeague = 2
    case laLiga = 140
    case segundaDivision = 141
    case copaDelRey = 143
    case premierLeague = 39
    case serieA = 135
    case bundesliga = 78
    case ligue1 = 61

    /// Default leagues to fetch for Spanish users.
    static let defaultLeagueIds: [Int] = [
        championsLeague.rawValue,
        laLiga.rawValue,
        segundaDivision.rawValue,
        premierLeague.rawValue,
        serieA.rawValue,
        bundesliga.rawValue
    ]

    /// Current season year (starts from August).
    static var currentSeason: Int {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)

        // Season starts in August, so Jan-Jul belongs to previous season
        return month >= 8 ? year : year - 1
    }

    var displayName: String {
        switch self {
        case .championsLeague: return "Champions League"
        case .laLiga: return "La Liga"
        case .segundaDivision: return "Segunda División"
        case .copaDelRey: return "Copa del Rey"
        case .premierLeague: return "Premier League"
        case .serieA: return "Serie A"
        case .bundesliga: return "Bundesliga"
        case .ligue1: return "Ligue 1"
        }
    }

    var shortName: String {
        switch self {
        case .championsLeague: return "UCL"
        case .laLiga: return "LaLiga"
        case .segundaDivision: return "LaLiga 2"
        case .copaDelRey: return "Copa"
        case .premierLeague: return "PL"
        case .serieA: return "Serie A"
        case .bundesliga: return "BL"
        case .ligue1: return "L1"
        }
    }
}

// MARK: - Football Config Manager

/// Manages football configuration stored in UserDefaults.
enum FootballConfigManager {
    private static let apiKeyKey = "football_api_key"
    private static let providerKey = "football_provider"
    private static let enableLiveScoresKey = "football_enable_live_scores"

    /// Get current configuration.
    static var current: FootballConfig {
        let providerRaw = UserDefaults.standard.string(forKey: providerKey) ?? "mock"
        let provider = FootballProvider(rawValue: providerRaw) ?? .mock
        let apiKey = UserDefaults.standard.string(forKey: apiKeyKey)
        let enableLiveScores = UserDefaults.standard.bool(forKey: enableLiveScoresKey)

        if let key = apiKey, !key.isEmpty, provider == .apiFootball {
            var config = FootballConfig.withAPIKey(key)
            return FootballConfig(
                provider: config.provider,
                apiKey: config.apiKey,
                baseURL: config.baseURL,
                cacheTTL: config.cacheTTL,
                leagueIds: config.leagueIds,
                season: config.season,
                enableLiveScores: enableLiveScores,
                liveScoresRefreshInterval: config.liveScoresRefreshInterval
            )
        }

        return FootballConfig(
            provider: .mock,
            apiKey: nil,
            baseURL: "https://api-football-v1.p.rapidapi.com/v3",
            cacheTTL: 14400,
            leagueIds: FootballLeague.defaultLeagueIds,
            season: FootballLeague.currentSeason,
            enableLiveScores: false,
            liveScoresRefreshInterval: 60
        )
    }

    /// Set API key.
    static func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: apiKeyKey)
        UserDefaults.standard.set(FootballProvider.apiFootball.rawValue, forKey: providerKey)
    }

    /// Clear API key (revert to mock data).
    static func clearAPIKey() {
        UserDefaults.standard.removeObject(forKey: apiKeyKey)
        UserDefaults.standard.set(FootballProvider.mock.rawValue, forKey: providerKey)
    }

    /// Enable or disable live scores.
    static func setLiveScoresEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enableLiveScoresKey)
    }
}

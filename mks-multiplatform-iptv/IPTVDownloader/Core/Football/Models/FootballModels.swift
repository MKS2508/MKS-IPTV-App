//
//  FootballModels.swift
//  mks-multiplatform-iptv
//
//  Data models for football fixtures and events integration.
//  Designed to work with API-Football but provider-agnostic.
//

import Foundation

// MARK: - Football Fixture

/// Represents a single football match/fixture.
struct FootballFixture: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let referee: String?
    let timezone: String
    let date: Date
    let timestamp: Int
    let periods: FootballPeriods
    let venue: FootballVenue?
    let status: FootballMatchStatus
    let league: FootballLeagueInfo
    let teams: FootballTeams
    let goals: FootballGoals?
    let score: FootballScore?

    // MARK: - Computed Properties

    /// Whether the match is currently live
    var isLive: Bool {
        status.isLive
    }

    /// Whether the match has finished
    var isFinished: Bool {
        status.isFinished
    }

    /// Whether the match hasn't started yet
    var isUpcoming: Bool {
        status.isUpcoming
    }

    /// Formatted match time (e.g., "21:00")
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        return formatter.string(from: date)
    }

    /// Formatted date (e.g., "Lun 10 Mar")
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.string(from: date)
    }

    /// Display string for the match (e.g., "Real Madrid vs Barcelona")
    var matchDisplay: String {
        "\(teams.home.name) vs \(teams.away.name)"
    }

    /// Short display for badges (e.g., "RMA vs BAR")
    var shortDisplay: String {
        "\(teams.home.shortName ?? teams.home.name.prefix(3).uppercased()) vs \(teams.away.shortName ?? teams.away.name.prefix(3).uppercased())"
    }

    /// Live score display (e.g., "2 - 1") or nil if not started
    var scoreDisplay: String? {
        guard let goals = goals, status.short != .notStarted else { return nil }
        return "\(goals.home ?? 0) - \(goals.away ?? 0)"
    }

    /// Status display (e.g., "65'", "HT", "FT")
    var statusDisplay: String {
        status.displayString
    }
}

// MARK: - Match Periods

/// Time periods for a match.
struct FootballPeriods: Codable, Equatable, Sendable {
    let first: Int?
    let second: Int?
}

// MARK: - Venue

/// Stadium/venue information.
struct FootballVenue: Codable, Equatable, Sendable {
    let id: Int?
    let name: String?
    let city: String?
}

// MARK: - Match Status

/// Match status with elapsed time.
struct FootballMatchStatus: Codable, Equatable, Sendable {
    let elapsed: Int?
    let short: FootballStatusShort
    let long: String

    /// Whether the match is currently in play
    var isLive: Bool {
        switch short {
        case .firstHalf, .secondHalf, .extraTime, .penaltyInProgress, .halftime, .break_:
            return true
        default:
            return false
        }
    }

    /// Whether the match has finished
    var isFinished: Bool {
        short == .matchFinished || short == .afterPenalties || short == .afterExtraTime
    }

    /// Whether the match hasn't started yet
    var isUpcoming: Bool {
        short == .notStarted || short == .timeToBeDefined || short == .postponed
    }

    /// Display string for the status
    var displayString: String {
        switch short {
        case .notStarted, .timeToBeDefined:
            return formattedTime
        case .firstHalf, .secondHalf, .extraTime:
            if let elapsed = elapsed {
                return "\(elapsed)'"
            }
            return ""
        case .halftime:
            return "HT"
        case .penaltyInProgress:
            return "PEN"
        case .break_:
            return "DESC"
        case .matchFinished:
            return "FT"
        case .afterPenalties:
            return "PEN"
        case .afterExtraTime:
            return "AET"
        case .postponed, .suspended, .interrupted, .abandoned, .cancelled:
            return short.rawValue
        case .technicalBreak, .awarded:
            return short.rawValue
        }
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

/// Short status codes from API.
enum FootballStatusShort: String, Codable, Sendable {
    case timeToBeDefined = "TBD"
    case notStarted = "NS"
    case firstHalf = "1H"
    case halftime = "HT"
    case secondHalf = "2H"
    case extraTime = "ET"
    case penaltyInProgress = "P"
    case break_ = "BT"
    case matchFinished = "FT"
    case afterExtraTime = "AET"
    case afterPenalties = "PEN"
    case postponed = "PST"
    case suspended = "SUSP"
    case cancelled = "CANC"
    case abandoned = "ABD"
    case technicalBreak = "AWD"
    case interrupted = "INT"
    case awarded = "WO"
}

// MARK: - League Info

/// League information within a fixture.
struct FootballLeagueInfo: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let country: String?
    let logo: String?
    let flag: String?
    let season: Int
    let round: String?

    /// Normalized competition name for channel matching
    var competitionName: String {
        name.lowercased()
    }

    /// Whether this is a Champions League match
    var isChampionsLeague: Bool {
        name.lowercased().contains("champions") || id == 2
    }

    /// Whether this is a La Liga match
    var isLaLiga: Bool {
        name.lowercased().contains("la liga") || name.lowercased().contains("laliga") || id == 140
    }

    /// Whether this is a Premier League match
    var isPremierLeague: Bool {
        name.lowercased().contains("premier") || id == 39
    }

    /// Whether this is a Serie A match
    var isSerieA: Bool {
        name.lowercased().contains("serie a") || id == 135
    }

    /// Whether this is a Bundesliga match
    var isBundesliga: Bool {
        name.lowercased().contains("bundesliga") || id == 78
    }
}

// MARK: - Teams

/// Home and away teams.
struct FootballTeams: Codable, Equatable, Sendable {
    let home: FootballTeam
    let away: FootballTeam
}

/// Team information.
struct FootballTeam: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let logo: String?
    let winner: Bool?

    /// Short name if available (computed from name)
    var shortName: String? {
        // Common abbreviations
        let abbreviations: [String: String] = [
            "Real Madrid": "RMA",
            "Barcelona": "BAR",
            "Atlético Madrid": "ATM",
            "Athletic Bilbao": "ATH",
            "Real Sociedad": "RSO",
            "Real Betis": "BET",
            "Villarreal": "VIL",
            "Sevilla": "SEV",
            "Valencia": "VAL",
            "Girona": "GIR",
            "Bayern Munich": "BAY",
            "Borussia Dortmund": "BVB",
            "Inter Milan": "INT",
            "AC Milan": "MIL",
            "Juventus": "JUV",
            "Manchester City": "MCI",
            "Manchester United": "MUN",
            "Liverpool": "LIV",
            "Arsenal": "ARS",
            "Chelsea": "CHE",
            "Tottenham": "TOT",
            "Paris Saint Germain": "PSG"
        ]
        return abbreviations[name]
    }
}

// MARK: - Goals

/// Goals scored by each team.
struct FootballGoals: Codable, Equatable, Sendable {
    let home: Int?
    let away: Int?
}

// MARK: - Score

/// Detailed score breakdown (half-time, full-time, extra-time, penalty).
struct FootballScore: Codable, Equatable, Sendable {
    let halftime: FootballGoals?
    let fulltime: FootballGoals?
    let extratime: FootballGoals?
    let penalty: FootballGoals?
}

// MARK: - API Response

/// Generic API response wrapper.
struct FootballAPIResponse<T: Codable>: Codable, Sendable where T: Sendable {
    let response: [T]
    let errors: [String: String]?
    let paging: FootballPaging?
}

/// Pagination info from API.
struct FootballPaging: Codable, Sendable {
    let current: Int
    let total: Int
}

// MARK: - Fixture Request Parameters

/// Parameters for fetching fixtures.
struct FootballFixturesRequest: Sendable {
    let date: Date?
    let leagueIds: [Int]?
    let season: Int?
    let teamId: Int?
    let live: Bool?
    let from: Date?
    let to: Date?
    let round: String?

    init(
        date: Date? = nil,
        leagueIds: [Int]? = nil,
        season: Int? = nil,
        teamId: Int? = nil,
        live: Bool? = nil,
        from: Date? = nil,
        to: Date? = nil,
        round: String? = nil
    ) {
        self.date = date
        self.leagueIds = leagueIds
        self.season = season
        self.teamId = teamId
        self.live = live
        self.from = from
        self.to = to
        self.round = round
    }

    /// Request for today's fixtures
    static func today(leagueIds: [Int]? = nil) -> FootballFixturesRequest {
        FootballFixturesRequest(date: Date(), leagueIds: leagueIds)
    }

    /// Request for live fixtures
    static func live(leagueIds: [Int]? = nil) -> FootballFixturesRequest {
        FootballFixturesRequest(leagueIds: leagueIds, live: true)
    }

    /// Request for date range
    static func range(from: Date, to: Date, leagueIds: [Int]? = nil) -> FootballFixturesRequest {
        FootballFixturesRequest(leagueIds: leagueIds, from: from, to: to)
    }
}

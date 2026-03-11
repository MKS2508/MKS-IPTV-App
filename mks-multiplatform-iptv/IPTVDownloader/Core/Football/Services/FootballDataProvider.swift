//
//  FootballDataProvider.swift
//  mks-multiplatform-iptv
//
//  Protocol for football data providers.
//  Allows easy switching between API-Football, mock data, or future providers.
//

import Foundation

// MARK: - Data Provider Protocol

/// Protocol for football data providers.
protocol FootballDataProvider: Actor {
    /// Provider name for logging
    var name: String { get }

    /// Fetch fixtures for a specific date
    func fetchFixtures(
        date: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture]

    /// Fetch live fixtures
    func fetchLiveFixtures(leagueIds: [Int]) async throws -> [FootballFixture]

    /// Fetch fixtures in a date range
    func fetchFixtures(
        from: Date,
        to: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture]

    /// Whether the provider is properly configured
    var isConfigured: Bool { get }
}

// MARK: - Mock Provider

/// Mock data provider for testing without API key.
actor MockFootballDataProvider: FootballDataProvider {
    let name = "Mock Data Provider"
    var isConfigured: Bool { true }

    func fetchFixtures(
        date: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture] {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        return generateMockFixtures(for: date)
    }

    func fetchLiveFixtures(leagueIds: [Int]) async throws -> [FootballFixture] {
        try await Task.sleep(nanoseconds: 200_000_000)
        let today = Date()
        var fixtures = generateMockFixtures(for: today)

        // Mark some as live
        if fixtures.count > 1 {
            fixtures[1] = makeFixtureLive(fixtures[1], elapsed: 35)
        }

        return fixtures.filter { $0.isLive }
    }

    func fetchFixtures(
        from: Date,
        to: Date,
        leagueIds: [Int],
        season: Int
    ) async throws -> [FootballFixture] {
        try await Task.sleep(nanoseconds: 500_000_000)
        var allFixtures: [FootballFixture] = []

        var currentDate = from
        while currentDate <= to {
            allFixtures.append(contentsOf: generateMockFixtures(for: currentDate))
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return allFixtures
    }

    // MARK: - Mock Data Generation

    private func generateMockFixtures(for date: Date) -> [FootballFixture] {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        // Only generate fixtures for certain "match days" (simulation)
        let dayOfMonth = calendar.component(.day, from: date)

        // Champions League matches on Tue/Wed
        // La Liga matches on Sat/Sun
        let weekday = calendar.component(.weekday, from: date)

        var fixtures: [FootballFixture] = []

        // Tuesday = 3, Wednesday = 4 -> Champions League
        if weekday == 3 || weekday == 4 {
            fixtures.append(contentsOf: generateChampionsLeagueFixtures(for: date))
        }

        // Saturday = 7, Sunday = 1 -> La Liga
        if weekday == 7 || weekday == 1 {
            fixtures.append(contentsOf: generateLaLigaFixtures(for: date))
        }

        // Add some Premier League on any day for demo
        if dayOfMonth % 3 == 0 {
            fixtures.append(contentsOf: generatePremierLeagueFixtures(for: date))
        }

        return fixtures
    }

    private func generateChampionsLeagueFixtures(for date: Date) -> [FootballFixture] {
        let calendar = Calendar.current
        let baseDate = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!

        return [
            makeFixture(
                id: 1_001,
                date: baseDate,
                leagueId: 2,
                leagueName: "Champions League",
                round: "Round of 16",
                homeTeam: "Real Madrid",
                awayTeam: "Bayern Munich",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            ),
            makeFixture(
                id: 1_002,
                date: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!,
                leagueId: 2,
                leagueName: "Champions League",
                round: "Round of 16",
                homeTeam: "Barcelona",
                awayTeam: "Paris Saint Germain",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            )
        ]
    }

    private func generateLaLigaFixtures(for date: Date) -> [FootballFixture] {
        let calendar = Calendar.current
        let baseDate = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: date)!

        return [
            makeFixture(
                id: 2_001,
                date: baseDate,
                leagueId: 140,
                leagueName: "La Liga",
                round: "Regular Season - 28",
                homeTeam: "Real Madrid",
                awayTeam: "Sevilla",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            ),
            makeFixture(
                id: 2_002,
                date: calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date)!,
                leagueId: 140,
                leagueName: "La Liga",
                round: "Regular Season - 28",
                homeTeam: "Barcelona",
                awayTeam: "Real Sociedad",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            ),
            makeFixture(
                id: 2_003,
                date: calendar.date(bySettingHour: 16, minute: 15, second: 0, of: date)!,
                leagueId: 140,
                leagueName: "La Liga",
                round: "Regular Season - 28",
                homeTeam: "Atlético Madrid",
                awayTeam: "Villarreal",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            )
        ]
    }

    private func generatePremierLeagueFixtures(for date: Date) -> [FootballFixture] {
        let calendar = Calendar.current
        let baseDate = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: date)!

        return [
            makeFixture(
                id: 3_001,
                date: baseDate,
                leagueId: 39,
                leagueName: "Premier League",
                round: "Regular Season - 28",
                homeTeam: "Manchester City",
                awayTeam: "Liverpool",
                homeGoals: nil,
                awayGoals: nil,
                status: .notStarted
            )
        ]
    }

    private func makeFixture(
        id: Int,
        date: Date,
        leagueId: Int,
        leagueName: String,
        round: String,
        homeTeam: String,
        awayTeam: String,
        homeGoals: Int?,
        awayGoals: Int?,
        status: FootballStatusShort
    ) -> FootballFixture {
        FootballFixture(
            id: id,
            referee: nil,
            timezone: "Europe/Madrid",
            date: date,
            timestamp: Int(date.timeIntervalSince1970),
            periods: FootballPeriods(first: nil, second: nil),
            venue: nil,
            status: FootballMatchStatus(elapsed: nil, short: status, long: status.rawValue),
            league: FootballLeagueInfo(
                id: leagueId,
                name: leagueName,
                country: leagueId == 39 ? "England" : leagueId == 78 ? "Germany" : "Spain",
                logo: nil,
                flag: nil,
                season: FootballLeague.currentSeason,
                round: round
            ),
            teams: FootballTeams(
                home: FootballTeam(id: id * 10, name: homeTeam, logo: nil, winner: nil),
                away: FootballTeam(id: id * 10 + 1, name: awayTeam, logo: nil, winner: nil)
            ),
            goals: FootballGoals(home: homeGoals, away: awayGoals),
            score: FootballScore(
                halftime: nil,
                fulltime: FootballGoals(home: homeGoals, away: awayGoals),
                extratime: nil,
                penalty: nil
            )
        )
    }

    private func makeFixtureLive(_ fixture: FootballFixture, elapsed: Int) -> FootballFixture {
        FootballFixture(
            id: fixture.id,
            referee: fixture.referee,
            timezone: fixture.timezone,
            date: fixture.date,
            timestamp: fixture.timestamp,
            periods: fixture.periods,
            venue: fixture.venue,
            status: FootballMatchStatus(
                elapsed: elapsed,
                short: elapsed <= 45 ? .firstHalf : .secondHalf,
                long: elapsed <= 45 ? "First Half" : "Second Half"
            ),
            league: fixture.league,
            teams: fixture.teams,
            goals: FootballGoals(home: 1, away: 0),
            score: FootballScore(
                halftime: nil,
                fulltime: nil,
                extratime: nil,
                penalty: nil
            )
        )
    }
}

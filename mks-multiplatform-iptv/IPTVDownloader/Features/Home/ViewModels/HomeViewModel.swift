//
//  HomeViewModel.swift
//  mks-multiplatform-iptv
//
//  ViewModel for the Home screen — assembles Netflix-style sections
//  from movies, series, live channels, and EPG data
//

import SwiftUI
import IPTVCore

// MARK: - Home Section Model

/// Represents a section on the Home screen
struct HomeSection: Identifiable {
    let id: String
    let type: HomeSectionType
    let title: String
    let iconName: String?
}

/// Types of sections displayed on the Home screen
enum HomeSectionType {
    case heroBanner(item: any LibraryItem)
    case continueWatching(items: [WatchHistoryEntry])
    case recentChannels(channels: [RecentChannelEntry])
    case nowOnTV(channels: [(liveChannel: LiveChannel, epgChannel: EPGChannel?, programme: EPGProgramme)])
    case comingUpNext(programmes: [(programme: EPGProgramme, channelName: String)])
    case mediaCarousel(items: [any LibraryItem])
    case liveTVCategory(channels: [LiveChannel], categoryName: String)
}

// MARK: - HomeViewModel

@MainActor
@Observable
final class HomeViewModel {

    // MARK: - State

    private(set) var sections: [HomeSection] = []
    private(set) var isAssembling = false

    // MARK: - Dependencies

    private let epgService: EPGService?

    /// Stored reference for deferred EPG section insertion
    private var storedLiveChannels: [LiveChannel] = []

    // MARK: - Init

    init(epgService: EPGService? = nil) {
        self.epgService = epgService
    }

    // MARK: - Public API

    /// Assemble all Home sections from loaded data (without EPG — EPG sections inserted later)
    func assembleSections(
        movies: [Movie],
        series: [Serie],
        liveChannels: [LiveChannel],
        movieCategories: [MovieCategory],
        seriesCategories: [SeriesCategory],
        liveChannelCategories: [LiveChannelCategory]
    ) async {
        isAssembling = true
        defer { isAssembling = false }

        // Store for deferred EPG insertion
        storedLiveChannels = liveChannels

        var newSections: [HomeSection] = []

        // 1. Hero Banner — random high-rated movie or serie
        if let hero = pickHeroBanner(movies: movies, series: series) {
            newSections.append(HomeSection(
                id: "hero",
                type: .heroBanner(item: hero),
                title: "",
                iconName: nil
            ))
        }

        // EPG sections (Now on TV, Coming Up Next) are inserted later
        // via insertEPGSections() once EPG loads in the background

        // 4. Added Last 24 Hours
        let now = Date()
        let oneDayAgo = now.addingTimeInterval(-86400)
        let recentItems24h = getRecentItems(movies: movies, series: series, since: oneDayAgo, until: now)
        if !recentItems24h.isEmpty {
            newSections.append(HomeSection(
                id: "added_24h",
                type: .mediaCarousel(items: recentItems24h),
                title: "Added Last 24 Hours",
                iconName: "clock.badge"
            ))
        }

        // 5. Added This Week (excluding items already in 24h)
        let oneWeekAgo = now.addingTimeInterval(-604800)
        let recentItemsWeek = getRecentItems(movies: movies, series: series, since: oneWeekAgo, until: oneDayAgo)
        if !recentItemsWeek.isEmpty {
            newSections.append(HomeSection(
                id: "added_week",
                type: .mediaCarousel(items: recentItemsWeek),
                title: "Added This Week",
                iconName: "calendar"
            ))
        }

        // 6. Category Spotlights — top 3 movie/series categories by item count
        let categorySpotlights = buildCategorySpotlights(
            movies: movies,
            series: series,
            movieCategories: movieCategories,
            seriesCategories: seriesCategories
        )
        newSections.append(contentsOf: categorySpotlights)

        // 7. Live TV Categories — top 5 by channel count
        let liveTVSections = buildLiveTVCategories(
            liveChannels: liveChannels,
            categories: liveChannelCategories
        )
        newSections.append(contentsOf: liveTVSections)

        sections = newSections
    }

    // MARK: - EPG Section Insertion (deferred)

    /// Insert EPG sections ("Now on TV" + "Coming Up Next") after EPG loads in the background.
    /// Inserts at index 1 (after hero banner) with animation.
    func insertEPGSections(liveChannels: [LiveChannel]? = nil) async {
        let channels = liveChannels ?? storedLiveChannels
        guard let epg = epgService, await epg.isAvailable else { return }

        var epgSections: [HomeSection] = []

        let nowOnTV = await buildNowOnTVSection(liveChannels: channels)
        if !nowOnTV.isEmpty {
            epgSections.append(HomeSection(
                id: "now_on_tv",
                type: .nowOnTV(channels: nowOnTV),
                title: "Now on TV",
                iconName: "antenna.radiowaves.left.and.right"
            ))
        }

        let comingUp = await buildComingUpNextSection(liveChannels: channels)
        if !comingUp.isEmpty {
            epgSections.append(HomeSection(
                id: "coming_up_next",
                type: .comingUpNext(programmes: comingUp),
                title: "Coming Up Next",
                iconName: "clock"
            ))
        }

        guard !epgSections.isEmpty else { return }

        // Insert after hero banner (index 1) with smooth animation
        let insertionIndex = sections.isEmpty ? 0 : min(1, sections.count)
        withAnimation(.easeInOut(duration: 0.4)) {
            sections.insert(contentsOf: epgSections, at: insertionIndex)
        }

        MKSLog.app.info("[HomeViewModel] Inserted \(epgSections.count) EPG sections")
    }

    // MARK: - Continue Watching Section (deferred)

    /// Insert "Continue Watching" section after hero banner.
    /// Call after initial section assembly or when returning to Home.
    func insertContinueWatchingSection(profileId: UUID) async {
        guard let manager = WatchHistoryManager.shared else { return }

        do {
            let items = try await manager.continueWatchingItems(profileId: profileId, limit: 20)
            guard !items.isEmpty else {
                // Remove existing section if no items
                withAnimation(.easeInOut(duration: 0.3)) {
                    sections.removeAll { $0.id == "continue_watching" }
                }
                return
            }

            // Remove existing section before reinserting (refresh)
            sections.removeAll { $0.id == "continue_watching" }

            let section = HomeSection(
                id: "continue_watching",
                type: .continueWatching(items: items),
                title: "Continue Watching",
                iconName: "play.circle"
            )

            // Insert after hero banner (index 1)
            let insertionIndex = sections.isEmpty ? 0 : min(1, sections.count)
            withAnimation(.easeInOut(duration: 0.4)) {
                sections.insert(section, at: insertionIndex)
            }

            MKSLog.app.info("[HomeViewModel] Inserted Continue Watching section with \(items.count) items")
        } catch {
            MKSLog.app.error("[HomeViewModel] Failed to load continue watching: \(error)")
        }
    }

    /// Insert "Recently Watched Channels" section after Continue Watching.
    func insertRecentChannelsSection(profileId: UUID) async {
        guard let manager = WatchHistoryManager.shared else { return }

        do {
            let channels = try await manager.recentChannels(profileId: profileId, limit: 20)
            guard !channels.isEmpty else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    sections.removeAll { $0.id == "recent_channels" }
                }
                return
            }

            sections.removeAll { $0.id == "recent_channels" }

            let section = HomeSection(
                id: "recent_channels",
                type: .recentChannels(channels: channels),
                title: "Recently Watched",
                iconName: "clock.arrow.circlepath"
            )

            // Insert after continue watching (or after hero banner)
            let afterCW = sections.firstIndex(where: { $0.id == "continue_watching" })
            let insertionIndex = (afterCW.map { $0 + 1 }) ?? min(1, sections.count)
            withAnimation(.easeInOut(duration: 0.4)) {
                sections.insert(section, at: insertionIndex)
            }

            MKSLog.app.info("[HomeViewModel] Inserted Recent Channels section with \(channels.count) items")
        } catch {
            MKSLog.app.error("[HomeViewModel] Failed to load recent channels: \(error)")
        }
    }

    // MARK: - Hero Banner

    private func pickHeroBanner(movies: [Movie], series: [Serie]) -> (any LibraryItem)? {
        // Combine top-rated items from both movies and series
        let topMovies = movies
            .filter { ($0.rating5Based ?? 0) >= 3.5 && $0.streamIcon != nil && !($0.streamIcon?.isEmpty ?? true) }
            .sorted { ($0.rating5Based ?? 0) > ($1.rating5Based ?? 0) }
            .prefix(20)

        let topSeries = series
            .filter { $0.rating5Based >= 3.5 && $0.cover != nil && !($0.cover?.isEmpty ?? true) }
            .sorted { $0.rating5Based > $1.rating5Based }
            .prefix(20)

        let candidates: [any LibraryItem] = Array(topMovies) + Array(topSeries)

        guard !candidates.isEmpty else {
            // Fallback: just pick any movie/serie with a cover
            let anyWithCover = movies.first { $0.streamIcon != nil && !($0.streamIcon?.isEmpty ?? true) }
            return anyWithCover ?? series.first { $0.cover != nil && !($0.cover?.isEmpty ?? true) }
        }

        return candidates.randomElement()
    }

    // MARK: - EPG Sections

    private func buildNowOnTVSection(
        liveChannels: [LiveChannel]
    ) async -> [(liveChannel: LiveChannel, epgChannel: EPGChannel?, programme: EPGProgramme)] {
        guard let epg = epgService else { return [] }

        var results: [(LiveChannel, EPGChannel?, EPGProgramme)] = []

        for channel in liveChannels {
            if let programme = await epg.currentProgramme(for: channel.streamId) {
                let epgChId = await epg.matchedEPGChannelId(for: channel.streamId)
                var epgChannel: EPGChannel?
                if let chId = epgChId {
                    epgChannel = await epg.epgChannel(for: chId)
                }
                results.append((channel, epgChannel, programme))
            }
            // Limit to keep the carousel manageable
            if results.count >= 30 { break }
        }

        return results
    }

    private func buildComingUpNextSection(
        liveChannels: [LiveChannel]
    ) async -> [(programme: EPGProgramme, channelName: String)] {
        guard let epg = epgService else { return [] }

        let upcoming = await epg.allUpcomingProgrammes(limit: 20)
        var results: [(EPGProgramme, String)] = []

        // Build a reverse lookup: EPG channel ID → LiveChannel name
        var epgToName: [String: String] = [:]
        for channel in liveChannels {
            if let epgChId = await epg.matchedEPGChannelId(for: channel.streamId) {
                if epgToName[epgChId] == nil {
                    epgToName[epgChId] = channel.name
                }
            }
        }

        for programme in upcoming {
            let channelName = epgToName[programme.channelId] ?? programme.channelId
            results.append((programme, channelName))
        }

        return results
    }

    // MARK: - Recently Added

    private func getRecentItems(
        movies: [Movie],
        series: [Serie],
        since: Date,
        until: Date
    ) -> [any LibraryItem] {
        let sinceTimestamp = since.timeIntervalSince1970
        let untilTimestamp = until.timeIntervalSince1970

        let recentMovies: [any LibraryItem] = movies.filter { movie in
            guard let addedStr = movie.added, let added = Double(addedStr) else { return false }
            return added >= sinceTimestamp && added < untilTimestamp
        }.sorted {
            Double($0.added ?? "0") ?? 0 > Double($1.added ?? "0") ?? 0
        }

        let recentSeries: [any LibraryItem] = series.filter { serie in
            guard let modified = Double(serie.lastModified) else { return false }
            return modified >= sinceTimestamp && modified < untilTimestamp
        }.sorted {
            Double($0.lastModified) ?? 0 > Double($1.lastModified) ?? 0
        }

        // Interleave movies and series, sorted by added time
        let combined = (recentMovies + recentSeries).sorted { a, b in
            let aTime = Double(a.added ?? "0") ?? 0
            let bTime = Double(b.added ?? "0") ?? 0
            return aTime > bTime
        }

        return Array(combined.prefix(30))
    }

    // MARK: - Category Spotlights

    private func buildCategorySpotlights(
        movies: [Movie],
        series: [Serie],
        movieCategories: [MovieCategory],
        seriesCategories: [SeriesCategory]
    ) -> [HomeSection] {
        // Count items per movie category
        var movieCategoryCounts: [String: Int] = [:]
        for movie in movies {
            movieCategoryCounts[movie.categoryId, default: 0] += 1
        }

        // Count items per series category
        var seriesCategoryCounts: [String: Int] = [:]
        for serie in series {
            seriesCategoryCounts[serie.categoryId, default: 0] += 1
        }

        // Merge and find top 3 categories
        struct CategoryInfo {
            let id: String
            let name: String
            let count: Int
            let isMovie: Bool
        }

        var allCategories: [CategoryInfo] = []

        for cat in movieCategories {
            let count = movieCategoryCounts[cat.categoryId] ?? 0
            if count > 0 {
                allCategories.append(CategoryInfo(id: cat.categoryId, name: cat.categoryName, count: count, isMovie: true))
            }
        }
        for cat in seriesCategories {
            let count = seriesCategoryCounts[cat.categoryId] ?? 0
            if count > 0 {
                allCategories.append(CategoryInfo(id: cat.categoryId, name: cat.categoryName, count: count, isMovie: false))
            }
        }

        let top3 = allCategories.sorted { $0.count > $1.count }.prefix(3)

        return top3.map { cat in
            let items: [any LibraryItem]
            if cat.isMovie {
                items = movies.filter { $0.categoryId == cat.id }.prefix(20).map { $0 as any LibraryItem }
            } else {
                items = series.filter { $0.categoryId == cat.id }.prefix(20).map { $0 as any LibraryItem }
            }

            return HomeSection(
                id: "category_\(cat.id)",
                type: .mediaCarousel(items: items),
                title: cat.name,
                iconName: "square.grid.2x2"
            )
        }
    }

    // MARK: - Live TV Categories

    /// Keywords that indicate a sports-related category (lowercased)
    private static let sportsKeywords: Set<String> = [
        "deport", "futbol", "football", "soccer", "sport",
        "basket", "tennis", "f1", "motor", "liga", "premier",
        "champions", "ufc", "boxeo", "golf", "rugby", "nba",
        "nfl", "mlb", "nhl", "cricket", "padel", "ciclismo"
    ]

    /// Returns true if the category name (lowercased) contains any sports keyword
    private func isSportsCategory(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return Self.sportsKeywords.contains { lowered.contains($0) }
    }

    private func buildLiveTVCategories(
        liveChannels: [LiveChannel],
        categories: [LiveChannelCategory]
    ) -> [HomeSection] {
        // Count channels per category
        var categoryCounts: [String: Int] = [:]
        for channel in liveChannels {
            if let catId = channel.categoryId {
                categoryCounts[catId, default: 0] += 1
            }
        }

        // Partition into sports and non-sports, each sorted by channel count
        let sortedCategories = categories
            .filter { (categoryCounts[$0.categoryId] ?? 0) > 0 }
            .sorted { (categoryCounts[$0.categoryId] ?? 0) > (categoryCounts[$1.categoryId] ?? 0) }

        let sports = sortedCategories.filter { isSportsCategory($0.categoryName) }
        let nonSports = sortedCategories.filter { !isSportsCategory($0.categoryName) }

        // Sports get up to 2 top slots, remaining 3 filled by highest-count non-sports
        let topSports = Array(sports.prefix(2))
        let topNonSports = Array(nonSports.prefix(5 - topSports.count))
        let finalCategories = topSports + topNonSports

        return finalCategories.compactMap { cat in
            let channels = liveChannels.filter { $0.categoryId == cat.categoryId }.prefix(20)
            guard !channels.isEmpty else { return nil }

            let icon = isSportsCategory(cat.categoryName) ? "soccerball" : "play.tv"

            return HomeSection(
                id: "live_\(cat.categoryId)",
                type: .liveTVCategory(channels: Array(channels), categoryName: cat.categoryName),
                title: cat.categoryName,
                iconName: icon
            )
        }
    }

    // MARK: - Metadata Prefetch

    /// Prefetch enriched metadata for Home-visible items in background.
    ///
    /// Priority order:
    /// 1. Hero banner item (single, highest visibility)
    /// 2. First 10 items of each media carousel section
    ///
    /// Uses ``EnrichedMediaStore`` which deduplicates and caches results.
    func prefetchMetadata() async {
        let store = EnrichedMediaStore.shared

        // Priority 1: Hero banner
        for section in sections {
            if case .heroBanner(let item) = section.type {
                let tmdbId = (item as? Movie)?.tmdbId.flatMap { Int($0) }
                _ = await store.getEnrichedMetadata(for: item, tmdbId: tmdbId)
                break
            }
        }

        // Priority 2: Carousel items (first 10 per section, concurrent)
        for section in sections {
            if case .mediaCarousel(let items) = section.type {
                await store.prefetch(items: Array(items.prefix(10)))
            }
        }

        MKSLog.app.info("[HomeViewModel] Metadata prefetch completed")
    }
}

//
//  LiveTVViewModel.swift
//  mks-multiplataforma-tvos-iptv
//
//  Loads live channels + categories from IPTVService with disk-based SWR cache.
//

import Foundation
import SwiftUI
import IPTVCore

@MainActor
final class LiveTVViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var featured: LiveChannel?
    @Published private(set) var sections: [ChannelSection] = []
    @Published private(set) var isRefreshing = false

    struct ChannelSection: Identifiable, Equatable {
        let id: String
        let title: String
        let channels: [LiveChannel]
    }

    func loadIfNeeded(profile: IPTVProfile) async {
        guard case .idle = state else { return }

        let cache = TVCacheManager.shared

        async let channelsResult = cache.cachedLiveChannels()
        async let catsResult     = cache.cachedLiveChannelCategories()
        let (channelsCache, cats) = await (channelsResult, catsResult)

        if let channelsCache, let cats {
            populateUI(channels: channelsCache.value, categories: cats.value)
            state = .loaded

            if channelsCache.isStale || cats.isStale {
                isRefreshing = true
                await refreshFromNetwork(profile: profile, silent: true)
                isRefreshing = false
            }
        } else {
            await load(profile: profile)
        }
    }

    func load(profile: IPTVProfile) async {
        state = .loading
        await refreshFromNetwork(profile: profile, silent: false)
    }

    // MARK: - Private

    private func refreshFromNetwork(profile: IPTVProfile, silent: Bool) async {
        let service = IPTVService(profile: profile)
        do {
            async let channelsTask    = service.fetchLiveChannels()
            async let categoriesTask  = service.fetchLiveChannelsCategories()
            let (channels, categories) = try await (channelsTask, categoriesTask)

            MKSLog.app.info("LiveVM fetched \(channels.count) channels, \(categories.count) categories")

            let cache = TVCacheManager.shared
            await cache.cacheLiveChannels(channels)
            await cache.cacheLiveChannelCategories(categories)

            populateUI(channels: channels, categories: categories)
            state = .loaded
        } catch {
            MKSLog.app.error("LiveVM refresh failed: \(error)")
            if !silent {
                state = .failed("\(error)")
            }
        }
    }

    private func populateUI(channels: [LiveChannel], categories: [LiveChannelCategory]) {
        featured = channels
            .filter { ($0.streamIcon?.isEmpty == false) && ($0.isAdult ?? "0") != "1" }
            .randomElement()
            ?? channels.first
        sections = buildSections(channels: channels, categories: categories)
    }

    private func buildSections(channels: [LiveChannel], categories: [LiveChannelCategory]) -> [ChannelSection] {
        var sections: [ChannelSection] = []

        let popular = channels
            .filter { $0.streamIcon?.isEmpty == false }
            .shuffled()
            .prefix(20)
        if !popular.isEmpty {
            sections.append(.init(id: "popular", title: "Popular Now", channels: Array(popular)))
        }

        let grouped = Dictionary(grouping: channels.filter { ($0.isAdult ?? "0") != "1" },
                                 by: { $0.categoryId ?? "0" })
        let topCategories = categories
            .map { ($0, grouped[$0.id]?.count ?? 0) }
            .filter { $0.1 >= 5 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        for (cat, _) in topCategories {
            let items = grouped[cat.id] ?? []
            sections.append(.init(
                id: "cat-\(cat.id)",
                title: cat.categoryName,
                channels: Array(items.prefix(20))
            ))
        }

        return sections
    }
}

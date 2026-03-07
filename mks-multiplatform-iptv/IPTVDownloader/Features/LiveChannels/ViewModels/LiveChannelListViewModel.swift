//
//  LiveChannelListViewModel.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 16/1/25.
//

import Foundation
import os

@MainActor
class LiveChannelListViewModel: ObservableObject {
    // NOTE: This view model always uses the active IPTVProfile.
    let profile: IPTVProfile

    @Published private(set) var liveChannels: [LiveChannel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let liveChannelService: MovieService
    private let cacheManager = CacheManager.shared
    private var didLoadChannels = false
    private let logger = Logger(subsystem: "LiveChannelListViewModel", category: "LiveTV")

    init(profile: IPTVProfile, liveChannelService: MovieService? = nil) {
        self.profile = profile
        self.liveChannelService = liveChannelService ?? MovieService(profile: profile)
        logger.info("🟢 LiveChannelListViewModel initialized with profile: \(profile.name)")
    }

    func loadChannels() async {
        guard !didLoadChannels else {
            logger.debug("📋 Channels already loaded, skipping...")
            return
        }

        // SWR: try cache first
        if let cached = cacheManager.getCachedLiveChannelsSWR() {
            logger.info("📦 Loaded \(cached.value.count) channels from cache (stale: \(cached.isStale))")
            liveChannels = orderByAddedDesc(cached.value)
            didLoadChannels = true

            if cached.isStale {
                Task { await refreshChannelsInBackground() }
            }
            return
        }

        // No cache: fetch from network
        logger.info("🔄 Starting to load live channels from network...")
        isLoading = true
        error = nil

        do {
            logger.debug("📡 Fetching channels from API...")
            let fetched = try await liveChannelService.fetchLiveChannels()
            logger.info("✅ Fetched \(fetched.count) channels successfully")

            liveChannels = orderByAddedDesc(fetched)
            didLoadChannels = true
            cacheManager.cacheLiveChannels(fetched)
            logger.debug("💾 Channels cached to disk")
        } catch {
            logger.error("❌ Failed to load channels: \(error.localizedDescription)")
            self.error = error
        }

        isLoading = false
    }

    func refreshChannels() async {
        logger.info("🔄 Refreshing channels...")
        didLoadChannels = false
        isLoading = true
        error = nil

        do {
            let fetched = try await liveChannelService.fetchLiveChannels()
            liveChannels = orderByAddedDesc(fetched)
            didLoadChannels = true
            cacheManager.cacheLiveChannels(fetched)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Background refresh: silently fetch from network and update cache + published array
    private func refreshChannelsInBackground() async {
        logger.info("🔄 Background-refreshing live channels...")
        do {
            let fetched = try await liveChannelService.fetchLiveChannels()
            liveChannels = orderByAddedDesc(fetched)
            cacheManager.cacheLiveChannels(fetched)
            logger.info("✅ Background refresh: \(fetched.count) channels updated")
        } catch {
            logger.error("⚠️ Background refresh failed (non-fatal): \(error.localizedDescription)")
        }
    }

    func filterChannels(searchText: String) -> [LiveChannel] {
        guard !searchText.isEmpty else {
            return self.liveChannels
        }

        return self.liveChannels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    func getChannel(by id: Int) -> LiveChannel? {
        return liveChannels.first { $0.id == id }
    }

    // Sorting methods

    func orderByNameAlphabeticallyAsc(_ channels: [LiveChannel]) -> [LiveChannel] {
        return channels.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func orderByNameAlphabeticallyDesc(_ channels: [LiveChannel]) -> [LiveChannel] {
        return channels.sorted { $0.name.lowercased() > $1.name.lowercased() }
    }

    func orderByAddedAsc(_ channels: [LiveChannel]) -> [LiveChannel] {
        return channels.sorted { (c1: LiveChannel, c2: LiveChannel) -> Bool in
            guard let date1 = Double(c1.added), let date2 = Double(c2.added) else {
                return false
            }
            return date1 < date2
        }
    }

    func orderByAddedDesc(_ channels: [LiveChannel]) -> [LiveChannel] {
        return channels.sorted { (c1: LiveChannel, c2: LiveChannel) -> Bool in
            guard let date1 = Double(c1.added), let date2 = Double(c2.added) else {
                return false
            }
            return date1 > date2
        }
    }

    func loadExampleChannels(_ channels: [LiveChannel]) {
        self.liveChannels = channels
    }

    // Method to apply a specific sorting
    func applySort(_ sortMethod: ([LiveChannel]) -> [LiveChannel]) {
        liveChannels = sortMethod(liveChannels)
    }
}


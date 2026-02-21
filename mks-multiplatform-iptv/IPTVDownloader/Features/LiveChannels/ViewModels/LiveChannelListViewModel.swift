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

        logger.info("🔄 Starting to load live channels...")
        isLoading = true
        error = nil

        do {
            logger.debug("📡 Fetching channels from API...")
            liveChannels = try await liveChannelService.fetchLiveChannels()
            logger.info("✅ Fetched \(self.liveChannels.count) channels successfully")
            
            liveChannels = orderByAddedDesc(liveChannels) // Apply default sorting
            logger.debug("📊 Channels sorted by added date")
            
            didLoadChannels = true
            logger.info("🏁 Channel loading completed")
        } catch {
            logger.error("❌ Failed to load channels: \(error.localizedDescription)")
            self.error = error
        }

        isLoading = false
    }

    func refreshChannels() async {
        logger.info("🔄 Refreshing channels...")
        didLoadChannels = false
        await loadChannels()
    }

    func filterChannels(searchText: String) -> [LiveChannel] {
        logger.debug("🔍 filterChannels called with searchText: '\(searchText)'")
        logger.debug("🔍 liveChannels.count = \(self.liveChannels.count)")
        
        guard !searchText.isEmpty else { 
            logger.debug("🔍 searchText is empty, returning all \(self.liveChannels.count) channels")
            return self.liveChannels 
        }
        
        logger.debug("🔍 Filtering channels with search text: '\(searchText)'")
        let filtered = self.liveChannels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(searchText)
        }
        logger.debug("🔍 Filtered result: \(filtered.count) channels")
        return filtered
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
    
    func loadLiveChannels() async {
        guard !didLoadChannels else { return }
        
        isLoading = true
        error = nil
        
        do {
            liveChannels = try await liveChannelService.fetchLiveChannels()
            liveChannels = orderByAddedDesc(liveChannels) // Apply default sorting
            didLoadChannels = true
        } catch {
            self.error = error
        }
        
        isLoading = false
    }

    // Method to apply a specific sorting
    func applySort(_ sortMethod: ([LiveChannel]) -> [LiveChannel]) {
        liveChannels = sortMethod(liveChannels)
    }
}


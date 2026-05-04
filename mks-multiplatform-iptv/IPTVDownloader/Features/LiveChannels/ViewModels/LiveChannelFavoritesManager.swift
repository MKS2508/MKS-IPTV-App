//
//  LiveChannelFavoritesManager.swift
//  mks-multiplatform-iptv
//
//  Manages favorite live channels with UserDefaults persistence.
//  Provides ObservableObject for SwiftUI integration.
//

import Foundation
import Combine
import os
import IPTVCore

// MARK: - Live Channel Favorites Manager

/// Manages favorite live channels with persistent storage.
/// Uses UserDefaults for persistence and publishes changes for SwiftUI.
class LiveChannelFavoritesManager: ObservableObject {
    // MARK: - Singleton

    /// Shared instance for app-wide access
    static let shared = LiveChannelFavoritesManager()

    // MARK: - Published Properties

    /// Set of favorite channel stream IDs
    @Published private(set) var favoriteIds: Set<Int> = []

    // MARK: - Private Properties

    private let userDefaultsKey = "liveChannelFavorites"
    private let logger = Logger(subsystem: "LiveChannelFavoritesManager", category: "Favorites")
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        loadFromStorage()
        logger.info("Initialized with \(self.favoriteIds.count) favorites")
    }

    // MARK: - Public API

    /// Checks if a channel is marked as favorite
    /// - Parameter streamId: The channel's stream ID
    /// - Returns: Whether the channel is a favorite
    func isFavorite(_ streamId: Int) -> Bool {
        favoriteIds.contains(streamId)
    }

    /// Toggles the favorite status of a channel
    /// - Parameter streamId: The channel's stream ID
    func toggleFavorite(_ streamId: Int) {
        if favoriteIds.contains(streamId) {
            removeFavorite(streamId)
        } else {
            addFavorite(streamId)
        }
    }

    /// Adds a channel to favorites
    /// - Parameter streamId: The channel's stream ID
    func addFavorite(_ streamId: Int) {
        guard !favoriteIds.contains(streamId) else { return }

        favoriteIds.insert(streamId)
        saveToStorage()
        logger.debug("Added favorite: \(streamId)")
    }

    /// Removes a channel from favorites
    /// - Parameter streamId: The channel's stream ID
    func removeFavorite(_ streamId: Int) {
        guard favoriteIds.contains(streamId) else { return }

        favoriteIds.remove(streamId)
        saveToStorage()
        logger.debug("Removed favorite: \(streamId)")
    }

    /// Returns the list of favorite stream IDs sorted
    /// - Returns: Array of favorite stream IDs
    func sortedFavorites() -> [Int] {
        Array(favoriteIds).sorted()
    }

    /// Clears all favorites
    func clearAllFavorites() {
        guard !favoriteIds.isEmpty else { return }

        let count = favoriteIds.count
        favoriteIds.removeAll()
        saveToStorage()
        logger.info("Cleared \(count) favorites")
    }

    // MARK: - Persistence

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) else {
            logger.debug("No saved favorites found")
            return
        }

        favoriteIds = decoded
    }

    private func saveToStorage() {
        guard let encoded = try? JSONEncoder().encode(self.favoriteIds) else {
            logger.error("Failed to encode favorites")
            return
        }

        UserDefaults.standard.set(encoded, forKey: self.userDefaultsKey)
        logger.debug("Saved \(self.favoriteIds.count) favorites to storage")
    }
}

// MARK: - Convenience Extensions

extension LiveChannelFavoritesManager {
    /// Filters an array of channels to return only favorites
    /// - Parameter channels: Array of channels to filter
    /// - Returns: Array of channels marked as favorite
    func filterFavorites(_ channels: [LiveChannel]) -> [LiveChannel] {
        channels.filter { self.favoriteIds.contains($0.streamId) }
    }

    /// Checks how many of the given channels are favorites
    /// - Parameter channels: Array of channels to check
    /// - Returns: Count of favorite channels
    func favoriteCount(in channels: [LiveChannel]) -> Int {
        channels.filter { self.favoriteIds.contains($0.streamId) }.count
    }
}

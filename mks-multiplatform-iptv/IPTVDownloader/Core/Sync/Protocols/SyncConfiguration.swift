//
//  SyncConfiguration.swift
//  mks-multiplatform-iptv
//
//  Persisted configuration for iCloud sync preferences.
//

import Foundation
import IPTVCore

/// Stores user preferences for CloudKit synchronization.
///
/// Configuration is persisted in `UserDefaults` and loaded at app launch.
struct SyncConfiguration: Codable {
    /// Whether iCloud sync is enabled by the user.
    var isEnabled: Bool

    /// The date of the last successful sync, if any.
    var lastSyncDate: Date?

    /// Server change token data for incremental fetches.
    var serverChangeTokenData: Data?

    // MARK: - UserDefaults Keys

    private static let storageKey = "iptv_sync_configuration"

    // MARK: - Persistence

    /// Loads the sync configuration from UserDefaults.
    /// Returns a default configuration if none is persisted.
    static func load() -> SyncConfiguration {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(SyncConfiguration.self, from: data)
        else {
            return SyncConfiguration(isEnabled: true, lastSyncDate: nil, serverChangeTokenData: nil)
        }
        return config
    }

    /// Saves the sync configuration to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SyncConfiguration.storageKey)
        }
    }

    /// Updates the last sync date and persists the configuration.
    mutating func recordSync() {
        lastSyncDate = Date()
        save()
    }

    /// Stores the server change token for incremental CloudKit fetches.
    /// - Parameter token: The `CKServerChangeToken` to persist.
    mutating func storeChangeToken(_ tokenData: Data?) {
        serverChangeTokenData = tokenData
        save()
    }
}

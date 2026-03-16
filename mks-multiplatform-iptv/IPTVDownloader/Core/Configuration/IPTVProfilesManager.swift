import Foundation
import SwiftUI

/// Model and persistence for all IPTV profiles, handles active selection
typealias ProfileID = UUID

@MainActor
class IPTVProfilesManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var profiles: [IPTVProfile] = []
    @Published var activeProfileID: ProfileID? = nil

    /// Sync status for UI display
    @Published private(set) var syncStatus: SyncStatus = .idle

    /// Whether iCloud sync is enabled.
    /// Defaults to false — CloudKit entitlements must be active before enabling.
    @Published var isSyncEnabled: Bool = false {
        didSet {
            syncManager.isSyncEnabled = isSyncEnabled
            if isSyncEnabled {
                Task { await syncProfiles() }
            }
        }
    }

    // MARK: - Private Properties

    private let profilesKey = "iptv_profiles"
    private let activeProfileKey = "iptv_active_profile"

    /// CloudKit sync manager
    private let syncManager = ProfileSyncManager()

    // MARK: - Singleton

    static let shared = IPTVProfilesManager()

    private init() {
        loadProfiles()
        loadSyncConfiguration()
    }

    // MARK: - Profile Management

    func loadProfiles() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let loaded = try? decoder.decode([IPTVProfile].self, from: data)
        {
            self.profiles = loaded
        } else {
            self.profiles = []
        }

        if let idString = UserDefaults.standard.string(forKey: activeProfileKey),
           let id = UUID(uuidString: idString)
        {
            self.activeProfileID = id
        } else {
            self.activeProfileID = profiles.first?.id
        }
    }

    func saveProfiles() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
        }
    }

    func addProfile(_ profile: IPTVProfile) {
        profiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()

        // Sync to CloudKit
        Task {
            await syncProfileToCloud(profile)
        }
    }

    func updateProfile(_ profile: IPTVProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            saveProfiles()

            // Sync to CloudKit
            Task {
                await syncProfileToCloud(profile)
            }
        }
    }

    func deleteProfile(_ id: ProfileID) {
        // Get profile before deletion for CloudKit sync
        let profileToDelete = profiles.first { $0.id == id }

        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        saveProfiles()

        // Delete from CloudKit
        if let profile = profileToDelete {
            Task {
                await deleteProfileFromCloud(profile)
            }
        }
    }

    func selectProfile(_ id: ProfileID) {
        activeProfileID = id
        saveProfiles()
    }

    var activeProfile: IPTVProfile? {
        profiles.first(where: { $0.id == activeProfileID })
    }

    // MARK: - CloudKit Sync

    /// Loads sync configuration from persisted storage.
    private func loadSyncConfiguration() {
        let config = SyncConfiguration.load()
        self.isSyncEnabled = config.isEnabled
    }

    /// Performs a full sync with CloudKit.
    ///
    /// This pulls remote profiles, merges with local, and pushes changes.
    func syncProfiles() async {
        guard isSyncEnabled else { return }

        do {
            let syncedProfiles = try await syncManager.syncProfiles(local: profiles)
            self.profiles = syncedProfiles
            self.syncStatus = syncManager.syncStatus
            saveProfiles()
        } catch {
            self.syncStatus = syncManager.syncStatus
        }
    }

    /// Syncs a single profile to CloudKit.
    private func syncProfileToCloud(_ profile: IPTVProfile) async {
        guard isSyncEnabled else { return }

        do {
            try await syncManager.pushProfile(profile)
            self.syncStatus = syncManager.syncStatus
        } catch {
            self.syncStatus = syncManager.syncStatus
        }
    }

    /// Deletes a profile from CloudKit.
    private func deleteProfileFromCloud(_ profile: IPTVProfile) async {
        guard isSyncEnabled else { return }

        do {
            try await syncManager.deleteProfile(profile)
            self.syncStatus = syncManager.syncStatus
        } catch {
            self.syncStatus = syncManager.syncStatus
        }
    }

    /// Forces a sync of pending changes (useful after coming back online).
    func syncPendingChanges() async {
        guard isSyncEnabled else { return }

        do {
            try await syncManager.syncPendingChanges(localProfiles: profiles)
            self.syncStatus = syncManager.syncStatus
        } catch {
            self.syncStatus = syncManager.syncStatus
        }
    }

    /// Pulls remote profiles from CloudKit and merges with local.
    func pullRemoteProfiles() async {
        guard isSyncEnabled else { return }

        do {
            let remoteProfiles = try await syncManager.pullRemoteProfiles()

            // Merge with local profiles using last-modified-wins
            for remote in remoteProfiles {
                if let localIndex = profiles.firstIndex(where: { $0.id == remote.id }) {
                    let local = profiles[localIndex]
                    let resolved = syncManager.resolveConflict(local: local, remote: remote)
                    profiles[localIndex] = resolved
                } else {
                    // Remote-only profile, add to local
                    profiles.append(remote)
                }
            }

            saveProfiles()
            self.syncStatus = syncManager.syncStatus
        } catch {
            self.syncStatus = syncManager.syncStatus
        }
    }

    /// Returns the last sync date for UI display.
    var lastSyncDate: Date? {
        get async { await syncManager.lastSyncDate }
    }

    /// Returns the number of pending changes waiting to sync.
    var pendingChangesCount: Int {
        syncManager.pendingChangesCount
    }
}

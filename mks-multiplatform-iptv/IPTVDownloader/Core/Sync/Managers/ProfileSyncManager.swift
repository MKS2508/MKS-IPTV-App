//
//  ProfileSyncManager.swift
//  mks-multiplatform-iptv
//
//  Facade for CloudKit profile synchronization.
//

import Foundation
import CloudKit

/// Manages CloudKit synchronization for IPTV profiles.
///
/// This is the primary interface used by `IPTVProfilesManager` to sync profiles.
/// It wraps `CloudKitSyncEngine` and provides a higher-level API with
/// conflict resolution, status tracking, and pending change management.
///
/// When iCloud is unavailable (no entitlements or not signed in), all operations
/// gracefully fail and set `syncStatus` to `.unavailable`.
@MainActor
final class ProfileSyncManager {
    // MARK: - Properties

    /// Current sync status for UI binding.
    private(set) var syncStatus: SyncStatus = .idle

    /// Whether sync is enabled by the user.
    var isSyncEnabled: Bool = true

    /// The date of the last successful sync.
    var lastSyncDate: Date? {
        get async { await engine.lastSyncDate }
    }

    /// Number of profiles pending sync (tracked in UserDefaults).
    var pendingChangesCount: Int {
        pendingProfileIDs.count
    }

    // MARK: - Private Properties

    /// The CloudKit sync engine (actor-isolated).
    private let engine = CloudKitSyncEngine()

    /// Conflict resolver using last-modified-wins strategy.
    private let conflictResolver = SyncConflictResolver<IPTVProfile>(strategy: .lastModifiedWins)

    /// UserDefaults key for pending changes.
    private let pendingKey = "iptv_sync_pending_ids"

    /// IDs of profiles with local changes not yet synced.
    private var pendingProfileIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: pendingKey)
        }
    }

    // MARK: - Public API

    /// Performs a full sync: pushes local profiles and pulls remote ones.
    ///
    /// - Parameter local: The current local profiles.
    /// - Returns: The merged profile list after sync.
    /// - Throws: `SyncError` if sync fails entirely.
    func syncProfiles(local: [IPTVProfile]) async throws -> [IPTVProfile] {
        guard isSyncEnabled else { return local }

        syncStatus = .syncing("Preparing sync...")

        do {
            // Push local profiles
            syncStatus = .syncing("Uploading profiles...")
            let records = local.map { $0.toRecord(in: CloudKitContainer.zoneID) }
            if !records.isEmpty {
                _ = try await engine.saveRecords(records)
            }

            // Pull remote profiles
            syncStatus = .syncing("Downloading profiles...")
            let remoteRecords = try await engine.fetchRecords(ofType: CloudKitRecordTypes.profile)
            let remoteProfiles = remoteRecords.compactMap { IPTVProfile.fromRecord($0) }

            // Merge local and remote
            var merged = local
            for remote in remoteProfiles {
                if let localIndex = merged.firstIndex(where: { $0.id == remote.id }) {
                    let resolved = conflictResolver.resolve(local: merged[localIndex], remote: remote)
                    merged[localIndex] = resolved
                } else {
                    merged.append(remote)
                }
            }

            // Clear pending changes
            pendingProfileIDs.removeAll()
            await engine.recordSuccessfulSync()

            let now = Date()
            syncStatus = .synced(now)
            return merged

        } catch let error as SyncError {
            handleSyncError(error)
            throw error
        } catch {
            let syncError = SyncError.unknown(error.localizedDescription)
            handleSyncError(syncError)
            throw syncError
        }
    }

    /// Pushes a single profile to CloudKit.
    ///
    /// - Parameter profile: The profile to push.
    /// - Throws: `SyncError` on failure.
    func pushProfile(_ profile: IPTVProfile) async throws {
        guard isSyncEnabled else { return }

        syncStatus = .syncing(nil)

        do {
            profile.touchModifiedDate()
            let record = profile.toRecord(in: CloudKitContainer.zoneID)
            try await engine.saveRecord(record)
            pendingProfileIDs.remove(profile.id.uuidString)
            await engine.recordSuccessfulSync()
            syncStatus = .synced(Date())
        } catch {
            // Queue for later sync
            pendingProfileIDs.insert(profile.id.uuidString)
            let syncError = (error as? SyncError) ?? .unknown(error.localizedDescription)
            handleSyncError(syncError)
            throw syncError
        }
    }

    /// Deletes a profile from CloudKit.
    ///
    /// - Parameter profile: The profile to delete remotely.
    /// - Throws: `SyncError` on failure.
    func deleteProfile(_ profile: IPTVProfile) async throws {
        guard isSyncEnabled else { return }

        syncStatus = .syncing(nil)

        do {
            let recordID = CKRecord.ID(
                recordName: profile.id.uuidString,
                zoneID: CloudKitContainer.zoneID
            )
            try await engine.deleteRecord(recordID)
            pendingProfileIDs.remove(profile.id.uuidString)
            syncStatus = .synced(Date())
        } catch {
            let syncError = (error as? SyncError) ?? .unknown(error.localizedDescription)
            handleSyncError(syncError)
            throw syncError
        }
    }

    /// Syncs any profiles that failed to sync previously.
    ///
    /// - Parameter localProfiles: The current local profiles.
    /// - Throws: `SyncError` on failure.
    func syncPendingChanges(localProfiles: [IPTVProfile]) async throws {
        guard isSyncEnabled, !pendingProfileIDs.isEmpty else { return }

        syncStatus = .syncing("Syncing pending changes...")

        let pendingProfiles = localProfiles.filter { pendingProfileIDs.contains($0.id.uuidString) }

        do {
            let records = pendingProfiles.map { $0.toRecord(in: CloudKitContainer.zoneID) }
            if !records.isEmpty {
                _ = try await engine.saveRecords(records)
            }
            pendingProfileIDs.removeAll()
            await engine.recordSuccessfulSync()
            syncStatus = .synced(Date())
        } catch {
            let syncError = (error as? SyncError) ?? .unknown(error.localizedDescription)
            handleSyncError(syncError)
            throw syncError
        }
    }

    /// Pulls all profiles from CloudKit.
    ///
    /// - Returns: An array of remote profiles.
    /// - Throws: `SyncError` on failure.
    func pullRemoteProfiles() async throws -> [IPTVProfile] {
        guard isSyncEnabled else { return [] }

        syncStatus = .syncing("Fetching remote profiles...")

        do {
            let records = try await engine.fetchRecords(ofType: CloudKitRecordTypes.profile)
            let profiles = records.compactMap { IPTVProfile.fromRecord($0) }
            await engine.recordSuccessfulSync()
            syncStatus = .synced(Date())
            return profiles
        } catch {
            let syncError = (error as? SyncError) ?? .unknown(error.localizedDescription)
            handleSyncError(syncError)
            throw syncError
        }
    }

    /// Resolves a conflict between local and remote profiles.
    ///
    /// - Parameters:
    ///   - local: The local version.
    ///   - remote: The remote version.
    /// - Returns: The winning version.
    func resolveConflict(local: IPTVProfile, remote: IPTVProfile) -> IPTVProfile {
        conflictResolver.resolve(local: local, remote: remote)
    }

    // MARK: - Private

    /// Maps sync errors to appropriate status values.
    private func handleSyncError(_ error: SyncError) {
        switch error {
        case .accountNotAvailable, .permissionDenied:
            syncStatus = .unavailable
        case .networkError:
            syncStatus = .offline
        default:
            syncStatus = .error(error.localizedDescription ?? "Unknown error")
        }
    }
}

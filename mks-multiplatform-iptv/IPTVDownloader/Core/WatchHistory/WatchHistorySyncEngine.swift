//
//  WatchHistorySyncEngine.swift
//  mks-multiplatform-iptv
//
//  Cross-device watch history sync using CloudKit directly (CKModifyRecordsOperation +
//  CKFetchRecordZoneChangesOperation), bypassing NSPersistentCloudKitContainer.
//
//  Architecture:
//  ┌─────────────────────────────────────────────────────────────────┐
//  │  SwiftData (local, cloudKitDatabase: .none)                     │
//  │  WatchHistoryEntry / RecentChannelEntry                         │
//  └────────────────────┬────────────────────────────────────────────┘
//                       │ read/write via WatchHistoryManager (@ModelActor)
//  ┌─────────────────────▼────────────────────────────────────────────┐
//  │  WatchHistorySyncEngine (actor)                                  │
//  │  • pull()  — on app foreground / launch (fetch zone changes)     │
//  │  • schedulePush() — debounced 30s after any local write          │
//  │  • push()  — on app background / explicit call                   │
//  └─────────────────────┬────────────────────────────────────────────┘
//                        │ CKModifyRecordsOperation / CKFetchRecordZoneChanges
//  ┌──────────────────────▼───────────────────────────────────────────┐
//  │  CloudKit private database  (iCloud.com.mks.iptv)                │
//  │  Zone: IPTVProfilesZone                                          │
//  │  Record types: WatchHistoryEntry, RecentChannelEntry             │
//  └──────────────────────────────────────────────────────────────────┘
//
//  Conflict resolution: last-write-wins on `lastModifiedDate`.
//  Push policy: .changedKeys (only modified fields are sent to CloudKit).

import Foundation
import CloudKit
import SwiftData

actor WatchHistorySyncEngine {

    // MARK: - Singleton

    static let shared = WatchHistorySyncEngine()

    // MARK: - State

    /// Persisted server change token for incremental fetches.
    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.tokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    private static let tokenKey = "watchhistory_ck_zone_token"

    /// Debounce task for push — resets on every `schedulePush()` call.
    private var pendingPushTask: Task<Void, Never>?

    /// Prevents concurrent pull operations.
    private var isPulling = false

    /// Prevents concurrent push operations.
    private var isPushing = false

    // MARK: - Public API

    /// Pull remote changes from CloudKit and merge into local SwiftData store.
    ///
    /// Uses `CKFetchRecordZoneChangesOperation` with a persisted server change token
    /// so only records changed since the last pull are fetched.
    /// Call on app foreground and app launch (after a small delay to not block UI).
    func pull() async {
        guard !isPulling else { return }
        isPulling = true
        defer { isPulling = false }

        do {
            try await CloudKitContainer.ensureAvailable()
        } catch {
            MKSLog.app.info("[WatchHistorySync] iCloud unavailable, skipping pull: \(error.localizedDescription)")
            return
        }

        MKSLog.app.info("[WatchHistorySync] Starting pull (token: \(serverChangeToken != nil ? "incremental" : "full"))")

        do {
            try await CloudKitContainer.ensureZoneExists()
            let (watchEntries, channelEntries, newToken) = try await fetchZoneChanges()

            guard !watchEntries.isEmpty || !channelEntries.isEmpty else {
                MKSLog.app.info("[WatchHistorySync] Pull complete — no remote changes")
                if let token = newToken { serverChangeToken = token }
                return
            }

            MKSLog.app.info("[WatchHistorySync] Merging \(watchEntries.count) watch + \(channelEntries.count) channel records")
            try await mergeIntoLocalStore(watchEntries: watchEntries, channelEntries: channelEntries)

            if let token = newToken { serverChangeToken = token }
            MKSLog.app.info("[WatchHistorySync] Pull complete")
        } catch {
            MKSLog.app.error("[WatchHistorySync] Pull failed: \(error.localizedDescription)")
        }
    }

    /// Schedule a debounced push 30 seconds from now.
    ///
    /// Called by `WatchHistoryManager` after every local write so that rapid
    /// position saves during playback (~every 12s) coalesce into a single
    /// CloudKit operation per ~30s window.
    func schedulePush() {
        pendingPushTask?.cancel()
        pendingPushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    /// Push all local watch history to CloudKit immediately.
    ///
    /// Call on app background / explicit user request.
    /// Cancels any pending debounced push first.
    func pushNow() async {
        pendingPushTask?.cancel()
        pendingPushTask = nil
        await push()
    }

    // MARK: - Private: Fetch

    private func fetchZoneChanges() async throws -> (watch: [CKRecord], channels: [CKRecord], token: CKServerChangeToken?) {
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = serverChangeToken

        return try await withCheckedThrowingContinuation { continuation in
            var watchRecords: [CKRecord] = []
            var channelRecords: [CKRecord] = []
            var finalToken: CKServerChangeToken?

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [CloudKitContainer.zoneID],
                configurationsByRecordZoneID: [CloudKitContainer.zoneID: config]
            )

            operation.recordWasChangedBlock = { _, result in
                guard case .success(let record) = result else { return }
                switch record.recordType {
                case CloudKitRecordTypes.watchHistoryEntry:
                    watchRecords.append(record)
                case CloudKitRecordTypes.recentChannelEntry:
                    channelRecords.append(record)
                default:
                    break
                }
            }

            operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
                finalToken = token
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: (watchRecords, channelRecords, finalToken))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            CloudKitContainer.privateDatabase.add(operation)
        }
    }

    // MARK: - Private: Merge (pull → local)

    private func mergeIntoLocalStore(watchEntries: [CKRecord], channelEntries: [CKRecord]) async throws {
        guard let manager = WatchHistoryManager.shared else { return }

        for record in watchEntries {
            guard let parsed = WatchHistoryEntry.fromCKRecord(record) else { continue }
            try await manager.mergeRemoteWatchEntry(parsed.entry)
        }

        for record in channelEntries {
            guard let parsed = RecentChannelEntry.fromCKRecord(record) else { continue }
            try await manager.mergeRemoteChannelEntry(parsed.entry)
        }
    }

    // MARK: - Private: Push (local → CloudKit)

    private func push() async {
        guard !isPushing else { return }
        isPushing = true
        defer { isPushing = false }

        do {
            try await CloudKitContainer.ensureAvailable()
        } catch {
            MKSLog.app.info("[WatchHistorySync] iCloud unavailable, skipping push: \(error.localizedDescription)")
            return
        }

        do {
            try await CloudKitContainer.ensureZoneExists()
            guard let manager = WatchHistoryManager.shared else { return }

            let (watchRecords, channelRecords) = try await manager.allRecordsForSync(zoneID: CloudKitContainer.zoneID)

            let allRecords = watchRecords + channelRecords
            guard !allRecords.isEmpty else {
                MKSLog.app.debug("[WatchHistorySync] Push skipped — nothing to sync")
                return
            }

            MKSLog.app.info("[WatchHistorySync] Pushing \(watchRecords.count) watch + \(channelRecords.count) channel records")
            try await uploadRecords(allRecords)
            MKSLog.app.info("[WatchHistorySync] Push complete")
        } catch {
            MKSLog.app.error("[WatchHistorySync] Push failed: \(error.localizedDescription)")
        }
    }

    private func uploadRecords(_ records: [CKRecord]) async throws {
        // CloudKit batch limit is 400 records per operation.
        let batchSize = 400
        for batch in stride(from: 0, to: records.count, by: batchSize) {
            let slice = Array(records[batch..<min(batch + batchSize, records.count)])
            try await uploadBatch(slice)
        }
    }

    private func uploadBatch(_ records: [CKRecord]) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        // .changedKeys: only send fields that changed since the record was fetched.
        // For new records (no server version) this is equivalent to .allKeys.
        operation.savePolicy = .changedKeys
        operation.isAtomic = false // Allow partial success per batch

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            CloudKitContainer.privateDatabase.add(operation)
        }
    }
}

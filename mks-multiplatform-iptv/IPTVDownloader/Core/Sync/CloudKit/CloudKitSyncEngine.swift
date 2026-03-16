//
//  CloudKitSyncEngine.swift
//  mks-multiplatform-iptv
//
//  Actor-based CloudKit sync engine with runtime safety.
//

import Foundation
import CloudKit

/// Thread-safe CloudKit synchronization engine.
///
/// All CloudKit operations are gated behind `CloudKitContainer.ensureAvailable()`,
/// which checks iCloud account status at runtime. This means the code compiles
/// regardless of iCloud entitlements — when entitlements are missing,
/// `accountStatus()` returns `.noAccount` and operations gracefully throw
/// `SyncError.accountNotAvailable`.
actor CloudKitSyncEngine {
    /// Persisted sync configuration (change tokens, last sync date).
    private var configuration: SyncConfiguration

    /// Whether the zone has been verified to exist this session.
    private var zoneVerified = false

    init() {
        self.configuration = SyncConfiguration.load()
    }

    // MARK: - Zone Setup

    /// Ensures the custom record zone exists, only once per session.
    private func ensureZone() async throws {
        guard !zoneVerified else { return }
        try await CloudKitContainer.ensureZoneExists()
        zoneVerified = true
    }

    // MARK: - Push

    /// Saves a single record to CloudKit.
    /// - Parameter record: The `CKRecord` to save.
    /// - Throws: `SyncError` on failure.
    func saveRecord(_ record: CKRecord) async throws {
        try await ensureZone()

        do {
            _ = try await CloudKitContainer.privateDatabase.save(record)
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    /// Saves multiple records in a batch operation.
    /// - Parameter records: The records to save.
    /// - Returns: The saved records from the server.
    /// - Throws: `SyncError` on failure.
    func saveRecords(_ records: [CKRecord]) async throws -> [CKRecord] {
        try await ensureZone()

        let operation = CKModifyRecordsOperation(
            recordsToSave: records,
            recordIDsToDelete: nil
        )
        operation.savePolicy = .changedKeys

        return try await withCheckedThrowingContinuation { continuation in
            var savedRecords: [CKRecord] = []

            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result {
                    savedRecords.append(record)
                }
            }

            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: savedRecords)
                case .failure(let error):
                    if let ckError = error as? CKError {
                        continuation.resume(throwing: self.mapCKError(ckError))
                    } else {
                        continuation.resume(throwing: SyncError.networkError(error.localizedDescription))
                    }
                }
            }

            CloudKitContainer.privateDatabase.add(operation)
        }
    }

    /// Deletes a record from CloudKit by its ID.
    /// - Parameter recordID: The record ID to delete.
    /// - Throws: `SyncError` on failure.
    func deleteRecord(_ recordID: CKRecord.ID) async throws {
        try await ensureZone()

        let operation = CKModifyRecordsOperation(
            recordsToSave: nil,
            recordIDsToDelete: [recordID]
        )

        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    if let ckError = error as? CKError {
                        continuation.resume(throwing: self.mapCKError(ckError))
                    } else {
                        continuation.resume(throwing: SyncError.networkError(error.localizedDescription))
                    }
                }
            }
            CloudKitContainer.privateDatabase.add(operation)
        }
    }

    // MARK: - Pull

    /// Fetches all records of a given type from the custom zone.
    /// - Parameter recordType: The CloudKit record type to query.
    /// - Returns: An array of matching `CKRecord` objects.
    /// - Throws: `SyncError` on failure.
    func fetchRecords(ofType recordType: String) async throws -> [CKRecord] {
        try await ensureZone()

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        do {
            let (results, _) = try await CloudKitContainer.privateDatabase.records(
                matching: query,
                inZoneWith: CloudKitContainer.zoneID
            )

            return results.compactMap { _, result in
                try? result.get()
            }
        } catch let error as CKError {
            throw mapCKError(error)
        }
    }

    // MARK: - Sync Metadata

    /// Records a successful sync and persists the timestamp.
    func recordSuccessfulSync() {
        configuration.recordSync()
    }

    /// The date of the last successful sync.
    var lastSyncDate: Date? {
        configuration.lastSyncDate
    }

    // MARK: - Error Mapping

    /// Maps CloudKit errors to domain-specific `SyncError` cases.
    private nonisolated func mapCKError(_ error: CKError) -> SyncError {
        switch error.code {
        case .notAuthenticated:
            return .accountNotAvailable
        case .quotaExceeded:
            return .quotaExceeded
        case .permissionFailure:
            return .permissionDenied
        case .networkUnavailable, .networkFailure:
            return .networkError(error.localizedDescription)
        case .serverRejectedRequest:
            return .networkError("Server rejected request: \(error.localizedDescription)")
        default:
            return .unknown(error.localizedDescription)
        }
    }
}

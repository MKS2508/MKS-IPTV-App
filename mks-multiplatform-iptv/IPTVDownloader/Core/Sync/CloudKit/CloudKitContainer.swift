//
//  CloudKitContainer.swift
//  mks-multiplatform-iptv
//
//  CKContainer wrapper with availability checking.
//

import Foundation
import CloudKit
import IPTVCore

/// Provides access to the app's CloudKit container with runtime availability checks.
///
/// All operations first verify that the iCloud account is accessible.
/// When entitlements are missing or the user is not signed in,
/// operations throw `SyncError.accountNotAvailable` instead of crashing.
enum CloudKitContainer {
    /// The CloudKit container identifier for this app.
    static let containerIdentifier = "iCloud.com.mks.iptv"

    /// The custom record zone used for private database storage.
    static let zoneName = "IPTVProfilesZone"

    /// Returns the app's CKContainer.
    ///
    /// Note: `CKContainer(identifier:)` always succeeds at compile time.
    /// Runtime availability is determined by `accountStatus()`.
    static var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    /// The private database for user-specific data.
    static var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    /// The custom record zone ID for profile storage.
    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Checks whether iCloud is available and throws if not.
    ///
    /// This is the primary runtime safety gate. Call this before any CloudKit operation.
    /// - Throws: `SyncError.accountNotAvailable` if iCloud is not signed in,
    ///           `SyncError.permissionDenied` if restricted.
    static func ensureAvailable() async throws {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            // CKContainer can throw or crash when entitlements are missing.
            // Treat any failure as iCloud unavailable.
            throw SyncError.accountNotAvailable
        }

        switch status {
        case .available:
            return
        case .noAccount, .couldNotDetermine:
            throw SyncError.accountNotAvailable
        case .restricted:
            throw SyncError.permissionDenied
        case .temporarilyUnavailable:
            throw SyncError.networkError("iCloud temporarily unavailable")
        @unknown default:
            throw SyncError.accountNotAvailable
        }
    }

    /// Creates the custom record zone if it doesn't exist.
    /// - Throws: `SyncError` if zone creation fails.
    static func ensureZoneExists() async throws {
        try await ensureAvailable()

        let zone = CKRecordZone(zoneID: zoneID)
        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    // Zone already exists is not an error
                    if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: SyncError.networkError(error.localizedDescription))
                    }
                }
            }
            privateDatabase.add(operation)
        }
    }
}

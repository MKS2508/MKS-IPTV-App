//
//  SyncTypes.swift
//  mks-multiplatform-iptv
//
//  Common types for CloudKit synchronization.
//

import Foundation

/// Represents the current state of a sync operation.
///
/// Use this enum to display appropriate UI indicators and handle
/// user interactions based on sync status.
enum SyncStatus: Equatable, Sendable {
    /// No sync operation in progress.
    case idle

    /// Currently synchronizing with iCloud.
    /// Associated value contains optional progress description.
    case syncing(String?)

    /// Sync completed successfully.
    /// Associated value contains the timestamp of completion.
    case synced(Date)

    /// Sync failed with an error.
    /// Associated value contains the error description.
    case error(String)

    /// Device is offline, sync pending.
    case offline

    /// iCloud is not configured or unavailable.
    case unavailable

    /// Whether a sync operation is currently in progress.
    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    /// User-friendly description of the current status.
    var localizedDescription: String {
        switch self {
        case .idle:
            return String(localized: "Sync ready")
        case .syncing(let detail):
            if let detail = detail {
                return String(localized: "Syncing: \(detail)")
            }
            return String(localized: "Syncing...")
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return String(localized: "Synced \(formatter.localizedString(for: date, relativeTo: Date()))")
        case .error(let message):
            return String(localized: "Sync error: \(message)")
        case .offline:
            return String(localized: "Offline - sync pending")
        case .unavailable:
            return String(localized: "iCloud unavailable")
        }
    }

    // MARK: - Equatable

    static func == (lhs: SyncStatus, rhs: SyncStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.syncing(let l), .syncing(let r)):
            return l == r
        case (.synced(let l), .synced(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        case (.offline, .offline):
            return true
        case (.unavailable, .unavailable):
            return true
        default:
            return false
        }
    }
}

/// Errors that can occur during CloudKit synchronization.
enum SyncError: LocalizedError, Equatable {
    /// Failed to encode/decode data.
    case decodingFailed(String)

    /// CloudKit network error.
    case networkError(String)

    /// iCloud account not available.
    case accountNotAvailable

    /// CloudKit quota exceeded.
    case quotaExceeded

    /// Permission denied for CloudKit access.
    case permissionDenied

    /// Conflict resolution failed.
    case conflictResolutionFailed(String)

    /// Unknown error occurred.
    case unknown(String)

    /// User-friendly error description.
    var errorDescription: String? {
        switch self {
        case .decodingFailed(let detail):
            return "Failed to process data: \(detail)"
        case .networkError(let detail):
            return "Network error: \(detail)"
        case .accountNotAvailable:
            return "iCloud account not available. Please sign in to iCloud."
        case .quotaExceeded:
            return "iCloud storage quota exceeded."
        case .permissionDenied:
            return "Permission denied. Please allow iCloud access in Settings."
        case .conflictResolutionFailed(let detail):
            return "Failed to resolve sync conflict: \(detail)"
        case .unknown(let detail):
            return "Sync error: \(detail)"
        }
    }

    // MARK: - Equatable

    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        switch (lhs, rhs) {
        case (.decodingFailed(let l), .decodingFailed(let r)):
            return l == r
        case (.networkError(let l), .networkError(let r)):
            return l == r
        case (.accountNotAvailable, .accountNotAvailable):
            return true
        case (.quotaExceeded, .quotaExceeded):
            return true
        case (.permissionDenied, .permissionDenied):
            return true
        case (.conflictResolutionFailed(let l), .conflictResolutionFailed(let r)):
            return l == r
        case (.unknown(let l), .unknown(let r)):
            return l == r
        default:
            return false
        }
    }
}

/// Result of a sync operation.
struct SyncResult<T: Syncable>: Sendable {
    /// Successfully synchronized items.
    let syncedItems: [T]

    /// Items that failed to sync.
    let failedItems: [(T, SyncError)]

    /// Timestamp of the sync completion.
    let completedAt: Date

    /// Whether all items synced successfully.
    var isSuccess: Bool {
        failedItems.isEmpty
    }

    /// Total number of items processed.
    var totalItems: Int {
        syncedItems.count + failedItems.count
    }
}

//
//  SyncConflictResolver.swift
//  mks-multiplatform-iptv
//
//  Conflict resolution strategies for CloudKit sync.
//

import Foundation
import IPTVCore

/// Strategy for resolving conflicts between local and remote copies.
enum ConflictResolutionStrategy: Sendable {
    /// The most recently modified copy wins.
    case lastModifiedWins

    /// Local copy always takes precedence.
    case localWins

    /// Remote copy always takes precedence.
    case remoteWins
}

/// Resolves conflicts between local and remote syncable items.
///
/// Uses a configurable strategy to determine which version to keep
/// when both local and remote copies have been modified.
struct SyncConflictResolver<T: Syncable> {
    /// The strategy used to resolve conflicts.
    let strategy: ConflictResolutionStrategy

    init(strategy: ConflictResolutionStrategy = .lastModifiedWins) {
        self.strategy = strategy
    }

    /// Resolves a conflict between a local and remote item.
    /// - Parameters:
    ///   - local: The local version of the item.
    ///   - remote: The remote version of the item.
    /// - Returns: The winning version of the item.
    func resolve(local: T, remote: T) -> T {
        switch strategy {
        case .lastModifiedWins:
            return local.lastModifiedDate >= remote.lastModifiedDate ? local : remote
        case .localWins:
            return local
        case .remoteWins:
            return remote
        }
    }
}

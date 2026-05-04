import Foundation
import SwiftData
import CloudKit
import IPTVCore

/// Thread-safe service for reading and writing watch history data.
///
/// Uses `@ModelActor` for SwiftData concurrency safety, consistent with
/// the actor-based patterns used by `MovieService` and `CloudKitSyncEngine`.
@ModelActor
actor WatchHistoryManager {

    /// Shared singleton — initialized in `mks_iptv_downloaderApp.init()`.
    static var shared: WatchHistoryManager!

    // MARK: - VOD Position Tracking

    /// Upsert playback position for a VOD content item.
    ///
    /// Called every ~12s during playback, on pause, dismiss, and background.
    /// Creates a new entry if none exists, otherwise updates the existing one.
    func savePosition(
        profileId: UUID,
        contentType: String,
        contentId: String,
        position: Double,
        duration: Double,
        displayTitle: String,
        posterURL: String?,
        backdropURL: String?,
        seriesId: Int? = nil,
        showTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        containerExtension: String? = nil
    ) throws {
        let computedProgress = duration > 0 ? min(1.0, position / duration) : 0
        let isNowCompleted = computedProgress > 0.95

        if let existing = try fetchEntry(profileId: profileId, contentType: contentType, contentId: contentId) {
            existing.lastPosition = position
            // Keep the larger duration — transmux content may report 0 initially,
            // then correct duration later. Never downgrade a known duration.
            if duration > existing.totalDuration {
                existing.totalDuration = duration
            }
            let bestDuration = existing.totalDuration
            let correctedProgress = bestDuration > 0 ? min(1.0, position / bestDuration) : computedProgress
            existing.progress = correctedProgress
            existing.isCompleted = correctedProgress > 0.95
            existing.displayTitle = displayTitle
            existing.posterURL = posterURL
            existing.backdropURL = backdropURL
            existing.seriesId = seriesId
            existing.showTitle = showTitle
            existing.seasonNumber = seasonNumber
            existing.episodeNumber = episodeNumber
            existing.episodeTitle = episodeTitle
            existing.containerExtension = containerExtension
            existing.lastWatchedAt = Date()
            existing.lastModifiedDate = Date()
        } else {
            let entry = WatchHistoryEntry(
                profileId: profileId,
                contentType: contentType,
                contentId: contentId,
                lastPosition: position,
                totalDuration: duration,
                progress: computedProgress,
                isCompleted: isNowCompleted,
                displayTitle: displayTitle,
                posterURL: posterURL,
                backdropURL: backdropURL,
                seriesId: seriesId,
                showTitle: showTitle,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                episodeTitle: episodeTitle,
                containerExtension: containerExtension
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
        Task { await WatchHistorySyncEngine.shared.schedulePush() }
    }

    // MARK: - Continue Watching Queries

    /// Items with at least 30s of playback that aren't completed, sorted by `lastWatchedAt DESC`.
    ///
    /// Returns content that has been started but not finished — the data source
    /// for the "Continue Watching" carousel on the Home screen.
    func continueWatchingItems(profileId: UUID, limit: Int = 20) throws -> [WatchHistoryEntry] {
        let minPosition: Double = 30
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate<WatchHistoryEntry> { entry in
                entry.profileId == profileId &&
                entry.lastPosition > minPosition &&
                entry.isCompleted == false
            },
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = limit
        return try modelContext.fetch(limited)
    }

    /// Single entry lookup for resume dialog.
    func entry(profileId: UUID, contentType: String, contentId: String) throws -> WatchHistoryEntry? {
        try fetchEntry(profileId: profileId, contentType: contentType, contentId: contentId)
    }

    /// Most recent episode watched for a specific series.
    func lastWatchedEpisode(profileId: UUID, seriesId: Int) throws -> WatchHistoryEntry? {
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate<WatchHistoryEntry> { entry in
                entry.profileId == profileId &&
                entry.contentType == "episode" &&
                entry.seriesId == seriesId
            },
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 1
        return try modelContext.fetch(limited).first
    }

    // MARK: - Data Integrity

    /// Removes duplicate entries created by CloudKit sync across devices.
    ///
    /// Two devices can independently create `WatchHistoryEntry` records for the
    /// same content, resulting in duplicates after automatic sync merges both stores.
    /// Groups entries by `(profileId, contentType, contentId)` and keeps only the one
    /// with the latest `lastWatchedAt`. Called on app startup.
    func deduplicateEntries() throws {
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        let allEntries = try modelContext.fetch(descriptor)

        var seen = Set<String>()
        var deletedCount = 0

        for entry in allEntries {
            let key = "\(entry.profileId)_\(entry.contentType)_\(entry.contentId)"
            if seen.contains(key) {
                modelContext.delete(entry)
                deletedCount += 1
            } else {
                seen.insert(key)
            }
        }

        if deletedCount > 0 {
            try modelContext.save()
            MKSLog.app.info("[WatchHistory] Deduplicated \(deletedCount) entries after CloudKit sync")
        }
    }

    /// Fix entries corrupted by the duration=0 bug (progress=1.0 with low position).
    /// Entries where `isCompleted = true` but `lastPosition / totalDuration < 0.5` are
    /// reset to in-progress. Called once on app startup.
    func repairCorruptedEntries() throws {
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate<WatchHistoryEntry> { entry in
                entry.isCompleted == true
            }
        )
        let entries = try modelContext.fetch(descriptor)
        var repaired = 0
        for entry in entries {
            // If marked completed but position is clearly not near the end, fix it
            if entry.totalDuration > 0 {
                let actualProgress = entry.lastPosition / entry.totalDuration
                if actualProgress < 0.5 {
                    entry.isCompleted = false
                    entry.progress = actualProgress
                    repaired += 1
                }
            } else if entry.lastPosition < 300 {
                // Duration unknown and position < 5 minutes — likely bogus
                entry.isCompleted = false
                entry.progress = 0
                repaired += 1
            }
        }
        if repaired > 0 {
            try modelContext.save()
            MKSLog.app.info("[WatchHistory] Repaired \(repaired) corrupted entries")
        }
    }

    // MARK: - State Changes

    /// Mark a content item as completed (>95% or played to end).
    func markCompleted(profileId: UUID, contentType: String, contentId: String) throws {
        guard let entry = try fetchEntry(profileId: profileId, contentType: contentType, contentId: contentId) else { return }
        entry.isCompleted = true
        entry.progress = 1.0
        entry.lastModifiedDate = Date()
        try modelContext.save()
        Task { await WatchHistorySyncEngine.shared.schedulePush() }
    }

    /// Remove a single entry from continue watching (user action).
    func deleteEntry(profileId: UUID, contentType: String, contentId: String) throws {
        guard let entry = try fetchEntry(profileId: profileId, contentType: contentType, contentId: contentId) else { return }
        modelContext.delete(entry)
        try modelContext.save()
        Task { await WatchHistorySyncEngine.shared.schedulePush() }
    }

    /// Delete all watch history for a profile (called when profile is deleted).
    func deleteAllEntries(profileId: UUID) throws {
        let vodDescriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate<WatchHistoryEntry> { $0.profileId == profileId }
        )
        let vodEntries = try modelContext.fetch(vodDescriptor)
        for entry in vodEntries {
            modelContext.delete(entry)
        }

        let channelDescriptor = FetchDescriptor<RecentChannelEntry>(
            predicate: #Predicate<RecentChannelEntry> { $0.profileId == profileId }
        )
        let channelEntries = try modelContext.fetch(channelDescriptor)
        for entry in channelEntries {
            modelContext.delete(entry)
        }

        try modelContext.save()
        // No push needed for profile delete — deletions aren't synced to CloudKit.
        // The record will be cleaned up next time the other device logs in.
    }

    // MARK: - Live Channel History

    /// Record or update a live channel watch event.
    func recordChannelWatch(
        profileId: UUID,
        channelStreamId: Int,
        channelName: String,
        channelIcon: String?,
        categoryId: String?
    ) throws {
        let descriptor = FetchDescriptor<RecentChannelEntry>(
            predicate: #Predicate<RecentChannelEntry> { entry in
                entry.profileId == profileId &&
                entry.channelStreamId == channelStreamId
            }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.watchCount += 1
            existing.lastWatchedAt = Date()
            existing.channelName = channelName
            existing.channelIcon = channelIcon
        } else {
            let entry = RecentChannelEntry(
                profileId: profileId,
                channelStreamId: channelStreamId,
                channelName: channelName,
                channelIcon: channelIcon,
                categoryId: categoryId
            )
            modelContext.insert(entry)
        }

        try modelContext.save()
        Task { await WatchHistorySyncEngine.shared.schedulePush() }
    }

    /// Recent channels sorted by `lastWatchedAt DESC`.
    func recentChannels(profileId: UUID, limit: Int = 20) throws -> [RecentChannelEntry] {
        let descriptor = FetchDescriptor<RecentChannelEntry>(
            predicate: #Predicate<RecentChannelEntry> { entry in
                entry.profileId == profileId
            },
            sortBy: [SortDescriptor(\.lastWatchedAt, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = limit
        return try modelContext.fetch(limited)
    }

    // MARK: - CloudKit Sync Support

    /// Merges a remote `WatchHistoryEntry` into the local store.
    ///
    /// - If a local entry exists: merge using last-write-wins on `lastModifiedDate`.
    /// - If no local entry: insert the remote entry as-is.
    /// Merges a remote `WatchHistoryEntry` received from CloudKit pull.
    ///
    /// Does NOT call `schedulePush()` — this is an inbound sync write, not a
    /// user-initiated change. Calling schedulePush here would cause an infinite
    /// loop: pull → merge → save → schedulePush → push → CloudKit notifies → pull…
    func mergeRemoteWatchEntry(_ remote: WatchHistoryEntry) throws {
        if let local = try fetchEntry(
            profileId: remote.profileId,
            contentType: remote.contentType,
            contentId: remote.contentId
        ) {
            // last-write-wins: only overwrite if remote is newer
            guard remote.lastModifiedDate > local.lastModifiedDate else { return }
            local.lastPosition = remote.lastPosition
            local.totalDuration = max(local.totalDuration, remote.totalDuration)
            local.progress = remote.progress
            local.isCompleted = remote.isCompleted
            local.displayTitle = remote.displayTitle
            local.posterURL = remote.posterURL
            local.backdropURL = remote.backdropURL
            local.seriesId = remote.seriesId
            local.showTitle = remote.showTitle
            local.seasonNumber = remote.seasonNumber
            local.episodeNumber = remote.episodeNumber
            local.episodeTitle = remote.episodeTitle
            local.containerExtension = remote.containerExtension
            local.lastWatchedAt = remote.lastWatchedAt
            local.lastModifiedDate = remote.lastModifiedDate
        } else {
            modelContext.insert(remote)
        }
        // Save silently — no schedulePush(), this is inbound sync data.
        try modelContext.save()
    }

    /// Merges a remote `RecentChannelEntry` received from CloudKit pull.
    ///
    /// Does NOT call `schedulePush()` for the same reason as `mergeRemoteWatchEntry`.
    func mergeRemoteChannelEntry(_ remote: RecentChannelEntry) throws {
        let remoteProfileId = remote.profileId
        let remoteChannelId = remote.channelStreamId
        let descriptor = FetchDescriptor<RecentChannelEntry>(
            predicate: #Predicate<RecentChannelEntry> { entry in
                entry.profileId == remoteProfileId &&
                entry.channelStreamId == remoteChannelId
            }
        )
        if let local = try modelContext.fetch(descriptor).first {
            // Keep the higher watchCount and most recent timestamp
            if remote.lastWatchedAt > local.lastWatchedAt {
                local.watchCount = max(local.watchCount, remote.watchCount)
                local.lastWatchedAt = remote.lastWatchedAt
                local.channelName = remote.channelName
                local.channelIcon = remote.channelIcon
            }
        } else {
            modelContext.insert(remote)
        }
        // Save silently — no schedulePush(), this is inbound sync data.
        try modelContext.save()
    }

    /// Returns all local entries as CKRecords for upload to CloudKit.
    func allRecordsForSync(zoneID: CKRecordZone.ID) throws -> (watch: [CKRecord], channels: [CKRecord]) {
        let watchEntries = try modelContext.fetch(FetchDescriptor<WatchHistoryEntry>())
        let channelEntries = try modelContext.fetch(FetchDescriptor<RecentChannelEntry>())
        return (
            watchEntries.map { $0.toCKRecord(in: zoneID) },
            channelEntries.map { $0.toCKRecord(in: zoneID) }
        )
    }

    // MARK: - Private Helpers

    private func fetchEntry(profileId: UUID, contentType: String, contentId: String) throws -> WatchHistoryEntry? {
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate<WatchHistoryEntry> { entry in
                entry.profileId == profileId &&
                entry.contentType == contentType &&
                entry.contentId == contentId
            }
        )
        return try modelContext.fetch(descriptor).first
    }
}

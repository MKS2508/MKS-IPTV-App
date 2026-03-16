import Foundation
import SwiftData

/// Tracks playback position for VOD content (movies and episodes).
///
/// Each entry is scoped to a profile and content item. Display metadata is
/// denormalized so the Continue Watching carousel renders instantly without
/// IPTV API calls. The `progress` field is stored explicitly for efficient
/// SwiftData predicates.
@Model
final class WatchHistoryEntry {

    // MARK: - Identity

    /// Scopes all data per IPTV profile
    var profileId: UUID = UUID()

    /// `"movie"` or `"episode"`
    var contentType: String = ""

    /// `String(movie.streamId)` for movies, `episode.id` for episodes
    var contentId: String = ""

    // MARK: - Playback Position

    /// Playback position in seconds
    var lastPosition: Double = 0

    /// Total duration in seconds
    var totalDuration: Double = 0

    /// 0.0–1.0 (stored for efficient queries)
    var progress: Double = 0

    /// `true` when progress > 95%
    var isCompleted: Bool = false

    // MARK: - Display Metadata (denormalized)

    /// Title shown in Continue Watching carousel
    var displayTitle: String = ""

    /// Cover image URL
    var posterURL: String?

    /// Backdrop image URL
    var backdropURL: String?

    // MARK: - Series Fields

    /// For next-episode lookup
    var seriesId: Int?

    /// Series name
    var showTitle: String?

    /// For episode ordering
    var seasonNumber: Int?

    /// For episode ordering
    var episodeNumber: Int?

    /// Episode name
    var episodeTitle: String?

    // MARK: - Playback Rebuild

    /// Container extension for rebuilding playback URL (e.g. "mkv", "mp4")
    var containerExtension: String?

    // MARK: - Timestamps

    /// First play timestamp
    var createdAt: Date = Date.distantPast

    /// Most recent play timestamp
    var lastWatchedAt: Date = Date.distantPast

    /// For CloudKit conflict resolution
    var lastModifiedDate: Date = Date.distantPast

    // MARK: - Init

    init(
        profileId: UUID,
        contentType: String,
        contentId: String,
        lastPosition: Double = 0,
        totalDuration: Double = 0,
        progress: Double = 0,
        isCompleted: Bool = false,
        displayTitle: String,
        posterURL: String? = nil,
        backdropURL: String? = nil,
        seriesId: Int? = nil,
        showTitle: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        containerExtension: String? = nil
    ) {
        self.profileId = profileId
        self.contentType = contentType
        self.contentId = contentId
        self.lastPosition = lastPosition
        self.totalDuration = totalDuration
        self.progress = progress
        self.isCompleted = isCompleted
        self.displayTitle = displayTitle
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.seriesId = seriesId
        self.showTitle = showTitle
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.containerExtension = containerExtension

        let now = Date()
        self.createdAt = now
        self.lastWatchedAt = now
        self.lastModifiedDate = now
    }
}

// MARK: - Computed Helpers

extension WatchHistoryEntry {

    /// Formatted remaining time (e.g. "1h 23m left")
    var remainingTimeFormatted: String? {
        guard totalDuration > 0, !isCompleted else { return nil }
        let remaining = max(0, totalDuration - lastPosition)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }

    /// Formatted position for resume dialog (e.g. "1:23:45")
    var formattedPosition: String {
        let total = Int(lastPosition)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

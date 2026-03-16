import Foundation
import SwiftData

/// Tracks recently watched live channels per profile.
///
/// Stores denormalized channel metadata for instant rendering
/// in the Recent Channels carousel on the Home screen.
@Model
final class RecentChannelEntry {

    /// Scopes all data per IPTV profile
    var profileId: UUID = UUID()

    /// Channel identifier (LiveChannel.streamId)
    var channelStreamId: Int = 0

    /// Denormalized channel name
    var channelName: String = ""

    /// Denormalized channel icon URL
    var channelIcon: String?

    /// For optional category filtering
    var categoryId: String?

    /// How many times this channel has been watched
    var watchCount: Int = 0

    /// Most recent watch timestamp (for recency sorting)
    var lastWatchedAt: Date = Date.distantPast

    init(
        profileId: UUID,
        channelStreamId: Int,
        channelName: String,
        channelIcon: String? = nil,
        categoryId: String? = nil
    ) {
        self.profileId = profileId
        self.channelStreamId = channelStreamId
        self.channelName = channelName
        self.channelIcon = channelIcon
        self.categoryId = categoryId
        self.watchCount = 1
        self.lastWatchedAt = Date()
    }
}

//
//  LiveChannelDisplayModel.swift
//  mks-multiplatform-iptv
//
//  Display model combining LiveChannel with EPG data and favorites status.
//  Used for rendering channel cards with program information.
//

import Foundation

// MARK: - Live Channel Display Model

/// Combines LiveChannel data with EPG information and favorites status for UI display.
/// Provides computed properties for progress tracking and EPG availability.
struct LiveChannelDisplayModel: Identifiable {
    // MARK: - Properties

    /// Unique identifier matching the channel's stream ID
    let id: Int

    /// The underlying live channel data
    let channel: LiveChannel

    /// Currently airing programme (if EPG data available)
    let currentProgramme: EPGProgramme?

    /// Upcoming programmes (max 5)
    let upcomingProgrammes: [EPGProgramme]

    /// Whether this channel is marked as favorite
    var isFavorite: Bool

    // MARK: - Computed Properties

    /// Whether EPG data is available for this channel
    var hasEPG: Bool {
        currentProgramme != nil
    }

    /// Progress through the current programme (0.0 to 1.0)
    /// Returns 0 if no current programme
    var progress: Double {
        currentProgramme?.progress ?? 0.0
    }

    /// Formatted time range for current programme (e.g., "14:30 - 15:00")
    /// Returns empty string if no current programme
    var timeRange: String {
        guard let programme = currentProgramme else { return "" }
        return "\(programme.formattedStartTime) - \(programme.formattedStopTime)"
    }

    /// Duration of current programme in minutes
    /// Returns 0 if no current programme
    var durationMinutes: Int {
        currentProgramme?.durationMinutes ?? 0
    }

    /// Title of current programme or nil
    var programmeTitle: String? {
        currentProgramme?.title
    }

    /// Whether the programme is currently airing
    var isLive: Bool {
        currentProgramme?.isNow ?? false
    }

    // MARK: - Initialization

    /// Creates a display model from a LiveChannel with optional EPG data
    /// - Parameters:
    ///   - channel: The live channel data
    ///   - currentProgramme: Currently airing programme (optional)
    ///   - upcomingProgrammes: List of upcoming programmes (optional)
    ///   - isFavorite: Whether marked as favorite
    init(
        channel: LiveChannel,
        currentProgramme: EPGProgramme? = nil,
        upcomingProgrammes: [EPGProgramme] = [],
        isFavorite: Bool = false
    ) {
        self.id = channel.streamId
        self.channel = channel
        self.currentProgramme = currentProgramme
        self.upcomingProgrammes = upcomingProgrammes
        self.isFavorite = isFavorite
    }

    // MARK: - Factory Methods

    /// Creates a display model without EPG data (EPG unavailable)
    /// - Parameter channel: The live channel data
    /// - Parameter isFavorite: Whether marked as favorite
    /// - Returns: A display model with no EPG information
    static func withoutEPG(channel: LiveChannel, isFavorite: Bool = false) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: nil,
            upcomingProgrammes: [],
            isFavorite: isFavorite
        )
    }

    /// Creates a display model with full EPG data
    /// - Parameters:
    ///   - channel: The live channel data
    ///   - currentProgramme: Currently airing programme
    ///   - upcomingProgrammes: List of upcoming programmes
    ///   - isFavorite: Whether marked as favorite
    /// - Returns: A display model with complete EPG information
    static func withEPG(
        channel: LiveChannel,
        currentProgramme: EPGProgramme,
        upcomingProgrammes: [EPGProgramme] = [],
        isFavorite: Bool = false
    ) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: currentProgramme,
            upcomingProgrammes: upcomingProgrammes,
            isFavorite: isFavorite
        )
    }
}


//
//  LiveChannelDisplayModel.swift
//  mks-multiplatform-iptv
//
//  Display model combining LiveChannel with EPG data, favorites status,
//  and football event matching. Used for rendering channel cards.
//

import Foundation

// MARK: - Live Channel Display Model

/// Combines LiveChannel data with EPG information, favorites status, and football events for UI display.
/// Provides computed properties for progress tracking, EPG availability, and live sports data.
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

    /// Football event matched to this channel (if any)
    let footballEvent: FootballMatchedChannel?

    // MARK: - Computed Properties - EPG

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

    // MARK: - Computed Properties - Football

    /// Whether this channel has a matched football event
    var hasFootballEvent: Bool {
        footballEvent != nil
    }

    /// Whether the football match is currently live
    var hasLiveFootball: Bool {
        footballEvent?.isLive == true
    }

    /// Football match status display (e.g., "65'", "HT", "FT")
    var footballStatusDisplay: String? {
        footballEvent?.fixture.statusDisplay
    }

    /// Football score display (e.g., "2 - 1") or nil if not started
    var footballScoreDisplay: String? {
        footballEvent?.fixture.scoreDisplay
    }

    /// Compact badge for channel cards (e.g., "RMA 2 - 1 BAR")
    var footballBadgeDisplay: String? {
        footballEvent?.badgeDisplay
    }

    /// Full match display (e.g., "Real Madrid vs Barcelona")
    var footballMatchDisplay: String? {
        footballEvent?.fixture.matchDisplay
    }

    /// Short match display (e.g., "RMA vs BAR")
    var footballShortDisplay: String? {
        footballEvent?.fixture.shortDisplay
    }

    /// Match time display (e.g., "21:00")
    var footballTimeDisplay: String? {
        footballEvent?.fixture.formattedTime
    }

    /// Competition name (e.g., "Champions League")
    var footballCompetition: String? {
        footballEvent?.fixture.league.name
    }

    /// Best quality channel for this match
    var bestFootballChannel: LiveChannel? {
        footballEvent?.bestChannel?.channel
    }

    /// All mirror channels for this match
    var footballMirrorChannels: [LiveChannel] {
        footballEvent?.channels.map { $0.channel } ?? []
    }

    /// Match confidence level
    var footballMatchConfidence: MatchConfidence? {
        footballEvent?.matchConfidence
    }

    /// Whether this is the best channel for the match (highest quality)
    var isBestFootballChannel: Bool {
        guard let event = footballEvent,
              let best = event.bestChannel else { return false }
        return best.channel.streamId == channel.streamId
    }

    // MARK: - Initialization

    /// Creates a display model from a LiveChannel with optional EPG and football data
    /// - Parameters:
    ///   - channel: The live channel data
    ///   - currentProgramme: Currently airing programme (optional)
    ///   - upcomingProgrammes: List of upcoming programmes (optional)
    ///   - isFavorite: Whether marked as favorite
    ///   - footballEvent: Matched football event (optional)
    init(
        channel: LiveChannel,
        currentProgramme: EPGProgramme? = nil,
        upcomingProgrammes: [EPGProgramme] = [],
        isFavorite: Bool = false,
        footballEvent: FootballMatchedChannel? = nil
    ) {
        self.id = channel.streamId
        self.channel = channel
        self.currentProgramme = currentProgramme
        self.upcomingProgrammes = upcomingProgrammes
        self.isFavorite = isFavorite
        self.footballEvent = footballEvent
    }

    // MARK: - Factory Methods

    /// Creates a display model without EPG data (EPG unavailable)
    /// - Parameters:
    ///   - channel: The live channel data
    ///   - isFavorite: Whether marked as favorite
    ///   - footballEvent: Matched football event (optional)
    /// - Returns: A display model with no EPG information
    static func withoutEPG(
        channel: LiveChannel,
        isFavorite: Bool = false,
        footballEvent: FootballMatchedChannel? = nil
    ) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: nil,
            upcomingProgrammes: [],
            isFavorite: isFavorite,
            footballEvent: footballEvent
        )
    }

    /// Creates a display model with full EPG data
    /// - Parameters:
    ///   - channel: The live channel data
    ///   - currentProgramme: Currently airing programme
    ///   - upcomingProgrammes: List of upcoming programmes
    ///   - isFavorite: Whether marked as favorite
    ///   - footballEvent: Matched football event (optional)
    /// - Returns: A display model with complete EPG information
    static func withEPG(
        channel: LiveChannel,
        currentProgramme: EPGProgramme,
        upcomingProgrammes: [EPGProgramme] = [],
        isFavorite: Bool = false,
        footballEvent: FootballMatchedChannel? = nil
    ) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: currentProgramme,
            upcomingProgrammes: upcomingProgrammes,
            isFavorite: isFavorite,
            footballEvent: footballEvent
        )
    }

    // MARK: - Mutation Methods

    /// Returns a copy of this model with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: currentProgramme,
            upcomingProgrammes: upcomingProgrammes,
            isFavorite: isFavorite,
            footballEvent: footballEvent
        )
    }

    /// Returns a copy of this model with updated football event
    func withFootballEvent(_ footballEvent: FootballMatchedChannel?) -> LiveChannelDisplayModel {
        LiveChannelDisplayModel(
            channel: channel,
            currentProgramme: currentProgramme,
            upcomingProgrammes: upcomingProgrammes,
            isFavorite: isFavorite,
            footballEvent: footballEvent
        )
    }
}


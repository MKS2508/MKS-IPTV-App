//
//  IPTVConfiguration.swift
//  IPTVCore
//
//  Static URL builders and request defaults for the Xtream Codes API.
//

import Foundation

public enum IPTVConfiguration {
    public static let seriesEndpoint = "series"
    public static let moviesEndpoint = "movie"
    public static let liveChannelsEndpoint = "live"

    public static func buildMovieURL(profile: IPTVProfile, vodID: String, vodExtension: String) -> String {
        "\(profile.baseURL)/\(moviesEndpoint)/\(profile.username)/\(profile.password)/\(vodID).\(vodExtension)"
    }

    public static func buildSeriesURL(profile: IPTVProfile, vodID: String, vodExtension: String) -> String {
        "\(profile.baseURL)/\(seriesEndpoint)/\(profile.username)/\(profile.password)/\(vodID).\(vodExtension)"
    }

    public static func buildLiveChannelURL(profile: IPTVProfile, channelID: Int) -> String {
        "\(profile.baseURL)/\(liveChannelsEndpoint)/\(profile.username)/\(profile.password)/\(channelID).m3u8"
    }

    /// Build a raw MPEG-TS stream URL for a live channel.
    /// Used by the live segmenter pipeline (FFmpeg segments the continuous .ts stream locally).
    public static func buildLiveChannelTSURL(profile: IPTVProfile, channelID: Int) -> String {
        "\(profile.baseURL)/\(liveChannelsEndpoint)/\(profile.username)/\(profile.password)/\(channelID).ts"
    }

    public static func defaultRequestHeaders() -> [String: String] {
        [
            "Accept-Encoding": "identity",
            "Connection": "Keep-Alive",
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18"
        ]
    }
}

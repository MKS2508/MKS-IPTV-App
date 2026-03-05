import SwiftUI
import AVFoundation
import AVKit
import Combine

// MARK: - Player Protocol
/// Protocol that defines the interface for any video player implementation
protocol VideoPlayerProtocol: ObservableObject {
    /// Current playback state
    var isPlaying: Bool { get }

    /// Current playback time in seconds
    var currentTime: Double { get }

    /// Total duration in seconds
    var duration: Double { get }

    /// Volume level (0.0 to 1.0)
    var volume: Float { get set }

    /// Playback rate
    var rate: Float { get set }

    /// Is video loaded and ready
    var isReady: Bool { get }

    /// Current error if any
    var error: PlayerError? { get }

    /// Whether the player is currently buffering (waiting for data to resume playback)
    var isBuffering: Bool { get }

    /// Progress publisher for UI updates
    var progressPublisher: AnyPublisher<Double, Never> { get }

    /// Initialize player with URL
    func load(url: URL)

    /// Initialize player with URL and optional metadata for Control Center / Lock Screen / AirPlay
    func load(url: URL, metadata: MetadataResult?)

    /// Start playback
    func play()

    /// Pause playback
    func pause()

    /// Stop and cleanup
    func stop()

    /// Seek to specific time
    func seek(to time: Double)

    /// Get a SwiftUI view for the player
    func playerView() -> AnyView

    /// The underlying AVPlayer instance, if the implementation uses one.
    /// Used by MKSPlayerView to provide native system controls (Liquid Glass on iOS 26).
    var underlyingAVPlayer: AVPlayer? { get }

    /// Detailed buffering metrics for debug overlay and contextual buffering UI.
    var bufferingDetail: PlayerBufferingDetail { get }
}

// MARK: - Buffering Detail

/// Detailed buffering metrics for the player debug overlay and contextual UI.
struct PlayerBufferingDetail {
    let isBuffering: Bool
    /// Human-readable buffering reason (e.g. "Buffering...", "Evaluating...", "No content")
    let reason: String?
    /// Seconds of buffered data ahead of the current playhead
    let loadedRangeAhead: Double?
    /// Observed bitrate from AVPlayer's access log (bits/sec)
    let bitrate: Double?
    /// Total number of playback stalls from access log
    let stallCount: Int
    /// AVPlayer playback rate (0 = paused, 1 = normal)
    let playerRate: Float?

    static let idle = PlayerBufferingDetail(
        isBuffering: false, reason: nil, loadedRangeAhead: nil,
        bitrate: nil, stallCount: 0, playerRate: nil
    )
}

// MARK: - Default Protocol Implementations

extension VideoPlayerProtocol {
    var underlyingAVPlayer: AVPlayer? { nil }
    var isBuffering: Bool { false }
    var bufferingDetail: PlayerBufferingDetail { .idle }

    /// Default implementation that ignores metadata (for players that don't support it)
    func load(url: URL, metadata: MetadataResult?) {
        load(url: url)
    }
}

// MARK: - AVPlayer Metadata Helper

import MediaPlayer

/// Helper for setting Now Playing metadata that appears in Control Center, Lock Screen, and AirPlay displays.
/// Uses MPNowPlayingInfoCenter which works across all Apple platforms.
enum PlayerMetadataHelper {

    /// Set the Now Playing info for Control Center / Lock Screen / AirPlay.
    /// Call this when playback starts or when the current item changes.
    /// - Parameters:
    ///   - metadata: The enriched metadata from TMDB/iTunes/etc.
    ///   - duration: Total duration of the media in seconds
    ///   - currentTime: Current playback position in seconds
    ///   - playbackRate: Current playback rate (1.0 = normal, 0.0 = paused)
    static func setNowPlayingInfo(
        from metadata: MetadataResult,
        duration: Double,
        currentTime: Double = 0,
        playbackRate: Double = 1.0
    ) {
        // Title - format depends on content type
        let displayTitle: String
        if metadata.mediaType == .episode, let showTitle = metadata.showTitle {
            // Series episode: "Show Title - S01E05 - Episode Title"
            let season = metadata.seasonNumber ?? 1
            let episode = metadata.episodeNumber ?? 1
            let episodePart = metadata.episodeTitle ?? metadata.title
            displayTitle = "\(showTitle) - S\(String(format: "%02d", season))E\(String(format: "%02d", episode)) - \(episodePart)"
        } else if metadata.mediaType == .series, let showTitle = metadata.showTitle {
            displayTitle = showTitle
        } else {
            displayTitle = metadata.title
        }

        // Artist/Director/Creator
        let artist: String
        if metadata.mediaType == .movie {
            artist = metadata.director ?? "Unknown Director"
        } else {
            artist = metadata.showTitle ?? metadata.director ?? "Unknown"
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: displayTitle,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyMediaType: metadata.mediaType == .movie
                ? MPNowPlayingInfoMediaType.video.rawValue
                : MPNowPlayingInfoMediaType.video.rawValue
        ]

        // Add genre if available
        if let firstGenre = metadata.genre.first {
            nowPlayingInfo[MPMediaItemPropertyGenre] = firstGenre
        }

        // Add year if available
        if let year = metadata.year {
            nowPlayingInfo[MPMediaItemPropertyReleaseDate] = String(year)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        print("[PlayerMetadataHelper] Set Now Playing info: \(displayTitle)")
    }

    /// Update the current playback position in the Now Playing info.
    /// Call this periodically during playback to keep the progress bar in sync.
    static func updatePlaybackProgress(currentTime: Double, playbackRate: Double) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Load and set the artwork for Now Playing info.
    /// Call this asynchronously after setting the basic info.
    static func loadArtwork(from metadata: MetadataResult) {
        guard let posterURLString = metadata.posterURL ?? metadata.artworkURLs.first,
              let posterURL = URL(string: posterURLString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: posterURL)

                #if os(macOS)
                // On macOS, create NSImage from data
                let image = NSImage(data: data)
                #else
                // On iOS/tvOS, create UIImage from data
                let image = UIImage(data: data)
                #endif

                await MainActor.run {
                    guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }

                    #if os(macOS)
                    if let image = image {
                        // On macOS, we can set the artwork via MPMediaItemArtwork
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        info[MPMediaItemPropertyArtwork] = artwork
                    }
                    #else
                    if let image = image {
                        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                        info[MPMediaItemPropertyArtwork] = artwork
                    }
                    #endif

                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                    print("[PlayerMetadataHelper] Artwork loaded and set")
                }
            } catch {
                print("[PlayerMetadataHelper] Failed to load artwork: \(error)")
            }
        }
    }

    /// Clear the Now Playing info when playback stops.
    static func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("[PlayerMetadataHelper] Cleared Now Playing info")
    }
}

// MARK: - Player Errors
enum PlayerError: LocalizedError {
    case unsupportedFormat
    case networkError(Error)
    case decodingError
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This video format is not supported"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to decode video"
        case .unknown(let error):
            return "Playback error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Player Type
enum PlayerType: String, CaseIterable {
    case avplayer = "AVPlayer"
    case vlc = "VLCKit"
    case ffmpeg = "FFmpeg+AVPlayer"

    var displayName: String {
        switch self {
        case .avplayer:
            return "Native Player"
        case .vlc:
            return "VLC Player"
        case .ffmpeg:
            return "FFmpeg Transmuxer"
        }
    }

    var supportedFormats: [String] {
        switch self {
        case .avplayer:
            return ["mp4", "m4v", "mov", "m3u8"]
        case .vlc:
            return ["mkv", "avi", "mp4", "ts", "m3u8", "flv", "wmv", "m4v", "mov"]
        case .ffmpeg:
            return ["mkv", "avi", "ts", "flv", "wmv"] // Converts to MP4
        }
    }

    var hasPiPSupport: Bool {
        switch self {
        case .avplayer, .ffmpeg:
            return true  // .ffmpeg transmuxes to AVPlayer which supports PiP
        case .vlc:
            return false
        }
    }

    var hasAirPlaySupport: Bool {
        switch self {
        case .avplayer, .ffmpeg:
            return true  // .ffmpeg transmuxes to AVPlayer which supports AirPlay
        case .vlc:
            return false
        }
    }

    func supports(format: String) -> Bool {
        supportedFormats.contains(format.lowercased())
    }
}

// MARK: - Player Configuration
struct PlayerConfiguration {
    var preferredPlayer: PlayerType = .ffmpeg  // FFmpeg transmux pipeline for best format support + AirPlay
    var fallbackPlayer: PlayerType = .avplayer
    var autoSelectPlayer: Bool = true
    var enableHardwareDecoding: Bool = true
    var bufferDuration: Double = 2.0
    var networkCachingTime: Int = 1000 // milliseconds
    var requirePiPSupport: Bool = false
    var requireAirPlaySupport: Bool = false
}
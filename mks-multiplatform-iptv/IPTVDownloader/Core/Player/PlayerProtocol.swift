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

    /// The original source URL that was passed to `load(url:)`.
    /// Used by RemotePlay to send the content URL to Cast/DLNA devices.
    var sourceURL: URL? { get }
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
    var sourceURL: URL? { nil }

    /// Default implementation that ignores metadata (for players that don't support it)
    func load(url: URL, metadata: MetadataResult?) {
        load(url: url)
    }
}

// MARK: - AVPlayer Metadata Helper

import MediaPlayer

/// Helper for setting Now Playing metadata that appears in Control Center, Lock Screen, and AirPlay displays.
/// Uses MPNowPlayingInfoCenter + MPRemoteCommandCenter which works across all Apple platforms.
///
/// ## Why both MPRemoteCommandCenter AND MPNowPlayingInfoCenter?
/// The system only recognizes an app as an active media session when **remote commands are registered**.
/// Without at least play/pause handlers in `MPRemoteCommandCenter.shared()`, setting `nowPlayingInfo`
/// has no effect — the Now Playing widget never appears. This is especially critical on macOS where
/// `AVPlayerView` doesn't automatically register commands when `updatesNowPlayingInfoCenter = false`.
enum PlayerMetadataHelper {

    /// Whether remote commands are currently registered.
    private(set) static var isRemoteCommandsActive = false

    // MARK: - Remote Transport Controls

    /// Register remote command handlers so the system recognizes this app as an active media session.
    /// Without this, `MPNowPlayingInfoCenter.default().nowPlayingInfo` is completely ignored
    /// and the Now Playing widget never appears.
    ///
    /// Call once during the first `play()`. Idempotent — calling again after setup is a no-op.
    ///
    /// - Parameters:
    ///   - onPlay: Called when the user taps play in Control Center / Lock Screen / AirPlay remote.
    ///   - onPause: Called when the user taps pause.
    ///   - onToggle: Called when the user taps the play/pause toggle (headphones, keyboard).
    ///   - onSeek: Called when the user scrubs the progress bar. Receives target time in seconds.
    static func setupRemoteTransportControls(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        guard !isRemoteCommandsActive else { return }
        isRemoteCommandsActive = true

        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { _ in onPlay(); return .success }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { _ in onPause(); return .success }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { _ in onToggle(); return .success }

        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            onSeek(e.positionTime)
            return .success
        }

        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [15]
        cc.skipForwardCommand.addTarget { event in
            guard let e = event as? MPSkipIntervalCommandEvent,
                  let elapsed = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
            else { return .commandFailed }
            onSeek(elapsed + e.interval)
            return .success
        }

        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { event in
            guard let e = event as? MPSkipIntervalCommandEvent,
                  let elapsed = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
            else { return .commandFailed }
            onSeek(max(0, elapsed - e.interval))
            return .success
        }

        print("[PlayerMetadataHelper] Remote transport controls registered")
    }

    /// Remove all remote command handlers. Call during `stop()`.
    static func teardownRemoteTransportControls() {
        guard isRemoteCommandsActive else { return }

        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.changePlaybackPositionCommand.removeTarget(nil)
        cc.skipForwardCommand.removeTarget(nil)
        cc.skipBackwardCommand.removeTarget(nil)

        isRemoteCommandsActive = false
        print("[PlayerMetadataHelper] Remote transport controls removed")
    }

    // MARK: - Now Playing Info

    /// Set the Now Playing info for Control Center / Lock Screen / AirPlay.
    /// Call this when playback starts or when the current item changes.
    ///
    /// Also sets `playbackState = .playing` which is required for the Now Playing widget to appear.
    static func setNowPlayingInfo(
        from metadata: MetadataResult,
        duration: Double,
        currentTime: Double = 0,
        playbackRate: Double = 1.0
    ) {
        // Title - format depends on content type
        let displayTitle: String
        if metadata.mediaType == .episode, let showTitle = metadata.showTitle {
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
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if let firstGenre = metadata.genre.first {
            nowPlayingInfo[MPMediaItemPropertyGenre] = firstGenre
        }
        if let year = metadata.year {
            nowPlayingInfo[MPMediaItemPropertyReleaseDate] = String(year)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = .playing
        print("[PlayerMetadataHelper] Set Now Playing: \(displayTitle) (duration: \(String(format: "%.0f", duration))s)")
    }

    /// Update playback state to paused in the Now Playing session.
    static func setPlaybackStatePaused() {
        MPNowPlayingInfoCenter.default().playbackState = .paused
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
                let image = NSImage(data: data)
                #else
                let image = UIImage(data: data)
                #endif

                await MainActor.run {
                    guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }

                    #if os(macOS)
                    if let image = image {
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
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        print("[PlayerMetadataHelper] Cleared Now Playing info")
    }

    // MARK: - AVPlayerItem External Metadata (iOS / tvOS only)

    /// Build an array of `AVMetadataItem` for `AVPlayerItem.externalMetadata`.
    ///
    /// `AVPlayerViewController` reads `externalMetadata` to populate:
    /// - The player UI overlay (title bar)
    /// - Control Center / Lock Screen (NowPlaying)
    /// - AirPlay display on the remote device
    ///
    /// Without this, `AVPlayerViewController` publishes empty metadata and overrides
    /// any manually-set `MPNowPlayingInfoCenter` info.
    ///
    /// NOTE: `externalMetadata` is an AVKit extension on `AVPlayerItem` available only
    /// on iOS 12.2+ and tvOS. On macOS, it does not exist — macOS relies on
    /// `MPNowPlayingInfoCenter` set in `setNowPlayingInfo()` above, with
    /// `AVPlayerView.updatesNowPlayingInfoCenter = false` to prevent override.
    ///
    /// Reference: WWDC 2022 — "Explore media metadata publishing and playback interactions"
    #if os(iOS) || os(tvOS) || os(visionOS)
    static func buildExternalMetadata(from metadata: MetadataResult) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

        // Title
        let displayTitle: String
        if metadata.mediaType == .episode, let showTitle = metadata.showTitle {
            let season = metadata.seasonNumber ?? 1
            let episode = metadata.episodeNumber ?? 1
            let episodePart = metadata.episodeTitle ?? metadata.title
            displayTitle = "\(showTitle) - S\(String(format: "%02d", season))E\(String(format: "%02d", episode)) - \(episodePart)"
        } else if metadata.mediaType == .series, let showTitle = metadata.showTitle {
            displayTitle = showTitle
        } else {
            displayTitle = metadata.title
        }
        items.append(makeMetadataItem(identifier: .commonIdentifierTitle, value: displayTitle as NSString))

        // Artist / Director / Show Title
        let artist: String
        if metadata.mediaType == .movie {
            artist = metadata.director ?? "Unknown Director"
        } else {
            artist = metadata.showTitle ?? metadata.director ?? "Unknown"
        }
        items.append(makeMetadataItem(identifier: .commonIdentifierArtist, value: artist as NSString))

        // Description / Plot
        if let plot = metadata.plot, !plot.isEmpty {
            items.append(makeMetadataItem(identifier: .commonIdentifierDescription, value: plot as NSString))
        }

        // Genre
        if let firstGenre = metadata.genre.first {
            items.append(makeMetadataItem(identifier: .quickTimeMetadataGenre, value: firstGenre as NSString))
        }

        // Creation date (year)
        if let year = metadata.year {
            items.append(makeMetadataItem(identifier: .commonIdentifierCreationDate, value: String(year) as NSString))
        }

        return items
    }

    /// Asynchronously download artwork and append it to `AVPlayerItem.externalMetadata`.
    /// Must be called after `playerItem.externalMetadata` has been set with text metadata.
    static func loadExternalArtwork(for playerItem: AVPlayerItem, from metadata: MetadataResult) {
        guard let posterURLString = metadata.posterURL ?? metadata.artworkURLs.first,
              let posterURL = URL(string: posterURLString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: posterURL)
                guard UIImage(data: data) != nil else { return }

                await MainActor.run {
                    let artworkItem = makeMetadataItem(identifier: .commonIdentifierArtwork, value: data as NSData)
                    var existing = playerItem.externalMetadata
                    existing.append(artworkItem)
                    playerItem.externalMetadata = existing
                    print("[PlayerMetadataHelper] External artwork set on AVPlayerItem")
                }
            } catch {
                print("[PlayerMetadataHelper] Failed to load external artwork: \(error)")
            }
        }
    }
    /// Build minimal externalMetadata with just a title (for cases without full MetadataResult).
    static func buildTitleOnlyMetadata(title: String) -> [AVMetadataItem] {
        [makeMetadataItem(identifier: .commonIdentifierTitle, value: title as NSString)]
    }
    #endif

    /// Create a single `AVMetadataItem` with the given identifier and value.
    private static func makeMetadataItem(identifier: AVMetadataIdentifier, value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
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

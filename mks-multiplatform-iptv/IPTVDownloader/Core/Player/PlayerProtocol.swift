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

/// Helper for creating AVMetadataItem objects for AVPlayerItem.externalMetadata.
/// These appear in Control Center, Lock Screen, AirPlay displays, and Apple TV.
enum PlayerMetadataHelper {

    /// Create AVMetadataItem array from MetadataResult for AVPlayerItem.externalMetadata.
    /// - Parameter metadata: The enriched metadata from TMDB/iTunes/etc.
    /// - Returns: Array of AVMetadataItem for AVPlayerItem.externalMetadata
    static func makeExternalMetadata(from metadata: MetadataResult) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []

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

        if let item = makeMetadataItem(identifier: .commonKeyTitle, value: displayTitle) {
            items.append(item)
        }

        // Sort title (for alphabetical sorting in media libraries)
        if let item = makeMetadataItem(identifier: .id3MetadataSortTitle, value: displayTitle) {
            items.append(item)
        }

        // Artist/Director/Creator
        let creator: String?
        if metadata.mediaType == .movie {
            creator = metadata.director
        } else {
            creator = metadata.showTitle ?? metadata.director
        }
        if let creator, let item = makeMetadataItem(identifier: .commonKeyArtist, value: creator) {
            items.append(item)
        }

        // Genre
        if let firstGenre = metadata.genre.first,
           let item = makeMetadataItem(identifier: .quickTimeMetadataGenre, value: firstGenre) {
            items.append(item)
        }

        // Synopsis/Description
        if let plot = metadata.plot,
           let item = makeMetadataItem(identifier: .commonKeyDescription, value: plot) {
            items.append(item)
        }

        // Rating
        if let rating = metadata.rating {
            let ratingText = metadata.ratingSource != nil
                ? "\(metadata.ratingSource!): \(String(format: "%.1f", rating))"
                : String(format: "%.1f/10", rating)
            if let item = makeMetadataItem(identifier: .iTunesMetadataContentRating, value: ratingText) {
                items.append(item)
            }
        }

        // Year/Release Date
        if let year = metadata.year {
            if let item = makeMetadataItem(identifier: .id3MetadataYear, value: String(year)) {
                items.append(item)
            }
        }

        // Content rating (e.g., "TV-MA", "R")
        if let advisory = metadata.contentAdvisoryRating,
           let item = makeMetadataItem(identifier: .iTunesMetadataContentAdvisoryRating, value: advisory) {
            items.append(item)
        }

        return items
    }

    /// Create an AVMetadataItem with a string value.
    static func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMetadataItem? {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und" // language-agnostic
        return item
    }

    /// Create an AVMetadataItem with data value (for artwork).
    static func makeMetadataItem(identifier: AVMetadataIdentifier, data: Data) -> AVMetadataItem? {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = data as NSData
        item.extendedLanguageTag = "und"
        return item
    }

    /// Load artwork asynchronously and add to external metadata.
    /// - Parameters:
    ///   - metadata: The metadata containing posterURL
    ///   - playerItem: The AVPlayerItem to update
    static func loadArtwork(from metadata: MetadataResult, into playerItem: AVPlayerItem) {
        guard let posterURLString = metadata.posterURL ?? metadata.artworkURLs.first,
              let posterURL = URL(string: posterURLString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: posterURL)
                guard let artworkItem = makeMetadataItem(identifier: .commonKeyArtwork, data: data) else { return }

                await MainActor.run {
                    var currentMetadata = playerItem.externalMetadata
                    // Remove any existing artwork
                    currentMetadata.removeAll { $0.identifier == .commonKeyArtwork }
                    currentMetadata.append(artworkItem)
                    playerItem.externalMetadata = currentMetadata
                }
            } catch {
                // Artwork loading failed silently - not critical
                print("[PlayerMetadataHelper] Failed to load artwork: \(error)")
            }
        }
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
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
    
    /// Progress publisher for UI updates
    var progressPublisher: AnyPublisher<Double, Never> { get }
    
    /// Initialize player with URL
    func load(url: URL)
    
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
}

// MARK: - Default Protocol Implementations

extension VideoPlayerProtocol {
    var underlyingAVPlayer: AVPlayer? { nil }
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
    case ksplayer = "KSPlayer"
    case vlc = "VLCKit"
    case ffmpeg = "FFmpeg+AVPlayer"
    
    var displayName: String {
        switch self {
        case .avplayer:
            return "Native Player"
        case .ksplayer:
            return "KS Player"
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
        case .ksplayer:
            return ["mkv", "avi", "mp4", "ts", "m3u8", "flv", "wmv", "m4v", "mov", "webm"]
        case .vlc:
            return ["mkv", "avi", "mp4", "ts", "m3u8", "flv", "wmv", "m4v", "mov"]
        case .ffmpeg:
            return ["mkv", "avi", "ts", "flv", "wmv"] // Converts to MP4
        }
    }
    
    var hasPiPSupport: Bool {
        switch self {
        case .avplayer, .ksplayer, .ffmpeg:
            return true  // .ffmpeg transmuxes to AVPlayer which supports PiP
        case .vlc:
            return false
        }
    }

    var hasAirPlaySupport: Bool {
        switch self {
        case .avplayer, .ksplayer, .ffmpeg:
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
    var preferredPlayer: PlayerType = .ksplayer  // KSPlayer for best MKV + PiP/AirPlay
    var fallbackPlayer: PlayerType = .avplayer
    var autoSelectPlayer: Bool = true
    var enableHardwareDecoding: Bool = true
    var bufferDuration: Double = 2.0
    var networkCachingTime: Int = 1000 // milliseconds
    var requirePiPSupport: Bool = false
    var requireAirPlaySupport: Bool = false
}
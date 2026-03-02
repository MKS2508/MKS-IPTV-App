import Foundation

// MARK: - Public API Facade

/// TransmuxCore - A Swift package for transmuxing video containers using FFmpeg
/// without re-encoding. Optimized for progressive playback with HLS.
///
/// ## Key Components
/// - `TransmuxingService`: Actor-based transmux service with seek support
/// - `HLSSegmenter`: VOD HLS playlist generator with real-time segment tracking
/// - `TransmuxServer`: HTTP server for serving HLS playlists and segments
/// - `ActiveTransmux`: Thread-safe handle for controlling an in-progress transmux
///
/// ## Usage
/// ```swift
/// import TransmuxCore
///
/// let service = TransmuxingService()
/// let session = try await service.startTransmux(from: sourceURL)
///
/// // Start serving via HTTP
/// let serverSession = try await TransmuxServer.shared.start(
///     filePath: session.outputPath,
///     playlistPath: session.playlistPath,
///     expectedSize: session.expectedSize,
///     segmenter: session.segmenter,
///     initSegmentSize: session.initSegmentSize,
///     seekHandle: session.seekHandle
/// )
///
/// // Play with AVPlayer
/// let player = AVPlayer(url: serverSession.localURL)
/// ```
public enum TransmuxCore {
    /// Package version
    public static let version = "1.0.0"
}

import Foundation
import SwiftUI
import IPTVCore

// MARK: - Player Factory

class PlayerFactory {
    static let shared = PlayerFactory()

    private var configuration = PlayerConfiguration()

    private init() {}

    func configure(_ config: PlayerConfiguration) {
        self.configuration = config
    }

    // MARK: - Public API

    /// Create the optimal player for a given URL:
    ///   1. Native formats (MP4/M4V/MOV/M3U8) → AVPlayer (PiP + AirPlay)
    ///   2. Non-native → FFmpeg transmux pipeline (produces AVPlayer output)
    ///   3. VLCKit available → VLC fallback
    ///   4. Last resort → AVPlayer (may fail with MKV)
    func createPlayer(for url: URL) -> any VideoPlayerProtocol {
        createPlayer(for: url, metadata: nil, isLive: false)
    }

    /// Create the optimal player for a given URL with metadata for Control Center / Lock Screen / AirPlay.
    func createPlayer(for url: URL, metadata: MetadataResult?) -> any VideoPlayerProtocol {
        createPlayer(for: url, metadata: metadata, isLive: false)
    }

    /// Create the optimal player for a given URL with metadata and live stream hint.
    /// - Parameter isLive: When true, AVPlayer uses live-optimized buffer settings
    ///   regardless of URL path heuristics (e.g. locally-served HLS from TransmuxServer).
    func createPlayer(for url: URL, metadata: MetadataResult?, isLive: Bool) -> any VideoPlayerProtocol {
        let format = url.pathExtension.lowercased()

        if configuration.autoSelectPlayer {
            return createBestPlayer(for: format, url: url, metadata: metadata, isLive: isLive)
        }

        // Manual selection with fallback chain
        if configuration.preferredPlayer.supports(format: format) {
            return createPlayer(type: configuration.preferredPlayer, url: url, metadata: metadata, isLive: isLive)
        }
        if configuration.fallbackPlayer.supports(format: format) {
            MKSLog.player.info("Preferred player doesn't support \(format), using fallback")
            return createPlayer(type: configuration.fallbackPlayer, url: url, metadata: metadata, isLive: isLive)
        }
        MKSLog.player.info("No preferred player supports \(format), auto-selecting")
        return createBestPlayer(for: format, url: url, metadata: metadata, isLive: isLive)
    }

    func createPlayer(type: PlayerType, url: URL) -> any VideoPlayerProtocol {
        createPlayer(type: type, url: url, metadata: nil, isLive: false)
    }

    func createPlayer(type: PlayerType, url: URL, metadata: MetadataResult?) -> any VideoPlayerProtocol {
        createPlayer(type: type, url: url, metadata: metadata, isLive: false)
    }

    func createPlayer(type: PlayerType, url: URL, metadata: MetadataResult?, isLive: Bool) -> any VideoPlayerProtocol {
        switch type {
        case .avplayer:
            let player = AVPlayerImplementation()
            player.load(url: url, metadata: metadata, isLive: isLive)
            return player

        case .vlc:
            if VLCPlayerImplementation.isAvailable() {
                let player = VLCPlayerImplementation()
                player.load(url: url)
                // Note: VLC doesn't support externalMetadata, but the default load(url:metadata:) will call load(url:)
                return player
            }
            MKSLog.player.warning("VLCKit not available, falling back to AVPlayer")
            let player = AVPlayerImplementation()
            player.load(url: url, metadata: metadata, isLive: isLive)
            return player

        case .ffmpeg:
            let player = FFmpegPlayerImplementation(configuration: configuration)
            player.load(url: url, metadata: metadata)
            return player
        }
    }

    // MARK: - Smart Player Selection

    /// Native formats that AVPlayer can handle directly (with PiP + AirPlay)
    private static let nativeFormats: Set<String> = ["mp4", "m4v", "mov", "m3u8", "ts"]

    /// Formats that require FFmpeg transmux (MKV is the vast majority of IPTV VODs)
    private static let transmuxFormats: Set<String> = ["mkv", "avi", "flv", "wmv", "webm"]

    /// Detect the format from URL - handles IPTV URLs that may not have clear extensions
    private func detectFormat(from url: URL) -> String {
        // First try the path extension
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }

        // For IPTV URLs without extension, check the last path component
        // e.g., http://server/movie/user/pass/12345 or .../12345.mkv
        let path = url.path.lowercased()

        // Check for extension in the path (might be after query params stripped)
        for ext in Self.nativeFormats.union(Self.transmuxFormats) {
            if path.hasSuffix(".\(ext)") || path.contains(".\(ext)?") {
                return ext
            }
        }

        // Check URL structure for content type hints
        if path.contains("/movie/") || path.contains("/series/") {
            // VOD content - default to mkv (most common)
            MKSLog.player.info("No extension detected, VOD path → assuming mkv")
            return "mkv"
        }

        if path.contains("/live/") {
            // Live stream - typically ts or m3u8
            return "ts"
        }

        // Unknown - return empty, will default to FFmpeg
        return ""
    }

    private func createBestPlayer(for format: String, url: URL, metadata: MetadataResult?, isLive: Bool) -> any VideoPlayerProtocol {
        // Detect actual format from URL (handles IPTV URLs better)
        let detectedFormat = format.isEmpty ? detectFormat(from: url) : format

        // 1. Native formats → AVPlayer (best PiP + AirPlay)
        if Self.nativeFormats.contains(detectedFormat) {
            MKSLog.player.info("Native format (\(detectedFormat)) → AVPlayer (isLive=\(isLive))")
            return createPlayer(type: .avplayer, url: url, metadata: metadata, isLive: isLive)
        }

        // 2. MKV and other non-native → FFmpeg transmux pipeline (ALWAYS for MKV)
        // This is the primary path for IPTV VOD content
        if Self.transmuxFormats.contains(detectedFormat) {
            MKSLog.player.info("Transmux format (\(detectedFormat)) → FFmpeg transmux pipeline")
            return createPlayer(type: .ffmpeg, url: url, metadata: metadata, isLive: isLive)
        }

        // 3. Live stream → AVPlayer (native HLS/TS handling)
        let path = url.path.lowercased()
        if path.contains("/live/") || path.hasSuffix(".m3u8") {
            MKSLog.player.info("Live stream detected → AVPlayer (isLive=true)")
            return createPlayer(type: .avplayer, url: url, metadata: metadata, isLive: true)
        }

        // 4. Everything else → FFmpeg transmux (safest for IPTV content)
        // This covers: VOD with unknown format, proxy URLs (localhost),
        // and any other URL that doesn't match native formats.
        // VLC is still available via manual player selection.
        MKSLog.player.info("Non-native/unknown format (\(detectedFormat)) → FFmpeg transmux pipeline")
        return createPlayer(type: .ffmpeg, url: url, metadata: metadata, isLive: isLive)
    }

    // MARK: - Stream Detection

    private func detectLiveStream(url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/live/") || path.hasSuffix(".m3u8") || path.hasSuffix(".ts")
    }

    // MARK: - Available Players

    static func availablePlayers() -> [PlayerType] {
        var players: [PlayerType] = [.avplayer]

        if VLCPlayerImplementation.isAvailable() {
            players.append(.vlc)
        }

        // FFmpeg transmux pipeline is cross-platform (uses C API via TransmuxCore)
        players.append(.ffmpeg)

        return players
    }
}

// MARK: - Player Manager (Singleton)

class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var currentPlayer: (any VideoPlayerProtocol)?
    @Published var currentPlayerType: PlayerType = .avplayer

    private init() {}

    func loadVideo(url: URL, preferredPlayer: PlayerType? = nil, requireAirPlay: Bool = false) {
        loadVideo(url: url, metadata: nil, preferredPlayer: preferredPlayer, requireAirPlay: requireAirPlay)
    }

    func loadVideo(url: URL, metadata: MetadataResult?, preferredPlayer: PlayerType? = nil, requireAirPlay: Bool = false) {
        // Stop previous player synchronously to release connections immediately.
        // FFmpegPlayerImplementation.stop() handles its own cleanup (cancelTransmux,
        // cleanup session, stop TransmuxServer). Do NOT schedule a separate cleanup
        // Task here — it races with the new player's startTransmux/TransmuxServer.start
        // and can destroy the newly created server session.
        currentPlayer?.stop()
        currentPlayer = nil

        if let preferredPlayer = preferredPlayer {
            var config = PlayerConfiguration()
            config.preferredPlayer = preferredPlayer
            config.autoSelectPlayer = false
            config.requireAirPlaySupport = requireAirPlay
            PlayerFactory.shared.configure(config)
        } else {
            var config = PlayerConfiguration()
            config.autoSelectPlayer = true
            config.requireAirPlaySupport = requireAirPlay
            PlayerFactory.shared.configure(config)
        }

        let player = PlayerFactory.shared.createPlayer(for: url, metadata: metadata)
        currentPlayer = player

        // Track actual player type
        if player is VLCPlayerImplementation {
            currentPlayerType = .vlc
        } else if player is FFmpegPlayerImplementation {
            currentPlayerType = .ffmpeg
        } else {
            currentPlayerType = .avplayer
        }

        let titleInfo = metadata?.title ?? url.lastPathComponent
        MKSLog.player.info("Loaded \"\(titleInfo)\" with \(currentPlayerType.displayName)")
    }
}

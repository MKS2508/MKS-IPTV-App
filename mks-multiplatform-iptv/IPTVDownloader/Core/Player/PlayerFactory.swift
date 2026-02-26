import Foundation
import SwiftUI

// MARK: - Player Factory

class PlayerFactory {
    static let shared = PlayerFactory()

    private var configuration = PlayerConfiguration()

    private init() {}

    func configure(_ config: PlayerConfiguration) {
        self.configuration = config
    }

    // MARK: - Public API

    /// Create the optimal player for a given URL using Opción B strategy:
    ///   1. Native formats (MP4/M4V/MOV/M3U8) → AVPlayer (PiP + AirPlay)
    ///   2. KSPlayer available + non-native → KSPlayer (PiP, no AirPlay for MKV)
    ///   3. VLCKit available → VLC fallback
    ///   4. Last resort → AVPlayer (may fail with MKV)
    func createPlayer(for url: URL) -> any VideoPlayerProtocol {
        let format = url.pathExtension.lowercased()

        if configuration.autoSelectPlayer {
            return createBestPlayer(for: format, url: url)
        }

        // Manual selection with fallback chain
        if configuration.preferredPlayer.supports(format: format) {
            return createPlayer(type: configuration.preferredPlayer, url: url)
        }
        if configuration.fallbackPlayer.supports(format: format) {
            print("[PlayerFactory] Preferred player doesn't support \(format), using fallback")
            return createPlayer(type: configuration.fallbackPlayer, url: url)
        }
        print("[PlayerFactory] No preferred player supports \(format), auto-selecting")
        return createBestPlayer(for: format, url: url)
    }

    func createPlayer(type: PlayerType, url: URL) -> any VideoPlayerProtocol {
        switch type {
        case .avplayer:
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .ksplayer:
            if KSPlayerImplementation.isAvailable() {
                let player = KSPlayerImplementation()
                player.load(url: url)
                return player
            }
            print("[PlayerFactory] KSPlayer not available, falling back to AVPlayer")
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .vlc:
            if VLCPlayerImplementation.isAvailable() {
                let player = VLCPlayerImplementation()
                player.load(url: url)
                return player
            }
            print("[PlayerFactory] VLCKit not available, falling back to AVPlayer")
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .ffmpeg:
            let player = FFmpegPlayerImplementation(configuration: configuration)
            player.load(url: url)
            return player
        }
    }

    // MARK: - Smart Player Selection (Opción B)

    private func createBestPlayer(for format: String, url: URL) -> any VideoPlayerProtocol {
        let isNative = PlayerType.avplayer.supports(format: format)

        // 1. AirPlay required + non-native → FFmpeg transmux pipeline (produces AVPlayer output)
        if configuration.requireAirPlaySupport && !isNative && PlayerType.ffmpeg.supports(format: format) {
            print("[PlayerFactory] AirPlay required, non-native (\(format)) → FFmpeg transmux pipeline")
            return createPlayer(type: .ffmpeg, url: url)
        }

        // 2. Native formats → AVPlayer (best PiP + AirPlay)
        if isNative {
            print("[PlayerFactory] Native format (\(format)) → AVPlayer")
            return createPlayer(type: .avplayer, url: url)
        }

        // 3. Non-native but KSPlayer available → KSPlayer (PiP, wide codec support)
        if KSPlayerImplementation.isAvailable() {
            print("[PlayerFactory] Non-native format (\(format)) → KSPlayer")
            return createPlayer(type: .ksplayer, url: url)
        }

        // 4. VLCKit available → VLC fallback (wide format, no PiP in 3.x)
        if VLCPlayerImplementation.isAvailable() {
            print("[PlayerFactory] Non-native format (\(format)) → VLCKit fallback")
            return createPlayer(type: .vlc, url: url)
        }

        // 5. FFmpeg transmux pipeline (cross-platform)
        if PlayerType.ffmpeg.supports(format: format) {
            print("[PlayerFactory] Non-native format (\(format)) → FFmpeg transmux pipeline")
            return createPlayer(type: .ffmpeg, url: url)
        }

        // 6. Last resort: AVPlayer (will likely fail with MKV)
        print("[PlayerFactory] No suitable player for \(format), trying AVPlayer as last resort")
        return createPlayer(type: .avplayer, url: url)
    }

    // MARK: - Stream Detection

    private func detectLiveStream(url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/live/") || path.hasSuffix(".m3u8") || path.hasSuffix(".ts")
    }

    // MARK: - Available Players

    static func availablePlayers() -> [PlayerType] {
        var players: [PlayerType] = [.avplayer]

        if KSPlayerImplementation.isAvailable() {
            players.append(.ksplayer)
        }
        if VLCPlayerImplementation.isAvailable() {
            players.append(.vlc)
        }

        // FFmpeg transmux pipeline is cross-platform (uses C API, not shell)
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

        let player = PlayerFactory.shared.createPlayer(for: url)
        currentPlayer = player

        // Track actual player type
        if player is KSPlayerImplementation {
            currentPlayerType = .ksplayer
        } else if player is VLCPlayerImplementation {
            currentPlayerType = .vlc
        } else if player is FFmpegPlayerImplementation {
            currentPlayerType = .ffmpeg
        } else {
            currentPlayerType = .avplayer
        }

        print("[PlayerManager] Loaded \(url.lastPathComponent) with \(currentPlayerType.displayName)")
    }
}

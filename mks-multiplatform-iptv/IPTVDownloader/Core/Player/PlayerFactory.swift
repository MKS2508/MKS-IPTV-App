import Foundation
import SwiftUI

// MARK: - Player Factory
class PlayerFactory {
    static let shared = PlayerFactory()
    
    private var configuration = PlayerConfiguration()
    
    private init() {}
    
    /// Update player configuration
    func configure(_ config: PlayerConfiguration) {
        self.configuration = config
    }
    
    /// Create appropriate player for the given URL
    func createPlayer(for url: URL) -> any VideoPlayerProtocol {
        let fileExtension = url.pathExtension.lowercased()
        
        if configuration.autoSelectPlayer {
            // Auto-select best player based on format
            return createBestPlayer(for: fileExtension, url: url)
        } else {
            // Use preferred player if it supports the format
            if configuration.preferredPlayer.supports(format: fileExtension) {
                return createPlayer(type: configuration.preferredPlayer, url: url)
            } else if configuration.fallbackPlayer.supports(format: fileExtension) {
                print("[PlayerFactory] Preferred player doesn't support \(fileExtension), using fallback")
                return createPlayer(type: configuration.fallbackPlayer, url: url)
            } else {
                print("[PlayerFactory] No player supports \(fileExtension), trying VLC")
                return createPlayer(type: .vlc, url: url)
            }
        }
    }
    
    /// Create specific player type
    private func createPlayer(type: PlayerType, url: URL) -> any VideoPlayerProtocol {
        switch type {
        case .avplayer:
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .ksplayer:
            // KSPlayer module not installed - fallback to AVPlayer
            print("[PlayerFactory] KSPlayer not available (module not installed), using AVPlayer")
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .vlc:
            // VLCKit module not installed - fallback to AVPlayer
            print("[PlayerFactory] VLCKit not available (module not installed), using AVPlayer")
            let player = AVPlayerImplementation()
            player.load(url: url)
            return player

        case .ffmpeg:
            // FFmpeg transcoder implementation
            let player = FFmpegPlayerImplementation(configuration: configuration)
            player.load(url: url)
            return player
        }
    }
    
    /// Auto-select best player for format
    private func createBestPlayer(for format: String, url: URL) -> any VideoPlayerProtocol {
        // For native formats, use AVPlayer (better performance + PiP/AirPlay)
        if PlayerType.avplayer.supports(format: format) {
            print("[PlayerFactory] Using AVPlayer for \(format)")
            return createPlayer(type: .avplayer, url: url)
        }

        // Fallback to FFmpeg transcoding on macOS for unsupported formats
        #if os(macOS)
        if PlayerType.ffmpeg.supports(format: format) {
            print("[PlayerFactory] Using FFmpeg transcoder for \(format)")
            return createPlayer(type: .ffmpeg, url: url)
        }
        #endif

        // Last resort: try AVPlayer anyway
        print("[PlayerFactory] Format \(format) may not be fully supported, trying AVPlayer")
        return createPlayer(type: .avplayer, url: url)
    }
    
    /// Get available players for current platform
    static func availablePlayers() -> [PlayerType] {
        var players: [PlayerType] = [.avplayer]

        // KSPlayer and VLCKit modules not installed
        print("[PlayerFactory] Only AVPlayer available (KSPlayer/VLCKit not installed)")

        #if os(macOS)
        players.append(.ffmpeg)
        #endif

        return players
    }
}

// MARK: - Player Manager (Singleton for app-wide player)
class PlayerManager: ObservableObject {
    static let shared = PlayerManager()
    
    @Published var currentPlayer: (any VideoPlayerProtocol)?
    @Published var currentPlayerType: PlayerType = .avplayer
    
    private init() {}
    
    func loadVideo(url: URL, preferredPlayer: PlayerType? = nil) {
        // Stop current player
        currentPlayer?.stop()
        
        // Create new player
        if let preferredPlayer = preferredPlayer {
            var config = PlayerConfiguration()
            config.preferredPlayer = preferredPlayer
            config.autoSelectPlayer = false
            PlayerFactory.shared.configure(config)
        }
        
        currentPlayer = PlayerFactory.shared.createPlayer(for: url)
        
        // Determine actual player type
        if currentPlayer is AVPlayerImplementation {
            currentPlayerType = .avplayer
        } else if currentPlayer is FFmpegPlayerImplementation {
            currentPlayerType = .ffmpeg
        }
    }
}
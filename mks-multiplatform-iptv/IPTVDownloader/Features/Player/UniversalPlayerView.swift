import SwiftUI
import Combine

// MARK: - Universal Player View
struct UniversalPlayerView: View {
    let url: URL
    @StateObject private var playerManager = PlayerManager.shared
    @State private var selectedPlayerType: PlayerType = .avplayer
    @State private var showPlayerSelector = false
    @State private var playerError: PlayerError?
    
    var body: some View {
        VStack(spacing: 0) {
            // Player View
            if let player = playerManager.currentPlayer {
                player.playerView()
                    .background(Color.black)
                    .onAppear {
                        // Check for errors periodically or use a different approach
                        checkPlayerError()
                    }
            } else {
                ZStack {
                    Color.black
                    VStack {
                        Image(systemName: "tv")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No player loaded")
                            .foregroundColor(.gray)
                    }
                }
            }
            
            // Player Controls
            PlayerControlsView(player: playerManager.currentPlayer)
                .padding()
                .background(Color.black.opacity(0.8))
            
            // Player Selection (if multiple available)
            if PlayerFactory.availablePlayers().count > 1 {
                HStack {
                    Text("Player:")
                        .foregroundColor(.white)
                    
                    Picker("Player", selection: $selectedPlayerType) {
                        ForEach(PlayerFactory.availablePlayers(), id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedPlayerType) { newValue in
                        reloadWithPlayer(type: newValue)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.9))
            }
        }
        .alert("Playback Error", isPresented: .constant(playerError != nil)) {
            Button("Try Another Player") {
                showPlayerSelector = true
                playerError = nil
            }
            Button("OK") {
                playerError = nil
            }
        } message: {
            Text(playerError?.errorDescription ?? "Unknown error")
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            playerManager.currentPlayer?.stop()
        }
    }
    
    private func loadVideo() {
        selectedPlayerType = determineOptimalPlayer()
        playerManager.loadVideo(url: url, preferredPlayer: selectedPlayerType)
    }
    
    private func reloadWithPlayer(type: PlayerType) {
        playerManager.loadVideo(url: url, preferredPlayer: type)
    }
    
    private func determineOptimalPlayer() -> PlayerType {
        let format = url.pathExtension.lowercased()
        
        // Check available players that support this format
        let supportingPlayers = PlayerFactory.availablePlayers()
            .filter { $0.supports(format: format) }
        
        // Prefer native player for supported formats
        if supportingPlayers.contains(.avplayer) {
            return .avplayer
        }
        
        // Then VLC
        if supportingPlayers.contains(.vlc) {
            return .vlc
        }
        
        // Finally FFmpeg
        if supportingPlayers.contains(.ffmpeg) {
            return .ffmpeg
        }
        
        // Default
        return .avplayer
    }
    
    private func checkPlayerError() {
        if let error = playerManager.currentPlayer?.error {
            playerError = error
        }
    }
}

// MARK: - Player Controls View
struct PlayerControlsView: View {
    let player: (any VideoPlayerProtocol)?
    @State private var isSliding = false
    @State private var sliderValue: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress Bar
            if let player = player {
                HStack {
                    Text(formatTime(player.currentTime))
                        .font(.caption)
                        .foregroundColor(.white)
                    
                    Slider(
                        value: isSliding ? $sliderValue : .constant(player.currentTime),
                        in: 0...max(player.duration, 1)
                    ) { editing in
                        isSliding = editing
                        if !editing {
                            player.seek(to: sliderValue)
                        }
                    }
                    .accentColor(.red)
                    
                    Text(formatTime(player.duration))
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
            
            // Playback Controls
            HStack(spacing: 30) {
                // Play/Pause
                Button(action: {
                    if player?.isPlaying == true {
                        player?.pause()
                    } else {
                        player?.play()
                    }
                }) {
                    Image(systemName: player?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
                
                // Volume
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.white)
                    
                    Slider(value: Binding(
                        get: { player?.volume ?? 1.0 },
                        set: { player?.volume = $0 }
                    ), in: 0...1)
                    .frame(width: 100)
                    .accentColor(.red)
                }
                
                // Playback Speed
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(speed)x") {
                            player?.rate = Float(speed)
                        }
                    }
                } label: {
                    Text("\(String(format: "%.1fx", player?.rate ?? 1.0))")
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        if seconds.isNaN || seconds.isInfinite {
            return "00:00"
        }
        
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let seconds = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Preview
struct UniversalPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        UniversalPlayerView(url: URL(string: "https://example.com/video.mkv")!)
            .previewLayout(.sizeThatFits)
    }
}
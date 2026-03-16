import SwiftUI
import AVFoundation

struct GlassPlayerControlBar: View {
    let player: any VideoPlayerProtocol
    var configuration: PlayerControlsConfiguration = .default
    var onFullscreenRequest: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onGravityChange: ((PlayerVideoGravity) -> Void)?
    
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var bufferedTime: Double = 0
    @State private var volume: Float = 1.0
    @State private var isMuted: Bool = false
    @State private var speed: Float = 1.0
    @State private var gravity: PlayerVideoGravity = .resizeAspect
    @State private var isVisible: Bool = true
    @State private var autoHideTask: Task<Void, Never>?
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                topBar
                Spacer()
                bottomControls
            } else {
                Spacer()
                centerPlayButton
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleControls()
        }
        .onAppear {
            loadPlayerState()
            startAutoHideTimer()
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                loadPlayerState()
            }
        }
    }
    
    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 12) {
            if let onDismiss {
                dismissButton(action: onDismiss)
            }
            
            Spacer()
            
            if configuration.showAirPlayButton {
                airPlayButton
            }
            
            if configuration.showPictureInPictureButton {
                pipButton
            }
            
            GlassVideoGravityControl(gravity: $gravity, onGravityChange: onGravityChange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    @ViewBuilder
    private var centerPlayButton: some View {
        Button {
            togglePlayPause()
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
        }
        .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.7)
        .buttonStyle(.plain)
        .scaleEffect(isPlaying ? 1.0 : 1.1)
        .animation(.spring(response: 0.3), value: isPlaying)
    }
    
    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if configuration.showSeekBar {
                seekBarSection
            }
            
            controlButtonsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    @ViewBuilder
    private var seekBarSection: some View {
        GlassSeekBar(
            progress: Binding(
                get: { duration > 0 ? currentTime / duration : 0 },
                set: { newProgress in
                    let newTime = newProgress * duration
                    player.seek(to: newTime)
                }
            ),
            bufferedProgress: duration > 0 ? bufferedTime / duration : 0,
            currentTime: PlayerTimeInfo.formatTime(currentTime),
            duration: PlayerTimeInfo.formatTime(duration),
            remainingTime: PlayerTimeInfo.formatTime(duration - currentTime),
            onSeek: { progress in
                let seekTime = progress * duration
                player.seek(to: seekTime)
                triggerHaptic()
            },
            onSeekStart: {
                autoHideTask?.cancel()
            },
            onSeekEnd: {
                startAutoHideTimer()
            }
        )
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 10), fallbackOpacity: 0.5)
    }
    
    @ViewBuilder
    private var controlButtonsSection: some View {
        HStack(spacing: 16) {
            rewindButton
            
            Spacer()
            
            playPauseButton
            
            Spacer()
            
            forwardButton
        }
        .padding(.horizontal, 8)
        
        HStack(spacing: 12) {
            if configuration.showVolumeControl {
                GlassVolumeControl(
                    volume: $volume,
                    isMuted: isMuted,
                    onMuteToggle: toggleMute
                )
                .adaptiveGlass(in: Capsule(), fallbackOpacity: 0.5)
            }
            
            if configuration.showSpeedControl {
                GlassSpeedControl(
                    speed: $speed,
                    onSpeedChange: changeSpeed
                )
            }
            
            Spacer()
            
            if configuration.showFullscreenButton, let onFullscreenRequest {
                fullscreenButton(action: onFullscreenRequest)
            }
        }
    }
    
    @ViewBuilder
    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var airPlayButton: some View {
        #if os(iOS)
        AirPlayButton()
            .frame(width: 32, height: 32)
            .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        #elseif os(macOS)
        // macOS uses system AirPlay via AVPlayerView controls
        Button {
            // AirPlay on macOS is handled via system menu or AVPlayerView
        } label: {
            Image(systemName: "airplayvideo")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
        #endif
    }
    
    @ViewBuilder
    private var pipButton: some View {
        Button {
            togglePiP()
        } label: {
            Image(systemName: "pip.enter")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
        .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var rewindButton: some View {
        Button {
            seekBackward()
        } label: {
            Image(systemName: "gobackward.\(Int(configuration.seekIntervals.first ?? 15))")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .animation(.spring(response: 0.2), value: isPlaying)
    }
    
    @ViewBuilder
    private var forwardButton: some View {
        Button {
            seekForward()
        } label: {
            Image(systemName: "goforward.\(Int(configuration.seekIntervals.first ?? 15))")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var playPauseButton: some View {
        Button {
            togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 64, height: 64)
                
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPlaying ? 1.0 : 1.05)
        .animation(.spring(response: 0.25), value: isPlaying)
        .adaptiveGlass(in: Circle(), fallbackOpacity: 0.8)
    }
    
    @ViewBuilder
    private func fullscreenButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
        .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        .buttonStyle(.plain)
    }
    
    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible.toggle()
        }
        if isVisible {
            startAutoHideTimer()
        }
    }
    
    private func startAutoHideTimer() {
        guard configuration.autoHideControls else { return }
        autoHideTask?.cancel()
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(configuration.autoHideDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = false
            }
        }
    }
    
    private func loadPlayerState() {
        isPlaying = player.isPlaying
        currentTime = player.currentTime
        duration = player.duration
        bufferedTime = player.bufferedTime
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        triggerHaptic()
    }
    
    private func seekBackward() {
        let interval = configuration.seekIntervals.first ?? 15
        let newTime = max(0, currentTime - interval)
        player.seek(to: newTime)
        currentTime = newTime
        triggerHaptic()
    }
    
    private func seekForward() {
        let interval = configuration.seekIntervals.first ?? 15
        let newTime = min(duration, currentTime + interval)
        player.seek(to: newTime)
        currentTime = newTime
        triggerHaptic()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player.setMuted(isMuted)
        triggerHaptic()
    }
    
    private func changeSpeed(_ newSpeed: Float) {
        speed = newSpeed
        player.setRate(newSpeed)
        triggerHaptic()
    }
    
    private func togglePiP() {
        #if os(iOS) || os(macOS)
        if let avImpl = player as? AVPlayerImplementation {
            avImpl.togglePictureInPicture()
        } else if let ffmpegImpl = player as? FFmpegPlayerImplementation {
            ffmpegImpl.togglePictureInPicture()
        }
        #endif
        triggerHaptic()
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        if configuration.enableHapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
        #endif
    }
}

#if os(iOS)
import UIKit
import AVKit

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.activeTintColor = UIColor(AppColors.accent)
        routePickerView.tintColor = .white
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        Text("Video Content Here")
            .foregroundStyle(.white)
        
        VStack {
            Spacer()
            Text("GlassPlayerControlBar Preview - Requires VideoPlayerProtocol instance")
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

import SwiftUI

/// Orchestrates the gesture layer and control bars for the player.
///
/// Implements the Netflix/YouTube pattern: a transparent gesture-catching layer sits
/// below the control bars. Control bar buttons have Z-order priority over the gesture
/// layer, so they receive taps within their bounds. The empty area between top bar and
/// bottom controls passes taps through to the gesture layer via `.allowsHitTesting(false)`
/// on the middle spacer.
struct PlayerOverlayContainer: View {
    let player: any VideoPlayerProtocol
    var configuration: PlayerControlsConfiguration = .default
    @Binding var isVisible: Bool
    var metadata: MetadataResult?
    var onFullscreenRequest: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onGravityChange: ((PlayerVideoGravity) -> Void)?

    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Sub-layer A: Gesture catcher — always present, full-screen.
            // Sits below control bars in Z-order so buttons/sliders take priority.
            gestureLayer

            // Sub-layer B: Control bars or center play button
            if isVisible {
                controlBars
                    .transition(.opacity)
            } else {
                centerPlayButton
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .onAppear {
            startAutoHideTimer()
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                startAutoHideTimer()
            } else {
                autoHideTask?.cancel()
            }
        }
    }

    // MARK: - Gesture Layer

    /// Full-screen transparent tap target. Toggles controls visibility on tap.
    @ViewBuilder
    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                toggleControls()
            }
    }

    // MARK: - Control Bars

    /// Top bar + empty spacer (hit-testing disabled) + bottom controls.
    /// The spacer's `.allowsHitTesting(false)` lets taps fall through to the gesture layer.
    @ViewBuilder
    private var controlBars: some View {
        GlassPlayerControlBar(
            player: player,
            configuration: configuration,
            onFullscreenRequest: onFullscreenRequest,
            onDismiss: onDismiss,
            onGravityChange: onGravityChange,
            onUserInteraction: {
                resetAutoHideTimer()
            }
        )
    }

    // MARK: - Center Play Button (visible when controls hidden)

    @ViewBuilder
    private var centerPlayButton: some View {
        VStack {
            Spacer()
                .allowsHitTesting(false)

            Button {
                togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 80, height: 80)
            }
            .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.7)
            .buttonStyle(.plain)

            Spacer()
                .allowsHitTesting(false)
        }
    }

    // MARK: - Controls Visibility

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible.toggle()
        }
        if isVisible {
            startAutoHideTimer()
        } else {
            autoHideTask?.cancel()
        }
    }

    // MARK: - Auto-Hide Timer

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

    private func resetAutoHideTimer() {
        if isVisible {
            startAutoHideTimer()
        }
    }

    // MARK: - Playback

    private func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
        triggerHaptic()
        // Show controls after play/pause from center button
        withAnimation(.easeInOut(duration: 0.25)) {
            isVisible = true
        }
        startAutoHideTimer()
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

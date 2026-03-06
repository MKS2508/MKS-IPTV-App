import SwiftUI
import AVKit
import MediaPlayer

// MARK: - Presentation Mode

/// How MKSPlayerView renders the player surface.
enum MKSPlayerPresentationMode {
    /// Inline preview within another view (e.g. 250pt in download views).
    /// Uses `VideoPlayer(player:)` with basic controls. Shows a fullscreen expand button.
    case inline

    /// Fullscreen native player presentation.
    /// Uses `AVPlayerViewController` (iOS) / `AVPlayerView` (macOS) for all system controls:
    /// scrub bar, play/pause/skip, volume, AirPlay, PiP, fullscreen, subtitle picker.
    /// Falls back to `playerView()` for non-AVPlayer backends (VLC).
    case fullscreen
}

// MARK: - MKSPlayerView

/// Unified player component used across the entire app.
///
/// Two modes:
/// - **inline**: `VideoPlayer(player:)` with optional metadata overlay + fullscreen button
/// - **fullscreen**: Native `AVPlayerViewController`/`AVPlayerView` with complete system controls
///
/// On iOS 26+, `AVPlayerViewController` automatically uses Liquid Glass transport controls.
/// AirPlay, PiP, seeking, and all native controls are provided by the system.
///
/// ## Usage
/// ```swift
/// // Inline preview with fullscreen button
/// MKSPlayerView(
///     player: player,
///     metadata: enrichedMetadata,
///     onRequestFullscreen: { showFullscreen = true }
/// )
/// .frame(height: 250)
///
/// // Fullscreen (via FullscreenPlayerPresenter)
/// MKSPlayerView(
///     player: player,
///     title: "Movie Title",
///     onDismiss: { player.stop() },
///     presentationMode: .fullscreen
/// )
/// ```
struct MKSPlayerView: View {
    let player: any VideoPlayerProtocol
    var title: String = ""
    var metadata: MetadataResult? = nil
    var onDismiss: (() -> Void)? = nil
    var onRequestFullscreen: (() -> Void)? = nil
    var presentationMode: MKSPlayerPresentationMode = .inline

    @State private var showMetadata = true
    @State private var showDebugOverlay = UserDefaults.showPlayerDebugOverlay
    #if os(macOS)
    @State private var macOSOverlayVisible = true
    @State private var overlayHideTask: Task<Void, Never>?
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Video surface — mode-dependent rendering
            playerSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onTapGesture(count: 3) {
                    showDebugOverlay.toggle()
                    UserDefaults.showPlayerDebugOverlay = showDebugOverlay
                }

            // Debug overlay (top-leading corner, any mode)
            if showDebugOverlay {
                VStack {
                    HStack {
                        PlayerDebugOverlay(player: player)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
                .allowsHitTesting(false)
            }

            // Overlays only for inline mode (fullscreen has native controls)
            if presentationMode == .inline {
                // Metadata overlay (Liquid Glass on iOS 26+)
                if let metadata, showMetadata {
                    VStack {
                        Spacer()
                        metadataOverlay(metadata)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Title bar (when no metadata but title provided)
                if metadata == nil, !title.isEmpty {
                    VStack {
                        titleBar
                        Spacer()
                    }
                }

                // Fullscreen expand button (bottom-trailing)
                if onRequestFullscreen != nil {
                    fullscreenButton
                }
            }

            // macOS fullscreen: title + metadata overlay at top, auto-hides with mouse
            #if os(macOS)
            if presentationMode == .fullscreen, (!title.isEmpty || metadata != nil) {
                macOSFullscreenTitleOverlay
            }

            if let onDismiss, presentationMode == .fullscreen {
                VStack {
                    HStack {
                        dismissButton(action: onDismiss)
                            .opacity(macOSOverlayVisible ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: macOSOverlayVisible)
                        Spacer()
                    }
                    Spacer()
                }
            }
            #endif

            if let onDismiss, presentationMode == .inline {
                dismissButton(action: onDismiss)
            }
        }
        #if os(macOS)
        .onContinuousHover { phase in
            if presentationMode == .fullscreen {
                switch phase {
                case .active:
                    showMacOSOverlayBriefly()
                case .ended:
                    break
                }
            }
        }
        .onAppear {
            if presentationMode == .fullscreen {
                scheduleMacOSOverlayAutoHide()
            }
        }
        #endif
        .ignoresSafeArea(.all, edges: .bottom)
    }

    // MARK: - Player Surface

    @ViewBuilder
    private var playerSurface: some View {
        switch presentationMode {
        case .fullscreen:
            // Reactive surface that polls for underlyingAVPlayer becoming available.
            // Critical for FFmpeg transmux where AVPlayer is nil during transmux,
            // then becomes available once the HLS pipeline is ready.
            ReactiveFullscreenSurface(
                player: player,
                title: title,
                metadata: metadata,
                onDismiss: onDismiss
            )

        case .inline:
            player.playerView()
        }
    }

    // MARK: - Title Bar

    @ViewBuilder
    private var titleBar: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let onDismiss {
                Button("Close", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Metadata Overlay

    @ViewBuilder
    private func metadataOverlay(_ metadata: MetadataResult) -> some View {
        MetadataOverlayView(metadata: metadata)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius))
            .padding()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showMetadata.toggle()
                }
            }
    }

    // MARK: - Dismiss Button

    @ViewBuilder
    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .adaptiveGlass(in: Circle())
        .padding()
    }

    // MARK: - Fullscreen Button

    @ViewBuilder
    private var fullscreenButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { onRequestFullscreen?() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                }
                .adaptiveGlass(in: Circle())
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - macOS Fullscreen Title Overlay

    #if os(macOS)
    @ViewBuilder
    private var macOSFullscreenTitleOverlay: some View {
        VStack {
            VStack(alignment: .leading, spacing: 6) {
                if !title.isEmpty {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                if let metadata {
                    HStack(spacing: 12) {
                        if let year = metadata.year {
                            Text(String(year))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if !metadata.genre.isEmpty {
                            Text(metadata.genre.prefix(2).joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if let runtime = metadata.runtimeMinutes, runtime > 0 {
                            let h = runtime / 60
                            let m = runtime % 60
                            Text(h > 0 ? "\(h)h \(m)m" : "\(m)m")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        if let rating = metadata.rating, rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(String(format: "%.1f", rating))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.75), .black.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()
        }
        .opacity(macOSOverlayVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: macOSOverlayVisible)
        .allowsHitTesting(false)
    }

    private func showMacOSOverlayBriefly() {
        macOSOverlayVisible = true
        scheduleMacOSOverlayAutoHide()
    }

    private func scheduleMacOSOverlayAutoHide() {
        overlayHideTask?.cancel()
        overlayHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                macOSOverlayVisible = false
            }
        }
    }
    #endif
}

// MARK: - Reactive Fullscreen Surface

/// Polls for `underlyingAVPlayer` becoming available, then transitions from the
/// player's own view to native system controls (`NativeAVPlayerView` / `NativeAVPlayerViewController`).
///
/// - **AVPlayer**: `underlyingAVPlayer` is available immediately → native controls from the start.
/// - **FFmpeg**: `underlyingAVPlayer` is nil during transmux → shows the player's own view
///   (spinner), then transitions to native controls once the HLS pipeline produces an AVPlayer.
/// - **VLC**: `underlyingAVPlayer` is always nil → permanently uses its own player view.
private struct ReactiveFullscreenSurface: View {
    let player: any VideoPlayerProtocol
    var title: String = ""
    var metadata: MetadataResult? = nil
    var onDismiss: (() -> Void)?

    @State private var avPlayer: AVPlayer?
    /// Tracks whether one-time metadata setup (externalMetadata, remote controls) has been done.
    @State private var didSetupMetadata = false
    /// Tracks whether NowPlaying duration has been set (may need retry when duration loads late).
    @State private var didSetDuration = false

    var body: some View {
        Group {
            if let avPlayer {
                #if os(iOS) || os(tvOS)
                NativeAVPlayerViewController(player: avPlayer, onDismiss: onDismiss)
                #elseif os(macOS)
                NativeAVPlayerView(player: avPlayer)
                #endif
            } else {
                // Fallback: player's own view (spinner for FFmpeg, native view for VLC)
                player.playerView()
            }
        }
        .onAppear {
            avPlayer = player.underlyingAVPlayer
            applyMetadataIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if avPlayer == nil {
                avPlayer = player.underlyingAVPlayer
            }
            applyMetadataIfNeeded()
            updateDurationIfNeeded()
        }
        .onDisappear {
            PlayerMetadataHelper.teardownRemoteTransportControls()
            PlayerMetadataHelper.clearNowPlayingInfo()
        }
    }

    /// Apply metadata to the AVPlayer once it's available. Sets externalMetadata
    /// (iOS/tvOS for AVPlayerViewController display) and MPNowPlayingInfoCenter
    /// (all platforms for Control Center / Lock Screen / AirPlay).
    private func applyMetadataIfNeeded() {
        guard !didSetupMetadata, let avPlayer else { return }
        didSetupMetadata = true

        let playerRef = player
        let displayTitle = metadata?.title ?? title

        // Setup remote transport controls (required for NowPlaying widget to appear on macOS)
        PlayerMetadataHelper.setupRemoteTransportControls(
            onPlay: { playerRef.play() },
            onPause: { playerRef.pause() },
            onToggle: {
                if playerRef.isPlaying { playerRef.pause() } else { playerRef.play() }
            },
            onSeek: { position in playerRef.seek(to: position) }
        )

        if let metadata {
            // Full metadata available
            let dur = avPlayer.currentItem?.duration.seconds ?? 0
            PlayerMetadataHelper.setNowPlayingInfo(
                from: metadata,
                duration: dur.isFinite ? dur : 0,
                currentTime: avPlayer.currentTime().seconds
            )
            PlayerMetadataHelper.loadArtwork(from: metadata)

            #if os(iOS) || os(tvOS) || os(visionOS)
            if let item = avPlayer.currentItem {
                item.externalMetadata = PlayerMetadataHelper.buildExternalMetadata(from: metadata)
                PlayerMetadataHelper.loadExternalArtwork(for: item, from: metadata)
            }
            #endif
        } else if !displayTitle.isEmpty {
            // Title-only: set minimal NowPlaying and externalMetadata
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: displayTitle,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0
            ]
            let dur = avPlayer.currentItem?.duration.seconds ?? 0
            if dur.isFinite && dur > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = dur
                didSetDuration = true
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = .playing
            print("[ReactiveFullscreenSurface] Set NowPlaying title: \(displayTitle)")

            #if os(iOS) || os(tvOS) || os(visionOS)
            if let item = avPlayer.currentItem {
                item.externalMetadata = PlayerMetadataHelper.buildTitleOnlyMetadata(title: displayTitle)
            }
            #endif
        }
    }

    /// Once the AVPlayer reports a valid duration, update NowPlaying info so the
    /// progress bar shows the correct length.
    private func updateDurationIfNeeded() {
        guard !didSetDuration, let avPlayer else { return }
        let dur = avPlayer.currentItem?.duration.seconds ?? 0
        guard dur.isFinite && dur > 0 else { return }
        didSetDuration = true

        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = dur
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = avPlayer.currentTime().seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

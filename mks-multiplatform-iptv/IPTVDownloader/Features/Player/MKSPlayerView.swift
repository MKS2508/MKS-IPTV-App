import SwiftUI
import AVKit

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

            // macOS fullscreen: dismiss at top-leading (floating controls are at bottom)
            #if os(macOS)
            if let onDismiss, presentationMode == .fullscreen {
                VStack {
                    HStack {
                        dismissButton(action: onDismiss)
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
            ReactiveFullscreenSurface(player: player, onDismiss: onDismiss)

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
    var onDismiss: (() -> Void)?

    @State private var avPlayer: AVPlayer?

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
        }
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            if avPlayer == nil {
                avPlayer = player.underlyingAVPlayer
            }
        }
    }
}

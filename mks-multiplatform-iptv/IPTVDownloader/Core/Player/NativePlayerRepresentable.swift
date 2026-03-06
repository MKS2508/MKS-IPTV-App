import SwiftUI
import AVKit

// MARK: - iOS / tvOS: AVPlayerViewController Wrapper

#if os(iOS) || os(tvOS)

/// Wraps `AVPlayerViewController` for the full native system player experience.
/// On iOS 26+, this automatically uses Liquid Glass transport controls.
/// Provides: scrub bar, play/pause/skip, volume, AirPlay, PiP,
/// subtitle/audio track picker, interactive dismiss gesture.
struct NativeAVPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: (() -> Void)?
    var showsPlaybackControls: Bool = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator

        #if os(iOS)
        if #available(iOS 16.0, *) {
            controller.allowsVideoFrameAnalysis = true
        }
        #endif

        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onDismiss: (() -> Void)?

        init(onDismiss: (() -> Void)?) {
            self.onDismiss = onDismiss
        }
    }
}

#endif

// MARK: - macOS: AVPlayerView Wrapper

#if os(macOS)

/// Wraps `AVPlayerView` for QuickTime-like controls on macOS.
/// `controlsStyle = .floating` gives the modern QuickTime look with
/// a translucent control bar that auto-hides.
/// Provides: scrub bar, volume, fullscreen (green button), PiP, AirPlay.
struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        // Disable automatic NowPlaying updates — AVPlayerView would override
        // our manually-set MPNowPlayingInfoCenter metadata with empty data
        // (macOS AVKit doesn't support externalMetadata on AVPlayerItem).
        view.updatesNowPlayingInfoCenter = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

#endif

import SwiftUI
import AVKit

#if os(iOS) || os(tvOS)

struct NativeAVPlayerViewController: UIViewControllerRepresentable {
    let player: AVPlayer
    var onDismiss: (() -> Void)?
    var showsPlaybackControls: Bool = true
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var allowsPictureInPicture: Bool = true
    var allowsVideoFrameAnalysis: Bool = true
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.videoGravity = videoGravity
        controller.delegate = context.coordinator
        
        #if os(iOS)
        if #available(iOS 16.0, *) {
            controller.allowsVideoFrameAnalysis = allowsVideoFrameAnalysis
        }

        // ContextualActions available in iOS 16.2+ but requires UIAction types
        // Enable when ready to implement custom playback controls:
        // if #available(iOS 16.2, *) {
        //     controller.contextualActions = context.coordinator.contextualActions
        // }
        #endif
        
        return controller
    }
    
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
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
        
        // MARK: - Contextual Actions (iOS 16.2+)
        // Uncomment when ready to implement custom playback controls:
        //
        // #if os(iOS)
        // @available(iOS 16.2, *)
        // var contextualActions: [UIAction] {
        //     let infoAction = UIAction(
        //         title: "Info",
        //         image: UIImage(systemName: "info.circle")
        //     ) { _ in
        //         // Handle info action
        //     }
        //     return [infoAction]
        // }
        // #endif
        
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
        }
        
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { _ in
                self.onDismiss?()
            }
        }
    }
}

#elseif os(macOS)

struct NativeAVPlayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var controlsStyle: AVPlayerViewControlsStyle = .floating
    var showsFullScreenToggleButton: Bool = true
    var showsSharingServiceButton: Bool = true
    var showsTimecodes: Bool = true
    var allowsPictureInPicture: Bool = true
    
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = controlsStyle
        view.videoGravity = videoGravity
        view.showsFullScreenToggleButton = showsFullScreenToggleButton
        view.showsSharingServiceButton = showsSharingServiceButton
        view.showsTimecodes = showsTimecodes
        view.allowsPictureInPicturePlayback = allowsPictureInPicture
        view.updatesNowPlayingInfoCenter = false
        return view
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        
        if nsView.videoGravity != videoGravity {
            nsView.videoGravity = videoGravity
        }
    }
}

#endif



import SwiftUI

// MARK: - Fullscreen Player Modifier (iOS/tvOS only)

/// Manages presentation of a fullscreen native system player.
/// - iOS/tvOS: uses `.fullScreenCover` for immersive presentation
/// - macOS: no-op — macOS uses a separate `Window(id: "player")` scene instead
#if !os(macOS)
struct FullscreenPlayerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let player: (any VideoPlayerProtocol)?
    var title: String = ""
    var metadata: MetadataResult? = nil
    var stopOnDismiss: Bool = true

    // Auto-play next episode
    var nextEpisodeInfo: NextEpisodeInfo?
    var onPlayNextEpisode: ((SerieDetail.Episode) -> Void)?
    var onCancelAutoPlay: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                if let player {
                    fullscreenContent(player: player)
                        .environment(RemotePlayManager.shared)
                        .ignoresSafeArea()
                }
            }
    }

    @ViewBuilder
    private func fullscreenContent(player: any VideoPlayerProtocol) -> some View {
        let dismiss = {
            if stopOnDismiss {
                player.stop()
            }
            isPresented = false
        }

        MKSPlayerView(
            player: player,
            title: title,
            metadata: metadata,
            onDismiss: dismiss,
            presentationMode: .fullscreen,
            nextEpisodeInfo: nextEpisodeInfo,
            onPlayNextEpisode: onPlayNextEpisode,
            onCancelAutoPlay: onCancelAutoPlay
        )
        .background(Color.black)
        .ignoresSafeArea()
    }
}
#endif

// MARK: - View Extension

extension View {
    /// Present a fullscreen native system player.
    /// - iOS/tvOS: presents via `.fullScreenCover`
    /// - macOS: no-op (macOS uses `Window(id: "player")` via `PlayerWindowManager`)
    ///
    /// - Parameters:
    ///   - isPresented: Binding controlling presentation
    ///   - player: The video player protocol instance
    ///   - title: Optional title displayed when no metadata
    ///   - metadata: Optional enriched metadata overlay
    ///   - stopOnDismiss: If true, calls player.stop() on dismiss (default true).
    ///     Set to false for inline→fullscreen transitions where inline should continue.
    func fullscreenPlayer(
        isPresented: Binding<Bool>,
        player: (any VideoPlayerProtocol)?,
        title: String = "",
        metadata: MetadataResult? = nil,
        stopOnDismiss: Bool = true,
        nextEpisodeInfo: NextEpisodeInfo? = nil,
        onPlayNextEpisode: ((SerieDetail.Episode) -> Void)? = nil,
        onCancelAutoPlay: (() -> Void)? = nil
    ) -> some View {
        #if os(macOS)
        self
        #else
        modifier(FullscreenPlayerModifier(
            isPresented: isPresented,
            player: player,
            title: title,
            metadata: metadata,
            stopOnDismiss: stopOnDismiss,
            nextEpisodeInfo: nextEpisodeInfo,
            onPlayNextEpisode: onPlayNextEpisode,
            onCancelAutoPlay: onCancelAutoPlay
        ))
        #endif
    }
}

import SwiftUI

// MARK: - Fullscreen Player Modifier

/// Manages presentation of a fullscreen native system player.
/// - iOS/tvOS: uses `.fullScreenCover` for immersive presentation
/// - macOS: uses `.sheet` with large frame
struct FullscreenPlayerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let player: (any VideoPlayerProtocol)?
    var title: String = ""
    var metadata: MetadataResult? = nil
    var stopOnDismiss: Bool = true

    func body(content: Content) -> some View {
        content
            #if os(iOS) || os(tvOS)
            .fullScreenCover(isPresented: $isPresented) {
                if let player {
                    fullscreenContent(player: player)
                        .ignoresSafeArea()
                }
            }
            #elseif os(macOS)
            .sheet(isPresented: $isPresented) {
                if let player {
                    fullscreenContent(player: player)
                        .frame(minWidth: 960, idealWidth: 1280, minHeight: 540, idealHeight: 720)
                }
            }
            #endif
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
            presentationMode: .fullscreen
        )
        .background(Color.black)
        .ignoresSafeArea()
        #if os(macOS)
        .onExitCommand(perform: dismiss)
        #endif
    }
}

// MARK: - View Extension

extension View {
    /// Present a fullscreen native system player.
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
        stopOnDismiss: Bool = true
    ) -> some View {
        modifier(FullscreenPlayerModifier(
            isPresented: isPresented,
            player: player,
            title: title,
            metadata: metadata,
            stopOnDismiss: stopOnDismiss
        ))
    }
}

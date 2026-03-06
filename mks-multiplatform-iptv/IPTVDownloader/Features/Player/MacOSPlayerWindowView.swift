#if os(macOS)
import SwiftUI

/// Content view for the macOS `Window(id: "player")` scene.
///
/// Reads from `PlayerWindowManager.shared` to display the active player.
/// When no content is playing, shows a placeholder. The window title bar
/// displays the content title via `.navigationTitle`.
struct MacOSPlayerWindowView: View {
    private let manager = PlayerWindowManager.shared

    var body: some View {
        Group {
            if let player = manager.activePlayer {
                MKSPlayerView(
                    player: player,
                    title: manager.title,
                    metadata: manager.metadata,
                    presentationMode: .fullscreen
                )
            } else {
                Color.black
                    .overlay {
                        VStack(spacing: 16) {
                            Image(systemName: "play.tv")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No content playing")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .background(Color.black)
        .navigationTitle(manager.title.isEmpty ? "Now Playing" : manager.title)
        .onDisappear {
            manager.dismiss()
        }
    }
}
#endif

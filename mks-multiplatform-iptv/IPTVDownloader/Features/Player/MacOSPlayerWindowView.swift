#if os(macOS)
import SwiftUI
import AppKit

/// Content view for the macOS `Window(id: "player")` scene.
///
/// Reads from `PlayerWindowManager.shared` to display the active player.
/// When no content is playing, the window closes itself automatically
/// so it doesn't linger as an empty window on app launch or after playback ends.
struct MacOSPlayerWindowView: View {
    private let manager = PlayerWindowManager.shared
    @Environment(\.dismiss) private var dismiss

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
                // No content — close the window immediately
                Color.clear
                    .onAppear {
                        closePlayerWindow()
                    }
            }
        }
        .background(Color.black)
        .navigationTitle(manager.title.isEmpty ? "Now Playing" : manager.title)
        .onDisappear {
            manager.dismiss()
        }
    }

    /// Close the player window via NSApplication when there's no content.
    /// SwiftUI's `dismiss` only works for sheets/popovers, so we find
    /// the actual NSWindow by its identifier and close it directly.
    private func closePlayerWindow() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.identifier?.rawValue.contains("player") == true
                    || window.title == "Now Playing" {
                    window.close()
                    return
                }
            }
            // Fallback: try dismiss (works in some contexts)
            dismiss()
        }
    }
}
#endif

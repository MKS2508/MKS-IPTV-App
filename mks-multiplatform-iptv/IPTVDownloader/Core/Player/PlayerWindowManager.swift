#if os(macOS)
import SwiftUI
import IPTVCore

/// Singleton that holds the active player state for the macOS player window.
///
/// On macOS, playback opens in a separate `Window(id: "player")` scene rather
/// than a sheet or fullScreenCover. Calling views set the player + metadata here,
/// then call `openWindow(id: "player")`. The window reads from this manager.
@MainActor @Observable
final class PlayerWindowManager {
    static let shared = PlayerWindowManager()

    var activePlayer: (any VideoPlayerProtocol)?
    var title: String = ""
    var metadata: MetadataResult?

    private init() {}

    /// Present a player in the macOS player window.
    /// Stops any existing player before replacing it.
    func present(player: any VideoPlayerProtocol, title: String, metadata: MetadataResult? = nil) {
        activePlayer?.stop()
        self.activePlayer = player
        self.title = title
        self.metadata = metadata
    }

    /// Dismiss the current player and clear state.
    func dismiss() {
        activePlayer?.stop()
        activePlayer = nil
        title = ""
        metadata = nil
    }
}
#endif

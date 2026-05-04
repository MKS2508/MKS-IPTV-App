#if os(macOS)
import SwiftUI
import IPTVCore

/// Singleton that manages global app state including launch mode detection.
/// Detects if the app was launched with a file (Open With) vs normal IPTV mode.
@MainActor @Observable
final class AppState {
    static let shared = AppState()
    
    /// File URL passed via Open With / command line at launch
    var launchedWithFile: URL?
    
    /// True if app should show ONLY the player (no IPTV UI)
    var isStandalonePlayerMode: Bool { launchedWithFile != nil }
    
    private init() {}
    
    /// Set a file to open (called from onOpenURL or File → Open)
    func setLaunchedFile(_ url: URL) {
        self.launchedWithFile = url
        MKSLog.app.info("[AppState] Set launched file: \(url.path)")
    }
    
    /// Clear the launched file after handling
    func clearLaunchedFile() {
        launchedWithFile = nil
    }
}
#endif

import SwiftUI
#if canImport(KSPlayer)
import KSPlayer
#endif

@main
struct mks_iptv_downloaderApp: App {
    @StateObject var profilesManager = IPTVProfilesManager.shared
    @State private var showingSettings = false

    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    init() {
        Self.configurePlayerEngines()
    }

    var body: some Scene {
        WindowGroup {
            // Profile selection gating: blocks app until a profile is chosen.
            if let profile = activeProfile {
                ContentView(showingSettings: $showingSettings)
                    .environmentObject(DownloadManager(profile: profile))
                    .environmentObject(profilesManager)
                    .environmentObject(profile)
            } else {
                IPTVProfilesView(manager: profilesManager)
            }
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Switch Profile...") {
                    showingSettings = true
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

// MARK: - Player Engine Configuration

extension mks_iptv_downloaderApp {
    static func configurePlayerEngines() {
        #if canImport(KSPlayer)
        // Enable FFmpeg engine for non-native formats (MKV, TS, AVI, etc.)
        KSOptions.secondPlayerType = KSMEPlayer.self

        // PiP: auto-start when app goes to background
        KSOptions.canStartPictureInPictureAutomaticallyFromInline = true

        // IPTV reconnection options are configured per-instance in
        // KSPlayerImplementation.makeOptions(for:) to allow per-stream tuning.

        print("[KSPlayer] Engine configured: KSMEPlayer enabled for MKV/TS/AVI")
        #else
        print("[Player] KSPlayer not available, using AVPlayer only")
        #endif
    }
}

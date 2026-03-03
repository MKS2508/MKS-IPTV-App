import SwiftUI
import TransmuxCore

@main
struct mks_iptv_downloaderApp: App {
    @StateObject var profilesManager = IPTVProfilesManager.shared
    @State private var showingSettings = false

    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    init() {
        StderrFilter.install()
        TransmuxingService.configure(streamProxy: StreamProxyAdapter())
        Self.configurePlayerEngines()
    }

    var body: some Scene {
        WindowGroup {
            // Profile selection gating: blocks app until a profile is chosen.
            Group {
                if let profile = activeProfile {
                    ContentView(showingSettings: $showingSettings)
                        .environmentObject(DownloadManager(profile: profile))
                        .environmentObject(profilesManager)
                        .environmentObject(profile)
                } else {
                    IPTVProfilesView(manager: profilesManager)
                }
            }
            .preferredColorScheme(.dark)
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
        print("[Player] Using FFmpeg transmux pipeline (TransmuxCore) + AVPlayer")
    }
}

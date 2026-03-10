import SwiftUI
import TransmuxCore
#if os(iOS)
import AVFoundation
#endif

@main
struct mks_iptv_downloaderApp: App {
    @StateObject var profilesManager = IPTVProfilesManager.shared
    @State private var showingSettings = false

    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    /// True when running inside Xcode Previews / Playgrounds.
    private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"

    init() {
        // Skip heavy initialization in Xcode Previews — StderrFilter redirects
        // stderr which breaks preview IPC, and TransmuxCore/FFmpeg init is slow
        // on external drives.
        guard !Self.isPreview else { return }

        StderrFilter.install()
        TransmuxingService.configure(streamProxy: StreamProxyAdapter())
        Self.configurePlayerEngines()
        #if os(iOS)
        Self.configureAudioSession()
        #endif

        // Request notification permission (async, non-blocking)
        Task {
            _ = await DownloadNotificationService.shared.requestPermission()
        }
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
                        .environment(RemotePlayManager.shared)
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

        #if os(macOS)
        Window("Now Playing", id: "player") {
            MacOSPlayerWindowView()
                .preferredColorScheme(.dark)
                .environment(RemotePlayManager.shared)
        }
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}

// MARK: - Player Engine Configuration

extension mks_iptv_downloaderApp {
    static func configurePlayerEngines() {
        print("[Player] Using FFmpeg transmux pipeline (TransmuxCore) + AVPlayer")
    }

    #if os(iOS)
    static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            print("[Audio] AVAudioSession configured: .playback, .moviePlayback")
        } catch {
            print("[Audio] Failed to configure AVAudioSession: \(error)")
        }
    }
    #endif
}

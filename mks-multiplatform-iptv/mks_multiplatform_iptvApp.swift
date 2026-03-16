import SwiftUI
import TransmuxCore
#if os(iOS)
import AVFoundation
#elseif os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@main
struct mks_iptv_downloaderApp: App {
    @StateObject var profilesManager = IPTVProfilesManager.shared
    @State private var showingSettings = false

    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"

    init() {
        guard !Self.isPreview else { return }

        StderrFilter.install()
        TransmuxingService.configure(streamProxy: StreamProxyAdapter())
        Self.configurePlayerEngines()
        #if os(iOS)
        Self.configureAudioSession()
        #endif

        Task {
            _ = await DownloadNotificationService.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindowContent(showingSettings: $showingSettings)
                .environmentObject(profilesManager)
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenFileButton()
            }

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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }

    // MARK: - Player Engine Configuration

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

// MARK: - Main Window Content

struct MainWindowContent: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject var profilesManager: IPTVProfilesManager
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            #if os(macOS)
            if AppState.shared.isStandalonePlayerMode {
                StandaloneLauncherView(fileURL: AppState.shared.launchedWithFile!)
                    .preferredColorScheme(.dark)
            } else {
                mainIPTVContent
            }
            #else
            mainIPTVContent
            #endif
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .openPlayerWindow)) { _ in
            openWindow(id: "player")
        }
        #endif
    }

    @ViewBuilder
    private var mainIPTVContent: some View {
        if let activeProfile = profilesManager.activeProfile {
            ContentView(showingSettings: $showingSettings)
                .environmentObject(DownloadManager(profile: activeProfile))
                .environmentObject(profilesManager)
                .environmentObject(activeProfile)
                .environment(RemotePlayManager.shared)
        } else {
            IPTVProfilesView(manager: profilesManager)
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.isFileURL else {
            print("[App] Ignoring non-file URL: \(url)")
            return
        }

        #if os(macOS)
        if AppState.shared.isStandalonePlayerMode {
            AppState.shared.setLaunchedFile(url)
        } else {
            FilePlayerOpener.openPlayerWindow(with: url)
        }
        #endif
    }
}

// MARK: - macOS File Handling

#if os(macOS)
import AppKit
import Combine

/// Notification to open player window from non-View context
extension Notification.Name {
    static let openPlayerWindow = Notification.Name("openPlayerWindow")
}

/// Helper to open player window from non-View context
enum FilePlayerOpener {
    private static var playerWindowController: NSWindowController?
    
    @MainActor
    static func openPlayerWindow(with url: URL) {
        print("[FilePlayerOpener] Opening player window for: \(url.path)")
        
        let title = url.deletingPathExtension().lastPathComponent
        let player = PlayerFactory.shared.createPlayer(for: url)

        PlayerWindowManager.shared.present(
            player: player,
            title: title,
            metadata: nil
        )
        
        print("[FilePlayerOpener] Player configured in PlayerWindowManager")

        player.load(url: url)
        player.play()
        
        print("[FilePlayerOpener] Player loaded and playing")

        // Create or show the player window directly via AppKit
        createAndShowPlayerWindow()
    }
    
    @MainActor
    private static func createAndShowPlayerWindow() {
        // If window already exists, just bring it to front
        if let existingWindow = NSApplication.shared.windows.first(where: { 
            $0.identifier?.rawValue == "mks-player-window"
        }) {
            print("[FilePlayerOpener] Reusing existing player window")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        print("[FilePlayerOpener] Creating new player window")
        
        // Create window programmatically
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.identifier = NSUserInterfaceItemIdentifier("mks-player-window")
        window.title = "Now Playing"
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.titlebarAppearsTransparent = true
        
        // Create the SwiftUI view
        let playerView = MacOSPlayerWindowView()
            .preferredColorScheme(.dark)
            .environment(RemotePlayManager.shared)
        
        // Wrap in hosting view
        let hostingView = NSHostingView(rootView: playerView)
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        
        window.contentView = hostingView
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        print("[FilePlayerOpener] Player window created and shown")
        
        // Debug: List all windows
        print("[FilePlayerOpener] Current windows:")
        for w in NSApplication.shared.windows {
            print("  - \(w.title) [id: \(w.identifier?.rawValue ?? "nil")]")
        }
    }
}

/// Button that shows NSOpenPanel for file selection
struct OpenFileButton: View {
    var body: some View {
        Button("Open File...") {
            showFilePicker()
        }
        .keyboardShortcut("o", modifiers: .command)
    }

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a video file to play"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                FilePlayerOpener.openPlayerWindow(with: url)
            }
        }
    }
}
#endif

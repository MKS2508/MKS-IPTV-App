import SwiftUI
import SwiftData
import TransmuxCore
import IPTVCore
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

    /// SwiftData container for watch history persistence
    let watchHistoryContainer: ModelContainer

    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    private static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"

    init() {
        // Initialize SwiftData container (must happen before guard)
        do {
            watchHistoryContainer = try WatchHistoryConfiguration.createContainer()
            WatchHistoryManager.shared = WatchHistoryManager(modelContainer: watchHistoryContainer)
            MKSLog.app.info("[WatchHistory] SwiftData container initialized")
            // Repair entries corrupted by the duration=0 bug (progress=1.0 with low position)
            Task {
                try? await WatchHistoryManager.shared.repairCorruptedEntries()
            }
            // Pull remote watch history from CloudKit (delayed 3s to not block launch UI).
            // Uses incremental CKFetchRecordZoneChangesOperation with persisted change token
            // so only records changed since the last pull are fetched.
            Task {
                try? await Task.sleep(for: .seconds(3))
                await WatchHistorySyncEngine.shared.pull()
            }
            // Register this device in CloudKit for cross-device tracking
            Task {
                await DeviceSyncManager.shared.registerCurrentDevice()
            }
        } catch {
            fatalError("[WatchHistory] Failed to create ModelContainer: \(error)")
        }

        guard !Self.isPreview else { return }

        #if os(macOS)
        // Prevent macOS from restoring previous windows on launch.
        // This must be set before the first window is created.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif

        // Centralized log configuration — must run before any logger fires.
        let logConfig = MKSLogConfig.shared
        logConfig.ensureLogDirectoryExists()
        TransmuxLog.configure(
            directory: logConfig.logDirectory,
            level: logConfig.level(for: .transmux).toTransmuxLevel()
        )

        // Bridge TransmuxCore logs (Swift + C/FFmpeg) → MKSLog → WebSocket.
        // TransmuxLog writes to its own file (mks-iptv-transmux.log).
        // This observer additionally sends each entry through MKSLog.transmux
        // so it reaches os.Logger + WebSocket remote viewer.
        TransmuxLog.externalObserver = { message, tag, level in
            switch level {
            case .error: MKSLog.transmux.error("[\(tag)] \(message)")
            case .warn:  MKSLog.transmux.warning("[\(tag)] \(message)")
            case .info:  MKSLog.transmux.info("[\(tag)] \(message)")
            case .debug: MKSLog.transmux.debug("[\(tag)] \(message)")
            }
        }
        TransmuxLog.installCLogBridge()

        StderrFilter.install()
        TransmuxingService.configure(streamProxy: StreamProxyAdapter())
        Self.configurePlayerEngines()
        #if os(iOS)
        Self.configureAudioSession()
        #endif

        // Remote debug: iOS browses for a Mac/viewer to send logs to.
        // macOS acts as the RECEIVER (RemoteLogReceiver), not a browser —
        // otherwise it discovers itself in a loop.
        #if DEBUG && !os(macOS)
        Task { @MainActor in
            RemoteDebugService.shared.start()
        }
        #endif

        Task {
            _ = await DownloadNotificationService.shared.requestPermission()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindowContent(showingSettings: $showingSettings)
                .environmentObject(profilesManager)
                .modelContainer(watchHistoryContainer)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
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
                .modelContainer(watchHistoryContainer)
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
        MKSLog.app.info("[Player] Using FFmpeg transmux pipeline (TransmuxCore) + AVPlayer")
    }

    #if os(iOS)
    static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback: audio continues when screen locks or app backgrounds (required for PiP)
            // .moviePlayback: optimized routing for video content
            // .duckOthers: lower other audio instead of stopping it (e.g. navigation)
            try session.setCategory(.playback, mode: .moviePlayback, options: [.duckOthers])
            try session.setActive(true)
            MKSLog.app.info("[Audio] AVAudioSession configured and activated: .playback, .moviePlayback, .duckOthers")
        } catch {
            MKSLog.app.error("[Audio] Failed to configure AVAudioSession: \(error)")
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

    /// DownloadManager is kept as a stable @StateObject so it is created exactly
    /// once per window and never recreated when profilesManager.activeProfile changes.
    ///
    /// Previously it was created inline as:
    ///   `.environmentObject(DownloadManager(profile: activeProfile))`
    /// inside the @ViewBuilder `mainIPTVContent` computed property. This meant every
    /// time SwiftUI re-evaluated that property (on ANY state change — tab selection,
    /// category filter, toolbar updates) it allocated a brand-new DownloadManager,
    /// which caused:
    ///   1. "Loaded N persisted downloads" logged 6+ times (multiple CoreData loads)
    ///   2. The EnvironmentObject identity changing → SwiftUI tearing down the entire
    ///      ContentView subtree, invalidating all child @StateObject instances and
    ///      cancelling in-flight .task{} closures → CPU 100% hang on every tab change.
    ///
    /// By lifting it to @StateObject here it is allocated exactly once for the lifetime
    /// of the window. Profile changes (profile switch in Settings) don't require a new
    /// DownloadManager because DownloadManager only stores the profile to satisfy its
    /// init signature — it never reads profile after initialisation.
    @StateObject private var downloadManager: DownloadManager = {
        // Use the already-loaded active profile from the shared manager.
        // IPTVProfilesManager.shared is a singleton initialised at app startup,
        // so activeProfile is already populated by the time this closure runs.
        // If there's no active profile yet (fresh install, no profile created),
        // we create a dummy profile. DownloadManager never reads the profile after
        // init, so this is safe — it will load any persisted downloads correctly.
        let profile = IPTVProfilesManager.shared.activeProfile
            ?? IPTVProfile(name: "", baseURL: "", username: "", password: "")
        return DownloadManager(profile: profile)
    }()

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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            // Flush pending debounced push when app loses focus (user switches away).
            Task { await WatchHistorySyncEngine.shared.pushNow() }
        }
        #endif
    }

    @ViewBuilder
    private var mainIPTVContent: some View {
        if let activeProfile = profilesManager.activeProfile {
            ContentView(showingSettings: $showingSettings)
                .environmentObject(downloadManager)
                .environmentObject(profilesManager)
                .environmentObject(activeProfile)
                .environment(RemotePlayManager.shared)
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    RemotePlayManager.shared.ensureDiscoveryActive()
                    // Pull remote watch history changes when app comes back to foreground
                    Task { await WatchHistorySyncEngine.shared.pull() }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Flush any pending debounced push immediately on background
                    Task { await WatchHistorySyncEngine.shared.pushNow() }
                }
                #endif
        } else {
            IPTVProfilesView(manager: profilesManager)
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard url.isFileURL else {
            MKSLog.app.info("[App] Ignoring non-file URL: \(url)")
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
import IPTVCore

/// Notification to open player window from non-View context
extension Notification.Name {
    static let openPlayerWindow = Notification.Name("openPlayerWindow")
}

/// Helper to open player window from non-View context
enum FilePlayerOpener {
    private static var playerWindowController: NSWindowController?
    
    @MainActor
    static func openPlayerWindow(with url: URL) {
        MKSLog.app.info("[FilePlayerOpener] Opening player window for: \(url.path)")
        
        let title = url.deletingPathExtension().lastPathComponent
        let player = PlayerFactory.shared.createPlayer(for: url)

        PlayerWindowManager.shared.present(
            player: player,
            title: title,
            metadata: nil
        )
        
        MKSLog.app.info("[FilePlayerOpener] Player configured in PlayerWindowManager")

        player.load(url: url)
        player.play()
        
        MKSLog.app.info("[FilePlayerOpener] Player loaded and playing")

        // Create or show the player window directly via AppKit
        createAndShowPlayerWindow()
    }
    
    @MainActor
    private static func createAndShowPlayerWindow() {
        // If window already exists, just bring it to front
        if let existingWindow = NSApplication.shared.windows.first(where: { 
            $0.identifier?.rawValue == "mks-player-window"
        }) {
            MKSLog.app.info("[FilePlayerOpener] Reusing existing player window")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        
        MKSLog.app.info("[FilePlayerOpener] Creating new player window")
        
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
        
        MKSLog.app.info("[FilePlayerOpener] Player window created and shown")
        
        // Debug: List all windows
        MKSLog.app.info("[FilePlayerOpener] Current windows:")
        for w in NSApplication.shared.windows {
            MKSLog.app.debug("  - \(w.title) [id: \(w.identifier?.rawValue ?? "nil")]")
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

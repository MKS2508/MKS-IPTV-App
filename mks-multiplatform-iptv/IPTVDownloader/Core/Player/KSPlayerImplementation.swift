import SwiftUI
import Combine

#if canImport(KSPlayer)
import KSPlayer
#endif

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - KSPlayer Implementation

#if canImport(KSPlayer)

// MARK: - Platform-specific KSPlayer Views

#if os(iOS)
struct KSPlayerViewWrapper: UIViewRepresentable {
    let url: URL
    let options: KSOptions
    let onPlayTimeChange: (TimeInterval, TimeInterval) -> Void
    let onStateChange: (KSPlayerState) -> Void

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let playerView = IOSVideoPlayerView()

        playerView.playTimeDidChange = { currentTime, totalTime in
            DispatchQueue.main.async {
                onPlayTimeChange(currentTime, totalTime)
            }
        }

        let coordinator = context.coordinator
        coordinator.onStateChange = onStateChange
        playerView.delegate = coordinator

        KSOptions.isAutoPlay = true
        let resource = KSPlayerResource(url: url, options: options, name: url.lastPathComponent)
        playerView.set(resource: resource)

        return playerView
    }

    func updateUIView(_ uiView: IOSVideoPlayerView, context: Context) {}

    func makeCoordinator() -> PlayerCoordinator {
        PlayerCoordinator()
    }
}
#endif

#if os(macOS)
struct KSPlayerViewWrapper: NSViewRepresentable {
    let url: URL
    let options: KSOptions
    let onPlayTimeChange: (TimeInterval, TimeInterval) -> Void
    let onStateChange: (KSPlayerState) -> Void

    func makeNSView(context: Context) -> MacVideoPlayerView {
        let playerView = MacVideoPlayerView()

        playerView.playTimeDidChange = { currentTime, totalTime in
            DispatchQueue.main.async {
                onPlayTimeChange(currentTime, totalTime)
            }
        }

        let coordinator = context.coordinator
        coordinator.onStateChange = onStateChange
        playerView.delegate = coordinator

        KSOptions.isAutoPlay = true
        let resource = KSPlayerResource(url: url, options: options, name: url.lastPathComponent)
        playerView.set(resource: resource)

        return playerView
    }

    func updateNSView(_ nsView: MacVideoPlayerView, context: Context) {}

    func makeCoordinator() -> PlayerCoordinator {
        PlayerCoordinator()
    }
}
#endif

// MARK: - Player Coordinator

class PlayerCoordinator: NSObject, PlayerControllerDelegate {
    var onStateChange: ((KSPlayerState) -> Void)?

    func playerController(state: KSPlayerState) {
        onStateChange?(state)
    }

    func playerController(currentTime: TimeInterval, totalTime: TimeInterval) {}
    func playerController(finish error: Error?) {}
    func playerController(maskShow: Bool) {}
    func playerController(action: PlayerButtonType) {}
    func playerController(bufferedCount: Int, consumeTime: TimeInterval) {}
    func playerController(seek: TimeInterval) {}
}

// MARK: - KSPlayer Implementation (Active)

class KSPlayerImplementation: VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var rate: Float = 1.0
    @Published var isReady: Bool = false
    @Published var error: PlayerError?

    private let progressSubject = PassthroughSubject<Double, Never>()
    private var currentURL: URL?
    private var customHeaders: [String: String] = [:]

    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    static func isAvailable() -> Bool { true }

    /// Create IPTV-optimized KSOptions for the given URL
    func makeOptions(for url: URL) -> KSOptions {
        let options = KSOptions()

        // For non-native formats (MKV, AVI, etc.), use KSMEPlayer (FFmpeg) directly.
        // Skips the KSAVPlayer attempt that always fails on MKV and wastes an IPTV
        // server connection — critical for servers with single-connection limits.
        let ext = url.pathExtension.lowercased()
        let nativeFormats = ["mp4", "m4v", "mov", "m3u8"]
        if !nativeFormats.contains(ext) {
            KSOptions.firstPlayerType = KSMEPlayer.self
            KSOptions.secondPlayerType = KSAVPlayer.self
        } else {
            KSOptions.firstPlayerType = KSAVPlayer.self
            KSOptions.secondPlayerType = KSMEPlayer.self
        }

        // IPTV reconnection
        options.formatContextOptions["reconnect"] = 1
        options.formatContextOptions["reconnect_streamed"] = 1
        options.formatContextOptions["reconnect_on_network_error"] = 1
        options.formatContextOptions["reconnect_delay_max"] = 5
        options.formatContextOptions["scan_all_pmts"] = 1

        // Default headers for IPTV servers
        var headers = [
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
            "Accept-Encoding": "identity",
            "Connection": "Keep-Alive",
        ]
        // Merge custom headers (overrides defaults)
        for (key, value) in customHeaders {
            headers[key] = value
        }
        options.appendHeader(headers)

        // Live stream detection
        let path = url.path.lowercased()
        let isLive = path.contains("/live/") || path.hasSuffix(".m3u8") || path.hasSuffix(".ts")
        if isLive {
            options.formatContextOptions["fflags"] = "nobuffer"
            options.formatContextOptions["analyzeduration"] = 1_000_000  // 1s
            options.formatContextOptions["probesize"] = 500_000
        }

        return options
    }

    func setCustomHeaders(_ headers: [String: String]) {
        customHeaders = headers
    }

    func load(url: URL) {
        currentURL = url
        isReady = false
        error = nil
        print("[KSPlayer] Loading URL: \(url)")
    }

    func play() {
        isPlaying = true
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        isPlaying = false
        currentTime = 0
        duration = 0
        isReady = false
    }

    func seek(to time: Double) {
        currentTime = time
        progressSubject.send(time)
    }

    func playerView() -> AnyView {
        guard let url = currentURL else {
            return AnyView(placeholderView)
        }

        let options = makeOptions(for: url)
        let wrapper = KSPlayerViewWrapper(
            url: url,
            options: options,
            onPlayTimeChange: { [weak self] currentTime, totalTime in
                self?.currentTime = currentTime
                self?.duration = totalTime
                self?.progressSubject.send(currentTime)
            },
            onStateChange: { [weak self] state in
                switch state {
                case .readyToPlay:
                    self?.isReady = true
                    self?.error = nil
                case .error:
                    self?.error = .decodingError
                default:
                    break
                }
            }
        )

        return AnyView(wrapper)
    }

    private var placeholderView: some View {
        ZStack {
            Color.black
            VStack {
                Image(systemName: "tv")
                    .font(.system(size: 50))
                    .foregroundColor(.gray)
                Text("KSPlayer Ready")
                    .foregroundColor(.gray)
                    .padding()
                Text("Load a video to start")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.7))
            }
        }
    }

    deinit {
        stop()
    }
}

#else

// MARK: - KSPlayer Not Available - Fallback

class KSPlayerImplementation: VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var rate: Float = 1.0
    @Published var isReady: Bool = false
    @Published var error: PlayerError?

    private let progressSubject = PassthroughSubject<Double, Never>()

    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    static func isAvailable() -> Bool { false }

    func load(url: URL) {
        print("[KSPlayer] Module not available - cannot load")
        error = PlayerError.unsupportedFormat
    }

    func play() {}
    func pause() {}
    func stop() {}
    func seek(to time: Double) {}

    func playerView() -> AnyView {
        AnyView(
            ZStack {
                Color.black
                Text("KSPlayer module not installed")
                    .foregroundColor(.gray)
            }
        )
    }
}

#endif

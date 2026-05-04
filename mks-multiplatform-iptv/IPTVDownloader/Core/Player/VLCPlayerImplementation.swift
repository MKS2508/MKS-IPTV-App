import SwiftUI
import Combine
import AVFoundation
import IPTVCore

// MARK: - VLC Player Implementation
// Conditional imports for VLCKit
#if canImport(VLCKitSPM)
import VLCKitSPM
typealias VLCMediaPlayerType = VLCMediaPlayer
typealias VLCMediaType = VLCMedia
typealias VLCTimeType = VLCTime
protocol VLCMediaPlayerDelegateType: VLCMediaPlayerDelegate {}
#else
// VLCKit not available - placeholder types
typealias VLCMediaPlayerType = AnyObject
typealias VLCMediaType = AnyObject
typealias VLCTimeType = AnyObject
protocol VLCMediaPlayerDelegateType {}
#endif

class VLCPlayerImplementation: NSObject, VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var rate: Float = 1.0
    @Published var isReady: Bool = false
    @Published var error: PlayerError?
    
    private let progressSubject = PassthroughSubject<Double, Never>()
    private var progressTimer: Timer?
    private var mediaPlayer: VLCMediaPlayerType?
    private var media: VLCMediaType?

    /// The original source URL passed to load(url:).
    private(set) var sourceURL: URL?
    
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    // Check if VLCKit is available
    static func isAvailable() -> Bool {
        #if canImport(VLCKitSPM)
            return true
        #else
            return false
        #endif
    }

    func load(url: URL) {
        load(url: url, metadata: nil)
    }

    func load(url: URL, metadata: MetadataResult?) {
        // Note: VLC doesn't support externalMetadata like AVPlayer does
        // Metadata is ignored but we log it for debugging
        if let metadata = metadata {
            MKSLog.player.debug("Metadata provided but VLC doesn't support externalMetadata: \(metadata.title)")
        }
        loadInternal(url: url)
    }

    private func loadInternal(url: URL) {
        self.sourceURL = url
        guard VLCPlayerImplementation.isAvailable() else {
            error = .unsupportedFormat
            MKSLog.player.error("VLCKit not available")
            return
        }
        
        // Validate URL
        guard url.scheme != nil else {
            error = .networkError(NSError(domain: "VLCPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            MKSLog.player.error("Invalid URL: \(url)")
            return
        }
        
        // Clean up existing player
        stop()
        
        #if canImport(VLCKitSPM)
        MKSLog.player.info("Loading URL: \(url)")
        
        // Create media with IPTV-optimized options
        let newMedia = VLCMediaType(url: url)
        guard newMedia.url != nil else {
            error = .networkError(NSError(domain: "VLCPlayer", code: -2,
                                         userInfo: [NSLocalizedDescriptionKey: "VLCMedia failed to initialize for URL: \(url)"]))
            MKSLog.player.error("VLCMedia creation returned invalid media for URL: \(url)")
            return
        }
        media = newMedia

        // Configure media options for IPTV streaming
        let options: [String: Any] = [
            // Network caching for smoother streaming
            "network-caching": 3000,      // 3 second buffer
            "live-caching": 1000,         // 1 second for live streams
            "rtsp-caching": 2000,         // 2 seconds for RTSP
            "http-reconnect": true,       // Auto-reconnect on HTTP streams
            
            // Transport stream optimization
            "ts-seek-percent": 100,       // Better seeking in TS files
            "ts-seek-mode": "fast",       // Fast seeking in transport streams
            
            // Network resilience
            "http-timeout": 15000,        // 15 second timeout
            "tcp-timeout": 15000,         // 15 second TCP timeout
            "server-timeout": 15000,      // 15 second server timeout
            
            // Audio/Video sync
            "clock-jitter": 0,            // Disable clock jitter for IPTV
            "clock-synchro": 0,           // Disable clock sync
            "avcodec-skiploopfilter": 0,  // Skip loop filter for better performance
            
            // Platform specific
            "no-xlib": true               // Disable X11 on macOS
        ]
        
        // Apply options to media
        for (key, value) in options {
            media?.addOption(":\(key)=\(value)")
        }
        
        // Additional optimization for live streams
        if url.absoluteString.contains(".m3u8") || url.absoluteString.contains("/live/") {
            MKSLog.player.info("Detected live stream, applying live optimizations")
            media?.addOption(":program=0")     // Use first program
            media?.addOption(":dvb-adapter=0") // Default DVB adapter
        }
        
        // Log format-specific optimizations
        let fileExtension = url.pathExtension.lowercased()
        MKSLog.player.debug("Format: \(fileExtension)")
        
        // Create media player and assign media
        let player = VLCMediaPlayerType()
        guard let validMedia = media else {
            error = .networkError(NSError(domain: "VLCPlayer", code: -3,
                                         userInfo: [NSLocalizedDescriptionKey: "Media became nil before player assignment"]))
            MKSLog.player.error("Media is nil, cannot assign to player")
            return
        }
        player.media = validMedia
        player.delegate = self
        mediaPlayer = player
        mediaPlayer?.drawable = nil // Will be set when view is created
        
        // Configure player settings
        mediaPlayer?.audio?.volume = Int32(volume * 100)
        mediaPlayer?.rate = rate
        
        MKSLog.player.info("Successfully loaded URL with VLC")
        #endif
    }
    
    func play() {
        guard VLCPlayerImplementation.isAvailable() else { return }
        
        #if canImport(VLCKitSPM)
        guard let player = mediaPlayer else { return }
        
        player.play()
        MKSLog.player.info("Starting playback")
        #endif
    }
    
    func pause() {
        guard VLCPlayerImplementation.isAvailable() else { return }
        
        #if canImport(VLCKitSPM)
        guard let player = mediaPlayer else { return }
        
        player.pause()
        isPlaying = false
        MKSLog.player.info("Paused playback")
        #endif
    }
    
    func stop() {
        #if canImport(VLCKitSPM)
        mediaPlayer?.stop()
        mediaPlayer = nil
        media = nil
        #endif
        
        progressTimer?.invalidate()
        progressTimer = nil
        
        isPlaying = false
        currentTime = 0
        duration = 0
        isReady = false
        
        MKSLog.player.info("Stopped playback")
    }
    
    func seek(to time: Double) {
        guard VLCPlayerImplementation.isAvailable() else { return }
        
        #if canImport(VLCKitSPM)
        guard let player = mediaPlayer else { return }
        
        player.time = VLCTimeType(int: Int32(time * 1000)) // Convert to milliseconds
        currentTime = time
        
        MKSLog.player.info("Seeked to \(time)s")
        #endif
    }
    
    func playerView() -> AnyView {
        if VLCPlayerImplementation.isAvailable() {
            return AnyView(
                VLCPlayerView { [weak self] view in
                    #if canImport(VLCKitSPM)
                    self?.mediaPlayer?.drawable = view
                    #endif
                }
            )
        } else {
            return AnyView(
                ZStack {
                    Color.black
                    VStack {
                        Image(systemName: "tv.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("VLCKit not integrated")
                            .foregroundColor(.gray)
                            .padding()
                        Text("Add VLCKit to enable MKV playback")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
            )
        }
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Private Methods
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func updateProgress() {
        guard VLCPlayerImplementation.isAvailable() else { return }
        
        #if canImport(VLCKitSPM)
        guard let player = mediaPlayer else { return }
        
        let currentTime = Double(player.time.intValue) / 1000.0
        let duration = Double(player.media?.length.intValue ?? 0) / 1000.0
        
        DispatchQueue.main.async { [weak self] in
            self?.currentTime = currentTime
            self?.duration = duration
            
            if duration > 0 {
                let progress = currentTime / duration
                self?.progressSubject.send(progress)
            }
        }
        #endif
    }
}

// MARK: - VLC Media Player Delegate
#if canImport(VLCKitSPM)
extension VLCPlayerImplementation: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = mediaPlayer else { return }
        
        DispatchQueue.main.async { [weak self] in
            switch player.state {
            case .opening:
                MKSLog.player.debug("State: Opening")
            case .buffering:
                MKSLog.player.debug("State: Buffering")
            case .playing:
                self?.isPlaying = true
                self?.isReady = true
                self?.startProgressTimer()
                MKSLog.player.info("State: Playing")
            case .paused:
                self?.isPlaying = false
                MKSLog.player.info("State: Paused")
            case .stopped:
                self?.isPlaying = false
                self?.progressTimer?.invalidate()
                MKSLog.player.info("State: Stopped")
            case .ended:
                self?.isPlaying = false
                self?.currentTime = self?.duration ?? 0
                self?.progressTimer?.invalidate()
                MKSLog.player.info("State: Ended")
            case .error:
                self?.error = .decodingError
                MKSLog.player.error("State: Playback error occurred")
                MKSLog.player.error("URL: \(String(describing: self?.media?.url))")
            case .esAdded:
                MKSLog.player.debug("State: Elementary stream added")
            @unknown default:
                break
            }
        }
    }
    
    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        updateProgress()
    }
}
#endif

// MARK: - VLC Player View (Cross-Platform)
struct VLCPlayerView: View {
    private let viewSetup: (Any) -> Void
    
    init(viewSetup: @escaping (Any) -> Void) {
        self.viewSetup = viewSetup
    }
    
    var body: some View {
        #if os(macOS)
        VLCPlayerViewMacOS(viewSetup: viewSetup)
        #elseif canImport(UIKit)
        VLCPlayerViewiOS(viewSetup: viewSetup)
        #else
        EmptyView()
        #endif
    }
}

// MARK: - VLC Player View macOS
#if os(macOS)
struct VLCPlayerViewMacOS: NSViewRepresentable {
    private let viewSetup: (Any) -> Void
    
    init(viewSetup: @escaping (Any) -> Void) {
        self.viewSetup = viewSetup
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        viewSetup(view)
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Update view if needed
    }
}
#endif

// MARK: - VLC Player View iOS
#if canImport(UIKit)
import UIKit
import IPTVCore

struct VLCPlayerViewiOS: UIViewRepresentable {
    private let viewSetup: (Any) -> Void
    
    init(viewSetup: @escaping (Any) -> Void) {
        self.viewSetup = viewSetup
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        viewSetup(view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
}
#endif


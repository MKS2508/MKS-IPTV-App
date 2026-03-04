import SwiftUI
import AVKit
import Combine
import TransmuxCore

// MARK: - FFmpeg Player Implementation
/// Transmux pipeline player: remuxes non-native formats (MKV, AVI, etc.) to
/// fragmented MP4 via TransmuxingService, then plays through AVPlayer.
/// This enables AirPlay and PiP for content that AVPlayer cannot handle directly.
///
/// ## Progressive Playback
/// Playback begins as soon as the fMP4 header is written. The remux loop
/// continues in the background, writing to a growing file that TransmuxServer
/// serves over localhost HTTP with Range request support.
class FFmpegPlayerImplementation: VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var rate: Float = 1.0
    @Published var isReady: Bool = false
    @Published var isBuffering: Bool = false
    @Published var error: PlayerError?

    private var avPlayer: AVPlayerImplementation?
    private let configuration: PlayerConfiguration
    private let progressSubject = PassthroughSubject<Double, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var transmuxSessionID: String?
    @Published private(set) var isTransmuxing: Bool = false

    /// Stored metadata to pass to the inner AVPlayer after transmux starts
    private var pendingMetadata: MetadataResult?

    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    init(configuration: PlayerConfiguration) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    func load(url: URL) {
        load(url: url, metadata: nil)
    }

    func load(url: URL, metadata: MetadataResult?) {
        print("[FFmpegPlayer] Loading URL: \(url)")
        isTransmuxing = true
        error = nil
        pendingMetadata = metadata

        Task { @MainActor in
            do {
                // Step 0: Preflight -- validate stream reachability before transmux
                let preflight = await StreamPreflight.check(url: url)
                print("[FFmpegPlayer] Preflight: \(preflight.summary)")

                guard preflight.isReachable else {
                    self.isTransmuxing = false
                    self.error = .networkError(
                        NSError(domain: "StreamPreflight", code: preflight.httpStatus ?? -1,
                                userInfo: [NSLocalizedDescriptionKey: "Stream unreachable: \(preflight.error ?? "unknown")"])
                    )
                    print("[FFmpegPlayer] Preflight failed -- aborting transmux")
                    return
                }

                // Step 1: Start progressive transmux (returns after header written)
                let session = try await TransmuxingService.shared.startTransmux(from: url)
                self.transmuxSessionID = session.sessionID

                // Step 2: Start HTTP server serving both m3u8 playlist and mp4 byte ranges.
                // HLSSegmenter (created by TransmuxingService) generates a byte-range HLS
                // playlist as the fMP4 grows. TransmuxServer serves both files so AVPlayer
                // can consume HLS natively — no custom resource loader needed.
                var effectiveSize = session.expectedSize
                if effectiveSize <= 0, let preflightSize = preflight.contentLength, preflightSize > 0 {
                    effectiveSize = preflightSize
                    print("[FFmpegPlayer] Using preflight contentLength as expectedSize: \(effectiveSize)")
                }
                print("[FFmpegPlayer] expectedSize=\(effectiveSize), session.expectedSize=\(session.expectedSize)")

                let serverSession = try await TransmuxServer.shared.start(
                    filePath: session.outputPath,
                    playlistPath: session.playlistPath,
                    expectedSize: effectiveSize,
                    segmenter: session.segmenter,
                    initSegmentSize: session.initSegmentSize,
                    seekHandle: session.seekHandle
                )

                // Step 3: Load the HLS playlist URL — AVPlayer handles HLS natively.
                // The playlist is VOD+ENDLIST from the start, so AVPlayer sees full
                // duration immediately and allows seeking to any position.
                let hlsURL = serverSession.localURL
                print("[FFmpegPlayer] Loading VOD HLS playlist: \(hlsURL)")
                self.isTransmuxing = false
                self.avPlayer = AVPlayerImplementation()
                self.avPlayer?.load(url: hlsURL, metadata: self.pendingMetadata)
                self.setupBindings()

                // Observe transmux completion for logging/cleanup only.
                // No reloadAsVOD needed — playlist is already VOD from the start.
                NotificationCenter.default.publisher(for: .transmuxDidComplete)
                    .compactMap { $0.object as? String }
                    .filter { [weak self] id in id == self?.transmuxSessionID }
                    .first()
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        print("[FFmpegPlayer] Transmux complete — sequential transmux finished (VOD playlist was already active)")
                    }
                    .store(in: &self.cancellables)

                // Step 4: Auto-play to trigger AVPlayer buffering
                print("[FFmpegPlayer] Auto-playing to trigger buffering...")
                self.avPlayer?.play()
                self.isPlaying = true
            } catch {
                self.isTransmuxing = false
                self.error = .unknown(error)
                print("[FFmpegPlayer] Transmux failed: \(error)")
            }
        }
    }

    func play() {
        avPlayer?.play()
    }

    func pause() {
        avPlayer?.pause()
    }

    func stop() {
        avPlayer?.stop()
        avPlayer = nil
        cancellables.removeAll()

        if let sessionID = transmuxSessionID {
            Task {
                await TransmuxingService.shared.cancelTransmux(sessionID: sessionID)
                await TransmuxServer.shared.stop()
                await TransmuxingService.shared.cleanup(sessionID: sessionID)
            }
            transmuxSessionID = nil
        }
    }

    func seek(to time: Double) {
        avPlayer?.seek(to: time)
    }

    /// Returns the inner AVPlayer's view when transmux is complete.
    /// Used by FFmpegPlayerContentView to reactively switch from spinner to video.
    func innerPlayerView() -> AnyView? {
        avPlayer?.playerView()
    }

    func playerView() -> AnyView {
        AnyView(FFmpegPlayerContentView(player: self))
    }

    /// The underlying AVPlayer instance, if the transmux pipeline has produced one.
    var underlyingAVPlayer: AVPlayer? {
        avPlayer?.underlyingAVPlayer
    }

    /// Forward buffering detail from the inner AVPlayer, with transmux context.
    var bufferingDetail: PlayerBufferingDetail {
        if isTransmuxing {
            return PlayerBufferingDetail(
                isBuffering: true,
                reason: "Transmuxing...",
                loadedRangeAhead: nil,
                bitrate: nil,
                stallCount: 0,
                playerRate: nil
            )
        }
        return avPlayer?.bufferingDetail ?? .idle
    }

    // MARK: - Private Methods

    private func setupBindings() {
        guard let avPlayer = avPlayer else { return }

        avPlayer.$isPlaying
            .assign(to: &$isPlaying)

        avPlayer.$currentTime
            .assign(to: &$currentTime)

        avPlayer.$duration
            .assign(to: &$duration)

        avPlayer.$isReady
            .assign(to: &$isReady)

        avPlayer.$error
            .assign(to: &$error)

        avPlayer.$isBuffering
            .assign(to: &$isBuffering)

        $volume
            .sink { [weak avPlayer] volume in
                avPlayer?.volume = volume
            }
            .store(in: &cancellables)

        $rate
            .sink { [weak avPlayer] rate in
                avPlayer?.rate = rate
            }
            .store(in: &cancellables)

        avPlayer.progressPublisher
            .sink { [weak self] progress in
                self?.progressSubject.send(progress)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Reactive Content View

/// Observes @Published properties on FFmpegPlayerImplementation so the view
/// re-evaluates when `isTransmuxing` / `avPlayer` change. This fixes the stale
/// AnyView problem where the spinner was captured once and never updated.
fileprivate struct FFmpegPlayerContentView: View {
    @ObservedObject var player: FFmpegPlayerImplementation

    var body: some View {
        if player.isTransmuxing {
            ZStack {
                Color.black
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Preparing video for playback...")
                        .foregroundColor(.white)
                        .font(.callout)
                    Text("Transmuxing to compatible format")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            }
        } else if let innerView = player.innerPlayerView() {
            ZStack {
                innerView
                if player.isBuffering {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)

                        let detail = player.bufferingDetail
                        Text(detail.reason ?? "Buffering...")
                            .font(.callout)
                            .foregroundStyle(.white)

                        if let ahead = detail.loadedRangeAhead {
                            Text("\(String(format: "%.1f", ahead))s buffered")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        } else {
            ZStack {
                Color.black
                VStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("FFmpeg Transmux Player")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                    Text("Load a non-native format to start")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
        }
    }
}

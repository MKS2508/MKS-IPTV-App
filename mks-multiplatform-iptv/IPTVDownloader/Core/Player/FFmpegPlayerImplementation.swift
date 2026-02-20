import SwiftUI
import AVKit
import Combine

// MARK: - FFmpeg Player Implementation
/// Transmux pipeline player: remuxes non-native formats (MKV, AVI, etc.) to
/// fragmented MP4 / HLS via TransmuxingService, then plays through AVPlayer.
/// This enables AirPlay and PiP for content that AVPlayer cannot handle directly.
/// Cross-platform — works on iOS, macOS, and tvOS (no shell dependency).
class FFmpegPlayerImplementation: VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var rate: Float = 1.0
    @Published var isReady: Bool = false
    @Published var error: PlayerError?

    private var avPlayer: AVPlayerImplementation?
    private let configuration: PlayerConfiguration
    private let progressSubject = PassthroughSubject<Double, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var transmuxSessionID: String?
    @Published private var isTransmuxing: Bool = false

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
        print("[FFmpegPlayer] Loading URL: \(url)")
        isTransmuxing = true
        error = nil

        Task { @MainActor in
            do {
                // Step 0: Preflight — validate stream reachability before transmux
                let preflight = await StreamPreflight.check(url: url)
                print("[FFmpegPlayer] Preflight: \(preflight.summary)")

                guard preflight.isReachable else {
                    self.isTransmuxing = false
                    self.error = .networkError(
                        NSError(domain: "StreamPreflight", code: preflight.httpStatus ?? -1,
                                userInfo: [NSLocalizedDescriptionKey: "Stream unreachable: \(preflight.error ?? "unknown")"])
                    )
                    print("[FFmpegPlayer] Preflight failed — aborting transmux")
                    return
                }

                // Step 1: Transmux to HLS/fMP4
                let result = try await TransmuxingService.shared.transmux(from: url)
                self.transmuxSessionID = result.sessionID

                // Step 2: Start local HLS server (if available)
                let playbackURL: URL
                #if canImport(FlyingFox)
                playbackURL = try await LocalHLSServer.shared.serve(
                    directory: result.segmentDirectory,
                    playlist: result.playlistURL.lastPathComponent
                )
                #else
                playbackURL = result.playlistURL
                #endif

                print("[FFmpegPlayer] Transmux complete, playing: \(playbackURL)")

                // Step 3: Feed to AVPlayer
                self.isTransmuxing = false
                self.avPlayer = AVPlayerImplementation()
                self.avPlayer?.load(url: playbackURL)
                self.setupBindings()
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

        // Cleanup transmux session and local server
        if let sessionID = transmuxSessionID {
            Task {
                await TransmuxingService.shared.cleanup(sessionID: sessionID)
                #if canImport(FlyingFox)
                await LocalHLSServer.shared.stop()
                #endif
            }
            transmuxSessionID = nil
        }
    }

    func seek(to time: Double) {
        avPlayer?.seek(to: time)
    }

    func playerView() -> AnyView {
        if isTransmuxing {
            return AnyView(
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
            )
        }

        if let avPlayer = avPlayer {
            return avPlayer.playerView()
        }

        return AnyView(
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
        )
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

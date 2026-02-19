import SwiftUI
import AVKit
import Combine

// MARK: - FFmpeg Player Implementation
// Simplified version - uses AVPlayer directly (transcoding removed as legacy)
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
        print("[FFmpegPlayerImplementation] Loading URL: \(url)")

        // Use AVPlayer directly (transcoding removed)
        self.avPlayer = AVPlayerImplementation()
        self.avPlayer?.load(url: url)
        self.setupBindings()
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
    }

    func seek(to time: Double) {
        avPlayer?.seek(to: time)
    }

    func playerView() -> AnyView {
        if let avPlayer = avPlayer {
            return avPlayer.playerView()
        } else {
            return AnyView(
                ZStack {
                    Color.black
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Loading video...")
                            .foregroundColor(.white)
                            .padding()
                    }
                }
            )
        }
    }

    // MARK: - Private Methods
    private func setupBindings() {
        guard let avPlayer = avPlayer else { return }

        // Bind all properties
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

        // Forward volume changes
        $volume
            .sink { [weak avPlayer] volume in
                avPlayer?.volume = volume
            }
            .store(in: &cancellables)

        // Forward rate changes
        $rate
            .sink { [weak avPlayer] rate in
                avPlayer?.rate = rate
            }
            .store(in: &cancellables)

        // Forward progress updates
        avPlayer.progressPublisher
            .sink { [weak self] progress in
                self?.progressSubject.send(progress)
            }
            .store(in: &cancellables)
    }
}

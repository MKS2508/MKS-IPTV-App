import SwiftUI
import AVKit
import Combine

// MARK: - AVPlayer Implementation
class AVPlayerImplementation: VideoPlayerProtocol, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }
    @Published var rate: Float = 1.0 {
        didSet {
            if isPlaying {
                player?.rate = rate
            }
        }
    }
    @Published var isReady: Bool = false
    @Published var error: PlayerError?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let progressSubject = PassthroughSubject<Double, Never>()
    
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    deinit {
        stop()
    }
    
    func load(url: URL) {
        stop()
        
        print("[AVPlayerImplementation] Loading URL: \(url)")
        
        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        
        setupObservers()
    }
    
    func play() {
        player?.play()
        player?.rate = rate
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func stop() {
        player?.pause()
        
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
        
        player = nil
        playerItem = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        duration = 0
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime) { [weak self] _ in
            self?.currentTime = time
        }
    }
    
    func playerView() -> AnyView {
        AnyView(
            VideoPlayer(player: player)
                .onAppear {
                    // Configure for iOS/macOS differences if needed
                }
        )
    }
    
    // MARK: - Private Methods
    private func setupObservers() {
        // Observe player item status
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isReady = true
                    self?.duration = self?.playerItem?.duration.seconds ?? 0
                    print("[AVPlayerImplementation] Ready to play, duration: \(self?.duration ?? 0)")
                case .failed:
                    if let error = self?.playerItem?.error {
                        self?.error = .unknown(error)
                        print("[AVPlayerImplementation] Failed to load: \(error)")
                    }
                case .unknown:
                    print("[AVPlayerImplementation] Unknown status")
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe playback progress
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            if seconds.isFinite {
                self?.currentTime = seconds
                self?.progressSubject.send(seconds)
            }
        }
        
        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.isPlaying = false
                print("[AVPlayerImplementation] Playback ended")
            }
            .store(in: &cancellables)
        
        // Observe errors
        playerItem?.publisher(for: \.error)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.error = .unknown(error)
                print("[AVPlayerImplementation] Error occurred: \(error)")
            }
            .store(in: &cancellables)
    }
}
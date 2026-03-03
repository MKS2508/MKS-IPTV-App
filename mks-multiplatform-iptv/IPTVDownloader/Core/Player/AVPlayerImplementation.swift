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
    @Published var isBuffering: Bool = false
    @Published var error: PlayerError?
    
    private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private let progressSubject = PassthroughSubject<Double, Never>()
    
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var underlyingAVPlayer: AVPlayer? { player }

    deinit {
        stop()
    }
    
    func load(url: URL) {
        stop()

        print("[AVPlayerImplementation] Loading URL: \(url)")

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        // For HLS via TransmuxServer, let AVPlayer buffer properly before starting.
        // Setting automaticallyWaitsToMinimizeStalling = false here causes CMTimebase
        // NULL errors because play() is called before segment data arrives (~1s delay),
        // and AVPlayer's clock runs with no media data, corrupting the timebase.
        // The default (true) queues the play intent and waits for sufficient buffer.
        // NOTE: load(asset:) still uses false for direct fMP4 resource-loader streaming.

        setupObservers()
    }

    func load(asset: AVURLAsset) {
        stop()

        print("[AVPlayerImplementation] Loading asset with resource loader, URL: \(asset.url)")
        print("[AVPlayerImplementation] Asset resourceLoader delegate: \(String(describing: asset.resourceLoader.delegate))")

        // Only require "playable" — NOT "duration". For fragmented MP4 with
        // empty_moov, the moov atom has duration=0 and there's no mfra box until
        // transmux finishes. If we require "duration", AVPlayer waits forever
        // (can't determine duration of a growing file) and never reaches .readyToPlay.
        playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        // Don't wait for large buffer — start playback as soon as first frames are available
        player?.automaticallyWaitsToMinimizeStalling = false

        print("[AVPlayerImplementation] AVPlayer created, playerItem.status=\(playerItem?.status.rawValue ?? -1), waitToMinimizeStalling=false")

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
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
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
    
    /// Replace the current AVPlayer with a completely NEW instance.
    /// Forces AVPlayer to re-parse the HLS playlist from scratch (EVENT -> VOD transition),
    /// enabling full duration display and arbitrary seeking.
    ///
    /// - Important: `replaceCurrentItem(with:)` does NOT work because AVPlayer's HLS
    ///   state machine is tied to the AVPlayer instance, not the AVPlayerItem. When
    ///   AVPlayer first loads an EVENT playlist (no ENDLIST), it internally classifies
    ///   the stream as "live/sliding" and `replaceCurrentItem` doesn't reset this.
    ///   Only creating a NEW AVPlayer forces a fresh HLS playlist parse.
    func reloadCurrentItem() {
        guard let currentItem = playerItem,
              let urlAsset = currentItem.asset as? AVURLAsset else { return }

        let position = player?.currentTime() ?? .zero
        let wasPlaying = rate > 0

        print("[AVPlayerImplementation] Reloading with NEW AVPlayer instance — URL: \(urlAsset.url)")
        print("[AVPlayerImplementation] Current position: \(position.seconds)s, wasPlaying: \(wasPlaying)")

        // Tear down old observers
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()

        // Create NEW AVPlayer and AVPlayerItem — forces fresh HLS playlist parse
        // This is the key: replaceCurrentItem(with:) doesn't reset HLS state machine
        playerItem = AVPlayerItem(url: urlAsset.url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.automaticallyWaitsToMinimizeStalling = false

        print("[AVPlayerImplementation] New AVPlayer created, re-attaching observers...")

        // Re-attach observers to new player/item
        setupObservers()

        // Restore position and playback state
        if position.seconds > 0 {
            player?.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                print("[AVPlayerImplementation] Seek to \(position.seconds)s complete, resuming: \(wasPlaying)")
                if wasPlaying {
                    self?.play()
                }
            }
        } else if wasPlaying {
            play()
        }
    }

    // MARK: - Private Methods
    private func setupObservers() {
        // Observe player item status
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isReady = true
                    let dur = self?.playerItem?.duration.seconds ?? 0
                    let isIndefinite = self?.playerItem?.duration.isIndefinite ?? false
                    self?.duration = dur
                    print("[AVPlayerImplementation] Ready to play, duration: \(dur)s, indefinite: \(isIndefinite)")
                case .failed:
                    if let error = self?.playerItem?.error {
                        self?.error = .unknown(error)
                        print("[AVPlayerImplementation] Failed to load: \(error)")
                        print("[AVPlayerImplementation] Error details: \((error as NSError).domain) code=\((error as NSError).code) \((error as NSError).localizedDescription)")
                        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                            print("[AVPlayerImplementation] Underlying error: \(underlying.domain) code=\(underlying.code) \(underlying.localizedDescription)")
                        }
                    }
                case .unknown:
                    let itemError = self?.playerItem?.error
                    let playerError = self?.player?.error
                    print("[AVPlayerImplementation] Unknown status — itemError=\(String(describing: itemError)), playerError=\(String(describing: playerError))")
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
        
        // Observe buffering state via timeControlStatus
        player?.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .waitingToPlayAtSpecifiedRate:
                    let reason = self.player?.reasonForWaitingToPlay
                    self.isBuffering = true
                    print("[AVPlayerImplementation] Buffering — reason: \(reason?.rawValue ?? "unknown")")
                case .playing:
                    self.isBuffering = false
                case .paused:
                    self.isBuffering = false
                @unknown default:
                    break
                }
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
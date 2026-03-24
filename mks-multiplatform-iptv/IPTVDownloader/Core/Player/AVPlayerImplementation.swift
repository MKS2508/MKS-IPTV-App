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

    /// Stored metadata for Now Playing info (Control Center / Lock Screen / AirPlay)
    private var pendingMetadata: MetadataResult?

    /// Whether the current stream is a live stream (affects reload/buffer behavior)
    private var isLiveStream: Bool = false

    /// Glitch detection and monitoring.
    /// Internal access allows FFmpegPlayerImplementation to wire the feedback callback.
    private(set) var glitchDetector: GlitchDetector?

    /// Track seek start time for latency measurement
    private var seekStartTime: Date?
    private var seekTargetPosition: Double?

    /// Track last position for external seek detection
    private var lastReportedTime: Double = 0
    private var seekObserver: Any?

    /// The original source URL passed to load(url:).
    private(set) var sourceURL: URL?

    // MARK: - External Seek Detection

    /// Último tiempo sampleado para detectar saltos
    private var lastSampledTime: Double = 0

    /// Timestamp del último sample
    private var lastSampleDate: Date?

    /// Flag para evitar detectar el mismo seek múltiples veces
    private var isProcessingExternalSeek: Bool = false

    /// Tiempo objetivo del seek externo detectado
    private var externalSeekTarget: Double?

    /// Tiempo cuando se detectó el seek externo
    private var externalSeekDetectedAt: Date?
    
    var progressPublisher: AnyPublisher<Double, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    var underlyingAVPlayer: AVPlayer? { player }

    var bufferingDetail: PlayerBufferingDetail {
        guard let player = player, let item = playerItem else { return .idle }

        let currentSec = player.currentTime().seconds
        var loadedAhead: Double? = nil
        if let range = item.loadedTimeRanges.first?.timeRangeValue {
            let bufferedEnd = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
            let ahead = bufferedEnd - currentSec
            if ahead.isFinite && ahead >= 0 {
                loadedAhead = ahead
            }
        }

        var bitrate: Double? = nil
        var stallCount = 0
        if let log = item.accessLog(), let event = log.events.last {
            if event.observedBitrate > 0 {
                bitrate = event.observedBitrate
            }
            stallCount = event.numberOfStalls
        }

        let reason: String?
        let waitingReason = player.reasonForWaitingToPlay
        if waitingReason == .toMinimizeStalls {
            reason = "Buffering..."
        } else if waitingReason == .noItemToPlay {
            reason = "No content"
        } else if waitingReason != nil {
            reason = "Evaluating..."
        } else {
            reason = isBuffering ? "Buffering..." : nil
        }

        return PlayerBufferingDetail(
            isBuffering: isBuffering,
            reason: reason,
            loadedRangeAhead: loadedAhead,
            bitrate: bitrate,
            stallCount: stallCount,
            playerRate: player.rate
        )
    }

    var bufferedTime: Double {
        guard let item = playerItem,
              let range = item.loadedTimeRanges.first?.timeRangeValue else {
            return 0
        }
        let bufferedEnd = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
        return bufferedEnd.isFinite ? bufferedEnd : 0
    }

    var isMuted: Bool {
        player?.isMuted ?? false
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying {
            player?.rate = newRate
        }
    }

    func togglePictureInPicture() {
        #if os(iOS) || os(macOS)
        if let pipController = pictureInPictureController {
            if pipController.isPictureInPictureActive {
                pipController.stopPictureInPicture()
            } else {
                pipController.startPictureInPicture()
            }
        }
        #endif
    }

    #if os(iOS) || os(macOS)
    private var pictureInPictureController: AVPictureInPictureController? {
        guard let player = player else { return nil }
        let playerLayer = AVPlayerLayer(player: player)
        if AVPictureInPictureController.isPictureInPictureSupported() {
            return try? AVPictureInPictureController(playerLayer: playerLayer)
        }
        return nil
    }
    #endif

    deinit {
        stop()
    }

    func load(url: URL) {
        load(url: url, metadata: nil)
    }

    func load(url: URL, metadata: MetadataResult?, isLive: Bool = false) {
        stop()

        self.sourceURL = url
        self.isLiveStream = isLive || url.path.lowercased().contains("/live/") || url.pathExtension.lowercased() == "m3u8" && url.path.lowercased().contains("/live/")

        // Start structured logging session
        PlayerLog.startSession(playerType: "AVPlayer", url: url.absoluteString)

        // Initialize glitch detector
        glitchDetector = GlitchDetector.forAVPlayer(sessionID: PlayerLog.sessionID)
        glitchDetector?.reset()

        PlayerLog.log("LOAD", category: "lifecycle", fields: [
            "url": url.absoluteString,
            "isLive": isLiveStream
        ])

        // Use AVURLAsset with IPTV-compatible HTTP headers.
        // Many Xtream Codes servers throttle or reject requests without a recognized User-Agent.
        let headers = IPTVConfiguration.defaultRequestHeaders()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        playerItem = AVPlayerItem(asset: asset)

        // For live HLS, set a moderate forward buffer to avoid the server
        // thinking the client is inactive. Default (~10s+) can cause stalls
        // when the server's segment window is small.
        if isLiveStream {
            playerItem?.preferredForwardBufferDuration = 6
        }

        // Store metadata for Now Playing info (Control Center / Lock Screen / AirPlay)
        self.pendingMetadata = metadata

        // Set externalMetadata on the AVPlayerItem so AVPlayerViewController can display
        // title, artist, and artwork in its UI, Control Center, Lock Screen, and AirPlay.
        // Without this, AVPlayerViewController overrides MPNowPlayingInfoCenter with empty metadata.
        // NOTE: externalMetadata is an AVKit extension available only on iOS/tvOS, not macOS.
        #if os(iOS) || os(tvOS) || os(visionOS)
        if let metadata = metadata, let item = playerItem {
            item.externalMetadata = PlayerMetadataHelper.buildExternalMetadata(from: metadata)
            PlayerMetadataHelper.loadExternalArtwork(for: item, from: metadata)
        }
        #endif

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

        // Start structured logging session
        PlayerLog.startSession(playerType: "AVPlayer", url: asset.url.absoluteString)

        // Initialize glitch detector
        glitchDetector = GlitchDetector.forAVPlayer(sessionID: PlayerLog.sessionID)
        glitchDetector?.reset()

        PlayerLog.log("LOAD_ASSET", category: "lifecycle", fields: [
            "url": asset.url.absoluteString,
            "hasResourceLoader": asset.resourceLoader.delegate != nil
        ])

        // Only require "playable" — NOT "duration". For fragmented MP4 with
        // empty_moov, the moov atom has duration=0 and there's no mfra box until
        // transmux finishes. If we require "duration", AVPlayer waits forever
        // (can't determine duration of a growing file) and never reaches .readyToPlay.
        playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        // Don't wait for large buffer — start playback as soon as first frames are available
        player?.automaticallyWaitsToMinimizeStalling = false

        PlayerLog.log("PLAYER_CREATED", category: "lifecycle", fields: [
            "status": playerItem?.status.rawValue ?? -1,
            "waitToMinimizeStalling": false
        ])

        setupObservers()
    }
    
    func play() {
        player?.play()
        player?.rate = rate
        isPlaying = true

        PlayerLog.stateChange(from: "paused", to: "playing", playerType: "AVPlayer")

        // Register remote commands (idempotent — only runs once per session).
        // Without this, macOS ignores MPNowPlayingInfoCenter entirely.
        if pendingMetadata != nil {
            PlayerMetadataHelper.setupRemoteTransportControls(
                onPlay: { [weak self] in self?.play() },
                onPause: { [weak self] in self?.pause() },
                onToggle: { [weak self] in
                    guard let self else { return }
                    self.isPlaying ? self.pause() : self.play()
                },
                onSeek: { [weak self] time in self?.seek(to: time) }
            )
        }

        // Set Now Playing info for Control Center / Lock Screen / AirPlay
        if let metadata = pendingMetadata {
            PlayerMetadataHelper.setNowPlayingInfo(
                from: metadata,
                duration: duration,
                currentTime: currentTime,
                playbackRate: Double(rate)
            )
            PlayerMetadataHelper.loadArtwork(from: metadata)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false

        PlayerLog.stateChange(from: "playing", to: "paused", playerType: "AVPlayer")

        // Update playback state and rate in Now Playing info
        if pendingMetadata != nil {
            PlayerMetadataHelper.updatePlaybackProgress(currentTime: currentTime, playbackRate: 0)
            PlayerMetadataHelper.setPlaybackStatePaused()
        }
    }

    func stop() {
        player?.pause()

        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        // Remover TODOS los observers de notificaciones
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()

        player = nil
        playerItem = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        duration = 0

        // Reset tracking state
        isLiveStream = false
        lastSampledTime = 0
        lastSampleDate = nil
        isProcessingExternalSeek = false
        externalSeekTarget = nil
        externalSeekDetectedAt = nil

        // Clear glitch detector
        glitchDetector?.reset()
        glitchDetector = nil

        // End logging session
        PlayerLog.endSession()

        // Teardown remote commands and clear Now Playing info
        PlayerMetadataHelper.teardownRemoteTransportControls()
        PlayerMetadataHelper.clearNowPlayingInfo()
        pendingMetadata = nil
    }
    
    func seek(to time: Double) {
        // Track seek start for latency measurement
        let currentPosition = currentTime
        glitchDetector?.seekStarted(target: time, currentPosition: currentPosition)
        seekStartTime = Date()
        seekTargetPosition = time

        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            self.currentTime = time

            // Track seek completion and report any latency glitches
            if finished {
                self.glitchDetector?.seekCompleted(actualPosition: time, duration: self.duration)
            } else {
                // Seek was cancelled or interrupted
                PlayerLog.log("SEEK_CANCELLED", category: "timing", level: .warning, fields: [
                    "target": String(format: "%.3f", time),
                    "from": String(format: "%.3f", currentPosition)
                ])
            }

            self.seekStartTime = nil
            self.seekTargetPosition = nil
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

        PlayerLog.log("RELOAD", category: "lifecycle", fields: [
            "url": urlAsset.url.absoluteString,
            "position": String(format: "%.3f", position.seconds),
            "wasPlaying": wasPlaying,
            "isLive": isLiveStream
        ])

        // Tear down old observers
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()

        // Create NEW AVPlayer and AVPlayerItem — forces fresh HLS playlist parse.
        // Use AVURLAsset with headers so the IPTV server recognizes the client.
        let headers = IPTVConfiguration.defaultRequestHeaders()
        let newAsset = AVURLAsset(url: urlAsset.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        playerItem = AVPlayerItem(asset: newAsset)

        // Reapply live buffer config on the new item
        if isLiveStream {
            playerItem?.preferredForwardBufferDuration = 6
        }

        // Re-apply external metadata on the new item so NowPlaying survives reload
        #if os(iOS) || os(tvOS) || os(visionOS)
        if let metadata = pendingMetadata, let item = playerItem {
            item.externalMetadata = PlayerMetadataHelper.buildExternalMetadata(from: metadata)
            PlayerMetadataHelper.loadExternalArtwork(for: item, from: metadata)
        }
        #endif

        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume

        // For VOD: disable auto-wait so playback resumes instantly after seek.
        // For live: keep the default (true) to let AVPlayer buffer from the live edge.
        if !isLiveStream {
            player?.automaticallyWaitsToMinimizeStalling = false
        }

        PlayerLog.log("RELOAD_PLAYER_CREATED", category: "lifecycle", fields: [:])

        // Re-attach observers to new player/item
        setupObservers()

        if isLiveStream {
            // Live streams: start from the live edge, don't seek to old position.
            // The old position is likely outside the playlist's sliding window,
            // which causes stream parse errors (-12312).
            PlayerLog.log("RELOAD_LIVE_EDGE", category: "lifecycle", fields: [
                "resuming": wasPlaying
            ])
            if wasPlaying {
                play()
            }
        } else {
            // VOD: restore position and playback state
            if position.seconds > 0 {
                player?.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    PlayerLog.log("RELOAD_SEEK_COMPLETE", category: "lifecycle", fields: [
                        "position": String(format: "%.3f", position.seconds),
                        "resuming": wasPlaying
                    ])
                    if wasPlaying {
                        self?.play()
                    }
                }
            } else if wasPlaying {
                play()
            }
        }
    }

    // MARK: - Private Methods
    private func setupObservers() {
        // Observe player item status
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .readyToPlay:
                    self.isReady = true
                    let dur = self.playerItem?.duration.seconds ?? 0
                    let isIndefinite = self.playerItem?.duration.isIndefinite ?? false
                    self.duration = dur
                    PlayerLog.log("READY", category: "lifecycle", fields: [
                        "duration": String(format: "%.1f", dur),
                        "indefinite": isIndefinite
                    ])
                case .failed:
                    if let error = self.playerItem?.error {
                        self.error = .unknown(error)
                        let nsError = error as NSError
                        PlayerLog.log("FAILED", category: "lifecycle", level: .critical, fields: [
                            "domain": nsError.domain,
                            "code": nsError.code,
                            "message": nsError.localizedDescription
                        ])
                        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                            PlayerLog.log("UNDERLYING_ERROR", category: "lifecycle", level: .critical, fields: [
                                "domain": underlying.domain,
                                "code": underlying.code,
                                "message": underlying.localizedDescription
                            ])
                        }
                    }
                case .unknown:
                    let itemError = self.playerItem?.error
                    let playerError = self.player?.error
                    PlayerLog.log("UNKNOWN_STATUS", category: "lifecycle", level: .warning, fields: [
                        "itemError": itemError?.localizedDescription ?? "nil",
                        "playerError": playerError?.localizedDescription ?? "nil"
                    ])
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        // Observe playback progress with glitch detection sampling
        let interval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }

            let now = Date()

            // Detectar seek externo por delta grande
            if self.isPlaying && !self.isProcessingExternalSeek {
                let timeDelta = seconds - self.lastSampledTime
                let absTimeDelta = abs(timeDelta)

                // Umbral: salto > 3 segundos = seek externo
                // (No consideramos saltos pequeños que pueden ser normales)
                if absTimeDelta > 3.0 {
                    // Verificar que no sea un seek interno (nuestro seek(to:) setea seekTargetPosition)
                    if self.seekTargetPosition == nil {
                        // For live streams, the initial jump from 0 to the live edge is normal —
                        // AVPlayer buffers and then starts from the current live position.
                        // Don't report this as an external seek.
                        let isLiveEdgeJump = self.isLiveStream && self.lastSampledTime == 0
                        if !isLiveEdgeJump {
                            self.reportExternalSeek(
                                from: self.lastSampledTime,
                                to: seconds,
                                source: "periodicObserver",
                                delta: timeDelta
                            )
                        }
                    }
                }
            }

            // Actualizar tracking
            self.lastSampledTime = seconds
            self.lastSampleDate = now
            self.currentTime = seconds
            self.progressSubject.send(seconds)

            // Sample for glitch detection
            self.glitchDetector?.sample(
                currentTime: seconds,
                duration: self.duration,
                playbackRate: self.rate,
                isPlaying: self.isPlaying,
                bufferAhead: self.bufferingDetail.loadedRangeAhead
            )

            // Update Now Playing progress every 5 seconds (throttled)
            // This keeps Control Center / Lock Screen progress bar in sync
            if self.pendingMetadata != nil && Int(seconds) % 5 == 0 {
                self.updateNowPlayingProgress()
            }
        }

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.isPlaying = false
                PlayerLog.log("PLAYBACK_ENDED", category: "lifecycle", fields: [:])
            }
            .store(in: &cancellables)

        // Observe buffering state via timeControlStatus
        player?.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                guard let self = self else { return }
                switch status {
                case .waitingToPlayAtSpecifiedRate:
                    let reason = self.player?.reasonForWaitingToPlay
                    self.isBuffering = true
                    PlayerLog.bufferingChange(
                        reason: reason?.rawValue,
                        bufferAhead: self.bufferingDetail.loadedRangeAhead,
                        currentTime: self.currentTime
                    )
                case .playing:
                    if self.isBuffering {
                        // Log buffer recovery
                        PlayerLog.log("PLAYING", category: "lifecycle", fields: [
                            "bufferAhead": String(format: "%.2f", self.bufferingDetail.loadedRangeAhead ?? 0)
                        ])
                    }
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
                PlayerLog.log("ERROR", category: "lifecycle", level: .critical, fields: [
                    "message": error.localizedDescription
                ])
            }
            .store(in: &cancellables)

        // MARK: - AVPlayer Notifications for Glitch Detection

        // AVPlayerItemTimeJumped - Detecta discontinuidades de tiempo (seeks externos)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemTimeJumped(_:)),
            name: .AVPlayerItemTimeJumped,
            object: playerItem
        )

        // AVPlayerItemPlaybackStalled - Detecta stalls explícitos
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemPlaybackStalled(_:)),
            name: .AVPlayerItemPlaybackStalled,
            object: playerItem
        )

        // AVPlayerItemNewErrorLogEntry - Errores detallados
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemNewErrorLogEntry(_:)),
            name: .AVPlayerItemNewErrorLogEntry,
            object: playerItem
        )

        // AVPlayerItemFailedToPlayToEndTime - Playback failure
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEndTime(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem
        )

        // MARK: - Buffer State KVO

        // isPlaybackBufferEmpty - Buffer vacío (binario)
        playerItem?.publisher(for: \.isPlaybackBufferEmpty)
            .removeDuplicates()
            .sink { [weak self] isEmpty in
                guard let self = self, isEmpty else { return }
                // At time 0 the buffer is always empty — player hasn't received data yet.
                // Don't report this as a real starvation event.
                guard self.currentTime > 0 else { return }
                PlayerLog.log("BUFFER_EMPTY_KVO", category: "buffer", level: .critical, fields: [
                    "currentTime": String(format: "%.1f", self.currentTime)
                ])
                self.glitchDetector?.reportGlitch(
                    type: .bufferStarvation,
                    currentTime: self.currentTime,
                    duration: self.duration,
                    playbackRate: self.rate,
                    message: "Playback buffer is empty (KVO)"
                )
            }
            .store(in: &cancellables)

        // isPlaybackLikelyToKeepUp - Buffer suficiente
        playerItem?.publisher(for: \.isPlaybackLikelyToKeepUp)
            .removeDuplicates()
            .sink { [weak self] likelyToKeepUp in
                guard let self = self else { return }
                if !likelyToKeepUp && self.isPlaying {
                    PlayerLog.log("BUFFER_UNLIKELY_KEEPUP", category: "buffer", level: .warning, fields: [
                        "currentTime": String(format: "%.1f", self.currentTime)
                    ])
                }
            }
            .store(in: &cancellables)
    }

    /// Update Now Playing progress (called throttled from time observer)
    private func updateNowPlayingProgress() {
        guard pendingMetadata != nil else { return }
        PlayerMetadataHelper.updatePlaybackProgress(
            currentTime: currentTime,
            playbackRate: isPlaying ? Double(rate) : 0
        )
    }

    // MARK: - Glitch Data Access

    /// Get recent glitch events for debug overlay.
    func recentGlitchEvents(limit: Int = 5) async -> [GlitchEvent] {
        await glitchDetector?.history.recentEvents(limit: limit) ?? []
    }

    /// Get glitch session summary for debug overlay.
    func glitchSessionSummary() async -> GlitchSessionSummary? {
        await glitchDetector?.history.summary()
    }

    // MARK: - Notification Handlers

    @objc private func playerItemTimeJumped(_ notification: Notification) {
        guard let _ = notification.object as? AVPlayerItem,
              let player = player else { return }

        let currentTime = player.currentTime().seconds
        let timeDelta = abs(currentTime - lastSampledTime)

        // AVPlayerItemTimeJumped se dispara para discontinuidades grandes
        // Verificar que sea un seek real (salto grande mientras playing)
        guard isPlaying && timeDelta > 1.0 else { return }

        PlayerLog.log("TIME_JUMP_NOTIFICATION", category: "timing", level: .warning, fields: [
            "from": String(format: "%.1f", lastSampledTime),
            "to": String(format: "%.1f", currentTime),
            "delta": String(format: "%.1f", timeDelta)
        ])

        // Reportar como seek externo si no estamos ya procesando uno
        if !isProcessingExternalSeek {
            reportExternalSeek(from: lastSampledTime, to: currentTime, source: "notification")
        }
    }

    @objc private func playerItemPlaybackStalled(_ notification: Notification) {
        PlayerLog.log("PLAYBACK_STALLED_NOTIFICATION", category: "buffer", level: .warning, fields: [
            "currentTime": String(format: "%.1f", currentTime)
        ])

        glitchDetector?.reportGlitch(
            type: .bufferStarvation,
            currentTime: currentTime,
            duration: duration,
            playbackRate: rate,
            message: "Playback stalled (AVPlayerItemPlaybackStalled)"
        )
    }

    @objc private func playerItemNewErrorLogEntry(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem,
              let errorLog = item.errorLog(),
              let lastEvent = errorLog.events.last else { return }

        PlayerLog.log("ERROR_LOG_ENTRY", category: "error", level: .critical, fields: [
            "errorStatusCode": lastEvent.errorStatusCode,
            "errorDomain": lastEvent.errorDomain,
            "uri": lastEvent.uri ?? "nil"
        ])
    }

    @objc private func playerItemFailedToPlayToEndTime(_ notification: Notification) {
        let errorDesc = notification.userInfo?["AVPlayerItemFailedToPlayToEndTimeErrorKey"] as? String ?? "unknown"
        PlayerLog.log("PLAYBACK_FAILED", category: "lifecycle", level: .critical, fields: [
            "currentTime": String(format: "%.1f", currentTime),
            "duration": String(format: "%.1f", duration),
            "error": errorDesc
        ])

        // Near-EOF recovery: if we're within the last 5% of the content,
        // treat this as a natural end of playback rather than an error.
        // The last HLS segment often has incomplete data that triggers this
        // notification even though playback is effectively done.
        if duration > 0 && currentTime > duration * 0.95 {
            PlayerLog.log("NEAR_END_RECOVERY", category: "lifecycle", fields: [
                "currentTime": String(format: "%.1f", currentTime),
                "duration": String(format: "%.1f", duration),
                "percentComplete": String(format: "%.1f", (currentTime / duration) * 100)
            ])
            isPlaying = false
            return
        }

        glitchDetector?.reportGlitch(
            type: .networkError,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 0,
            message: "Playback failed to reach end: \(errorDesc)"
        )

        // Recovery attempt: reload the current item after a brief delay.
        // Creates a fresh AVPlayer instance which re-fetches the HLS playlist.
        PlayerLog.log("ATTEMPTING_RELOAD", category: "lifecycle", level: .warning, fields: [
            "currentTime": String(format: "%.1f", currentTime)
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reloadCurrentItem()
        }
    }

    // MARK: - External Seek Detection

    private func reportExternalSeek(from: Double, to: Double, source: String, delta: Double? = nil) {
        let timeDelta = delta ?? (to - from)

        PlayerLog.log("EXTERNAL_SEEK_DETECTED", category: "timing", level: .warning, fields: [
            "from": String(format: "%.1f", from),
            "to": String(format: "%.1f", to),
            "delta": String(format: "%.1f", timeDelta),
            "source": source,
            "isPlaying": isPlaying
        ])

        // Marcar que estamos procesando un seek externo
        isProcessingExternalSeek = true
        externalSeekTarget = to
        externalSeekDetectedAt = Date()

        // Reportar al glitch detector
        glitchDetector?.reportGlitch(
            type: .externalSeek,
            currentTime: to,
            duration: duration,
            playbackRate: rate,
            metrics: GlitchMetrics(
                seekTarget: to,
                seekActual: to,
                seekLatencyMs: 0  // No conocemos cuándo empezó exactamente
            ),
            message: "External seek via \(source): jumped \(String(format: "%.1f", abs(timeDelta)))s"
        )

        // Resetear flag después de un tiempo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isProcessingExternalSeek = false
        }
    }
}
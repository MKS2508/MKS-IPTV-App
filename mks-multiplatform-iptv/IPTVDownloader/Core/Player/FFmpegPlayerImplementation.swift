import SwiftUI
import AVKit
import Combine
import TransmuxCore
import IPTVCore

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
    private(set) var transmuxSessionID: String?
    /// Timestamp when load() was called — used by error view to show elapsed time on failure.
    private(set) var loadStartedAt: Date?
    /// Timestamp when error was set — used by error view to show "failed Xs after load".
    private(set) var loadFailedAt: Date?
    @Published private(set) var isTransmuxing: Bool = false

    /// Stored metadata to pass to the inner AVPlayer after transmux starts
    private var pendingMetadata: MetadataResult?

    /// Seek handle for pre-warming the transmux pipeline on seek requests.
    /// Set during load() from the transmux session.
    private var seekHandle: ActiveTransmux?

    /// Debounce work item for transmux pre-warm during scrubbing.
    /// AVPlayer seek fires immediately (UI responsiveness), but the
    /// transmux pipeline seek is delayed by 150ms to avoid flooding
    /// the remux loop with intermediate positions.
    private var seekDebounceWorkItem: DispatchWorkItem?
    private let seekDebounceInterval: TimeInterval = 0.15

    /// The original source URL passed to load(url:).
    private(set) var sourceURL: URL?

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
        self.sourceURL = url

        // Start structured logging session
        PlayerLog.startSession(playerType: "FFmpeg", url: url.absoluteString)
        PlayerLog.log("LOAD", category: "lifecycle", fields: ["url": url.absoluteString])

        isTransmuxing = true
        error = nil
        loadStartedAt = Date()
        loadFailedAt = nil
        pendingMetadata = metadata

        Task { @MainActor in
            do {
                // Step 0: Preflight -- validate stream reachability before transmux
                let preflight = await StreamPreflight.check(url: url)
                PlayerLog.log("PREFLIGHT", category: "network", fields: [
                    "reachable": preflight.isReachable,
                    "httpStatus": preflight.httpStatus ?? -1,
                    "contentLength": preflight.contentLength ?? -1,
                    "summary": preflight.summary
                ])

                guard preflight.isReachable else {
                    self.isTransmuxing = false
                    self.loadFailedAt = Date()
                    self.error = .networkError(
                        NSError(domain: "StreamPreflight", code: preflight.httpStatus ?? -1,
                                userInfo: [NSLocalizedDescriptionKey: "Stream unreachable — \(preflight.summary)"])
                    )
                    PlayerLog.networkError(
                        httpStatus: preflight.httpStatus,
                        error: preflight.error,
                        currentTime: 0
                    )
                    return
                }

                // Step 1: Start progressive transmux (returns after header written)
                let session = try await TransmuxingService.shared.startTransmux(from: url, transcodeAudio: true)
                self.transmuxSessionID = session.sessionID
                self.seekHandle = session.seekHandle
                PlayerLog.log("TRANSMUX_STARTED", category: "transmux", fields: [
                    "sessionID": session.sessionID,
                    "expectedSize": session.expectedSize
                ])

                // Step 2: Start HTTP server serving both m3u8 playlist and mp4 byte ranges.
                // HLSSegmenter (created by TransmuxingService) generates a byte-range HLS
                // playlist as the fMP4 grows. TransmuxServer serves both files so AVPlayer
                // can consume HLS natively — no custom resource loader needed.
                var effectiveSize = session.expectedSize
                if effectiveSize <= 0, let preflightSize = preflight.contentLength, preflightSize > 0 {
                    effectiveSize = preflightSize
                    PlayerLog.log("SIZE_OVERRIDE", category: "transmux", fields: [
                        "from": "preflight",
                        "size": preflightSize
                    ])
                }

                let serverSession = try await TransmuxServer.shared.start(
                    filePath: session.outputPath,
                    playlistPath: session.playlistPath,
                    mediaPlaylistPath: session.mediaPlaylistPath,
                    expectedSize: effectiveSize,
                    segmenter: session.segmenter,
                    initSegmentSize: session.initSegmentSize,
                    seekHandle: session.seekHandle
                )
                PlayerLog.log("SERVER_STARTED", category: "transmux", fields: [
                    "localURL": serverSession.localURL.absoluteString
                ])

                // Step 3: Load the HLS playlist URL — AVPlayer handles HLS natively.
                // The playlist is VOD+ENDLIST from the start, so AVPlayer sees full
                // duration immediately and allows seeking to any position.
                let hlsURL = serverSession.localURL
                PlayerLog.log("HLS_LOAD", category: "transmux", fields: [
                    "url": hlsURL.absoluteString
                ])
                self.isTransmuxing = false
                self.avPlayer = AVPlayerImplementation()
                self.avPlayer?.load(url: hlsURL, metadata: self.pendingMetadata)
                self.setupBindings()

                // Wire GlitchDetector feedback loop: react to playback glitches
                // by signaling the transmux pipeline for corrective action.
                self.avPlayer?.glitchDetector?.onGlitch = { [weak self] event in
                    guard let self, let handle = self.seekHandle else { return }
                    switch event.type {
                    case .bufferStarvation:
                        handle.requestAggressiveFlush()
                    case .seekLatency, .seekFailure:
                        handle.adjustCooldown(seekWasClean: false)
                    default:
                        break
                    }
                }

                // Observe transmux completion for logging/cleanup only.
                // No reloadAsVOD needed — playlist is already VOD from the start.
                NotificationCenter.default.publisher(for: .transmuxDidComplete)
                    .compactMap { $0.object as? String }
                    .filter { [weak self] id in id == self?.transmuxSessionID }
                    .first()
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        PlayerLog.log("TRANSMUX_COMPLETE", category: "transmux", fields: [:])
                    }
                    .store(in: &self.cancellables)

                // Step 4: Auto-play to trigger AVPlayer buffering
                PlayerLog.log("AUTOPLAY", category: "lifecycle", fields: [:])
                self.avPlayer?.play()
                self.isPlaying = true
            } catch {
                self.isTransmuxing = false
                self.loadFailedAt = Date()
                self.error = .unknown(error)
                PlayerLog.log("TRANSMUX_FAILED", category: "transmux", level: .critical, fields: [
                    "error": error.localizedDescription
                ])
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
        PlayerLog.log("STOP", category: "lifecycle", fields: [:])

        seekDebounceWorkItem?.cancel()
        seekDebounceWorkItem = nil
        avPlayer?.stop()
        avPlayer = nil
        seekHandle = nil
        cancellables.removeAll()

        if let sessionID = transmuxSessionID {
            Task {
                await TransmuxingService.shared.cancelTransmux(sessionID: sessionID)
                await TransmuxServer.shared.stop()
                await TransmuxingService.shared.cleanup(sessionID: sessionID)
            }
            transmuxSessionID = nil
        }

        PlayerLog.endSession()
    }

    func seek(to time: Double) {
        // ALWAYS forward to AVPlayer immediately — UI must remain responsive.
        // AVPlayer may serve from the segment cache or already-buffered data.
        avPlayer?.seek(to: time)

        // DEBOUNCE the pre-warm signal to the transmux pipeline.
        // During fast scrubbing, only the LAST position matters. Without debouncing,
        // 10+ seeks in 2 seconds causes the remux loop to spend more time seeking
        // than producing data (each av_seek_frame + timestamp rebase + cooldown).
        seekDebounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let handle = self.seekHandle, let seg = handle.segmenter else { return }
            let targetDuration = seg.targetSegmentDuration
            let targetSegEnd = (floor(time / targetDuration) + 1) * targetDuration
            let buffered = seg.latestBufferedSourceTime()
            if buffered < targetSegEnd - 0.05 {
                handle.requestSeek(to: time)
            }
        }
        seekDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + seekDebounceInterval, execute: workItem)
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

        // Forward playback position to ActiveTransmux for backpressure.
        // Throttled to every 2s to minimize overhead.
        avPlayer.$currentTime
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] time in
                self?.seekHandle?.updatePlaybackPosition(time)
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
        } else if let error = player.error {
            TransmuxErrorView(player: player, error: error)
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

// MARK: - Transmux Error View

/// Verbose failure UI shown when the transmux pipeline aborts before producing
/// a playable AVPlayer. Surfaces every piece of diagnostic information available
/// so the user can debug without needing Xcode attached.
fileprivate struct TransmuxErrorView: View {
    @ObservedObject var player: FFmpegPlayerImplementation
    let error: PlayerError

    @State private var copied = false

    private var errorKind: String {
        switch error {
        case .unsupportedFormat: return "unsupported_format"
        case .networkError: return "network_error"
        case .decodingError: return "decoding_error"
        case .unknown: return "unknown"
        }
    }

    private var underlyingNSError: NSError? {
        switch error {
        case .networkError(let e), .unknown(let e): return e as NSError
        default: return nil
        }
    }

    private var elapsed: String {
        guard let start = player.loadStartedAt else { return "—" }
        let end = player.loadFailedAt ?? Date()
        return String(format: "%.2fs", end.timeIntervalSince(start))
    }

    private var failedAtString: String {
        guard let date = player.loadFailedAt else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private var fullDiagnostics: String {
        var lines: [String] = []
        lines.append("=== Transmux Failure Report ===")
        lines.append("Failed at: \(failedAtString)")
        lines.append("Elapsed:   \(elapsed)")
        lines.append("Kind:      \(errorKind)")
        lines.append("Message:   \(error.errorDescription ?? "—")")
        if let ns = underlyingNSError {
            lines.append("Domain:    \(ns.domain)")
            lines.append("Code:      \(ns.code)")
            if !ns.userInfo.isEmpty {
                lines.append("UserInfo:")
                for (k, v) in ns.userInfo {
                    lines.append("  \(k) = \(v)")
                }
            }
        }
        lines.append("Source URL:    \(player.sourceURL?.absoluteString ?? "—")")
        lines.append("URL length:    \(player.sourceURL?.absoluteString.count ?? 0) chars")
        lines.append("Session ID:    \(player.transmuxSessionID ?? "—")")
        lines.append("Log dir:       \(MKSLogConfig.shared.logDirectory)")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            Color.black

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transmux failed")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("The FFmpeg pipeline could not start playback")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }

                    Divider().background(.white.opacity(0.2))

                    // Error description (primary)
                    field(label: "MESSAGE", value: error.errorDescription ?? "Unknown error", monospaced: false, accent: .red)

                    // Kind / domain / code
                    HStack(alignment: .top, spacing: 12) {
                        field(label: "KIND", value: errorKind)
                        if let ns = underlyingNSError {
                            field(label: "DOMAIN", value: ns.domain)
                            field(label: "CODE", value: String(ns.code))
                        }
                    }

                    // Timing
                    HStack(alignment: .top, spacing: 12) {
                        field(label: "FAILED AT", value: failedAtString)
                        field(label: "ELAPSED", value: elapsed)
                    }

                    // Source URL
                    if let url = player.sourceURL {
                        field(
                            label: "SOURCE URL (\(url.absoluteString.count) chars)",
                            value: url.absoluteString,
                            monospaced: true
                        )
                    }

                    // Session + log path
                    field(label: "SESSION ID", value: player.transmuxSessionID ?? "—", monospaced: true)
                    field(label: "LOG DIRECTORY", value: MKSLogConfig.shared.logDirectory, monospaced: true)

                    // UserInfo dump
                    if let ns = underlyingNSError, !ns.userInfo.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("USER INFO")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(ns.userInfo.keys.map { "\($0)" }.sorted()), id: \.self) { key in
                                    if let value = ns.userInfo[key] {
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("\(key):")
                                                .foregroundStyle(.white.opacity(0.7))
                                            Text("\(value)")
                                                .foregroundStyle(.white)
                                                .textSelection(.enabled)
                                        }
                                        .font(.system(size: 11, design: .monospaced))
                                    }
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
                        }
                    }

                    // Actions
                    HStack(spacing: 10) {
                        if let url = player.sourceURL {
                            Button {
                                player.load(url: url)
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            copyToClipboard(fullDiagnostics)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Label(copied ? "Copied!" : "Copy full report", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        #if os(macOS)
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: MKSLogConfig.shared.logDirectory)
                        } label: {
                            Label("Open logs", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                        #endif

                        Spacer()
                    }
                    .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func field(label: String, value: String, monospaced: Bool = false, accent: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .callout)
                .foregroundStyle(accent)
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

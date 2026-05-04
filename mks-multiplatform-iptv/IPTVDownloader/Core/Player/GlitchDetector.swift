import Foundation
import AVFoundation
import IPTVCore

// MARK: - Glitch History Actor

/// Thread-safe storage for glitch history with statistics.
actor GlitchHistory {
    private var events: [GlitchEvent] = []
    private let maxSize: Int

    // Running statistics
    private var countsByType: [PlaybackGlitchType: Int] = [:]
    private var firstGlitchTime: Date?
    private var lastGlitchTime: Date?

    init(maxSize: Int = 100) {
        self.maxSize = maxSize
    }

    /// Add a new glitch event.
    func add(_ event: GlitchEvent) {
        events.append(event)
        if events.count > maxSize {
            events.removeFirst()
        }
        countsByType[event.type, default: 0] += 1
        if firstGlitchTime == nil { firstGlitchTime = event.timestamp }
        lastGlitchTime = event.timestamp

        // Log the glitch
        PlayerLog.glitch(event)
    }

    /// Get recent events.
    func recentEvents(limit: Int = 20) -> [GlitchEvent] {
        Array(events.suffix(limit))
    }

    /// Get all events.
    func allEvents() -> [GlitchEvent] {
        events
    }

    /// Get summary statistics.
    func summary() -> GlitchSessionSummary {
        let critical = events.filter { $0.severity == .critical }.count
        let warning = events.filter { $0.severity == .warning }.count
        let info = events.filter { $0.severity == .info }.count

        return GlitchSessionSummary(
            totalEvents: events.count,
            countsByType: countsByType,
            firstGlitchTime: firstGlitchTime,
            lastGlitchTime: lastGlitchTime,
            criticalCount: critical,
            warningCount: warning,
            infoCount: info
        )
    }

    /// Clear all history.
    func clear() {
        events.removeAll()
        countsByType.removeAll()
        firstGlitchTime = nil
        lastGlitchTime = nil
    }

    /// Get count for a specific glitch type.
    func count(for type: PlaybackGlitchType) -> Int {
        countsByType[type] ?? 0
    }

    /// Get total count.
    func totalCount() -> Int {
        events.count
    }
}

// MARK: - Glitch Detector

/// Detects playback glitches by monitoring player state.
/// Designed to be called periodically from a time observer.
///
/// ## Feedback Loop
/// Set `onGlitch` to receive events and trigger corrective actions
/// in the transmux pipeline (aggressive flushing, cooldown adjustment).
final class GlitchDetector {

    // MARK: - Properties

    let config: GlitchDetectionConfig
    let history: GlitchHistory

    /// Callback invoked on every detected glitch event.
    /// Used by FFmpegPlayerImplementation to trigger corrective actions
    /// in the transmux pipeline (e.g., aggressive flush on buffer starvation).
    var onGlitch: ((GlitchEvent) -> Void)?

    private let playerType: String
    private let sessionID: String?

    // Sampling state
    private var lastSampleTime: Date?
    private var lastPlayheadPosition: Double = 0
    private var freezeStartTime: Date?

    // Frame drop tracking
    private var lastDroppedFrames: Int = 0
    private var dropWindowStart: Date?
    private var dropsInWindow: Int = 0

    // Buffer tracking
    private var lastBufferAhead: Double = 0
    private var underrunStartTime: Date?

    // Seek tracking
    private var seekStartTime: Date?
    private var seekTarget: Double?

    // A/V sync tracking
    private var lastVideoPTS: Double = 0
    private var lastAudioPTS: Double = 0

    // MARK: - Initialization

    init(
        config: GlitchDetectionConfig = .default,
        playerType: String,
        sessionID: String? = nil
    ) {
        self.config = config
        self.playerType = playerType
        self.sessionID = sessionID
        self.history = GlitchHistory(maxSize: config.historySize)
    }

    // MARK: - Sample Method

    /// Sample the player state for glitch detection.
    /// Call this periodically (e.g., every 100ms from time observer).
    func sample(
        currentTime: Double,
        duration: Double,
        playbackRate: Float,
        isPlaying: Bool,
        bufferAhead: Double?,
        droppedFrames: Int? = nil
    ) {
        let now = Date()

        // 1. Video freeze detection
        detectVideoFreeze(
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            isPlaying: isPlaying,
            now: now
        )

        // 2. Frame drop detection
        if let droppedFrames = droppedFrames {
            detectFrameDrops(
                currentDropped: droppedFrames,
                currentTime: currentTime,
                now: now
            )
        }

        // 3. Buffer underrun detection
        if let bufferAhead = bufferAhead {
            detectBufferUnderrun(
                bufferAhead: bufferAhead,
                currentTime: currentTime,
                playbackRate: playbackRate,
                isPlaying: isPlaying,
                now: now
            )
        }

        lastSampleTime = now
        lastPlayheadPosition = currentTime
    }

    // MARK: - Detection Algorithms

    private func detectVideoFreeze(
        currentTime: Double,
        duration: Double,
        playbackRate: Float,
        isPlaying: Bool,
        now: Date
    ) {
        // Only check if playing
        guard isPlaying && playbackRate > 0 else {
            freezeStartTime = nil
            return
        }

        // Check if time is advancing
        let timeAdvanced = currentTime > lastPlayheadPosition

        if !timeAdvanced && lastSampleTime != nil {
            // Time not advancing while playing
            if freezeStartTime == nil {
                freezeStartTime = lastSampleTime
            }

            if let freezeStart = freezeStartTime {
                let freezeDuration = now.timeIntervalSince(freezeStart)

                if freezeDuration >= config.freezeThreshold {
                    // Emit VIDEO_FREEZE event
                    let event = GlitchEvent(
                        type: .videoFreeze,
                        currentTime: currentTime,
                        duration: duration,
                        playbackRate: playbackRate,
                        metrics: GlitchMetrics(freezeDuration: freezeDuration),
                        playerType: playerType,
                        sessionID: sessionID,
                        message: "Video frozen for \(String(format: "%.2f", freezeDuration))s"
                    )
                    record(event)
                }
            }
        } else {
            // Time advancing, clear freeze state
            freezeStartTime = nil
        }
    }

    private func detectFrameDrops(
        currentDropped: Int,
        currentTime: Double,
        now: Date
    ) {
        let newDrops = currentDropped - lastDroppedFrames

        if newDrops > 0 {
            if dropWindowStart == nil {
                dropWindowStart = now
            }

            dropsInWindow += newDrops

            // Check if window exceeded
            if let windowStart = dropWindowStart,
               now.timeIntervalSince(windowStart) <= config.frameDropWindow {
                if dropsInWindow >= config.frameDropThreshold {
                    let event = GlitchEvent(
                        type: .videoStutter,
                        currentTime: currentTime,
                        duration: 0,
                        playbackRate: 1,
                        metrics: GlitchMetrics(framesDropped: dropsInWindow),
                        playerType: playerType,
                        sessionID: sessionID,
                        message: "\(dropsInWindow) frames dropped in \(String(format: "%.1f", config.frameDropWindow))s window"
                    )
                    record(event)
                    dropsInWindow = 0
                    dropWindowStart = nil
                }
            } else {
                // Window expired, reset
                dropsInWindow = newDrops
                dropWindowStart = now
            }
        }

        lastDroppedFrames = currentDropped
    }

    private func detectBufferUnderrun(
        bufferAhead: Double,
        currentTime: Double,
        playbackRate: Float,
        isPlaying: Bool,
        now: Date
    ) {
        guard isPlaying && playbackRate > 0 else {
            underrunStartTime = nil
            lastBufferAhead = bufferAhead
            return
        }

        // Check for starvation (buffer = 0)
        if bufferAhead < config.bufferStarvationThreshold {
            let event = GlitchEvent(
                type: .bufferStarvation,
                currentTime: currentTime,
                duration: 0,
                playbackRate: playbackRate,
                metrics: GlitchMetrics(bufferAhead: bufferAhead, bufferEmpty: bufferAhead == 0),
                playerType: playerType,
                sessionID: sessionID,
                message: "Buffer empty (\(String(format: "%.2f", bufferAhead))s ahead)"
            )
            record(event)
        }
        // Check for underrun (buffer low)
        else if bufferAhead < config.bufferUnderrunThreshold {
            // Only log if we haven't recently
            if underrunStartTime == nil {
                underrunStartTime = now

                let event = GlitchEvent(
                    type: .bufferUnderrun,
                    currentTime: currentTime,
                    duration: 0,
                    playbackRate: playbackRate,
                    metrics: GlitchMetrics(bufferAhead: bufferAhead),
                    playerType: playerType,
                    sessionID: sessionID,
                    message: "Buffer low (\(String(format: "%.2f", bufferAhead))s ahead)"
                )
                record(event)
            }
        } else {
            underrunStartTime = nil
        }

        lastBufferAhead = bufferAhead
    }

    // MARK: - Seek Tracking

    /// Called when a seek starts.
    func seekStarted(target: Double, currentPosition: Double) {
        seekStartTime = Date()
        seekTarget = target
        PlayerLog.seekStart(target: target, currentPosition: currentPosition)
    }

    /// Called when a seek completes.
    /// Returns the glitch event if the seek was slow/failed.
    @discardableResult
    func seekCompleted(actualPosition: Double, duration: Double) -> GlitchEvent? {
        defer {
            seekStartTime = nil
            seekTarget = nil
        }

        guard let start = seekStartTime, let target = seekTarget else { return nil }

        let latencyMs = Date().timeIntervalSince(start) * 1000
        let accuracy = abs(actualPosition - target)

        // Log the completion
        PlayerLog.seekComplete(
            target: target,
            actual: actualPosition,
            latencyMs: latencyMs,
            accuracy: accuracy
        )

        // Check for glitch
        let glitchType: PlaybackGlitchType?
        if latencyMs > config.seekLatencyCriticalMs {
            glitchType = .seekFailure
        } else if latencyMs > config.seekLatencyWarnMs {
            glitchType = .seekLatency
        } else {
            glitchType = nil
        }

        if let type = glitchType {
            let event = GlitchEvent(
                type: type,
                currentTime: actualPosition,
                duration: duration,
                playbackRate: 1,
                metrics: GlitchMetrics(
                    seekTarget: target,
                    seekActual: actualPosition,
                    seekLatencyMs: latencyMs
                ),
                playerType: playerType,
                sessionID: sessionID,
                message: "Seek to \(String(format: "%.1f", target))s took \(String(format: "%.0f", latencyMs))ms"
            )
            record(event)
            return event
        }

        return nil
    }

    // MARK: - Event Recording

    /// Record a glitch event: store in history and fire the feedback callback.
    private func record(_ event: GlitchEvent) {
        onGlitch?(event)
        Task {
            await history.add(event)
        }
    }

    // MARK: - Manual Glitch Reporting

    /// Manually report a glitch (e.g., from server-side detection).
    func reportGlitch(
        type: PlaybackGlitchType,
        currentTime: Double,
        duration: Double,
        playbackRate: Float,
        metrics: GlitchMetrics = GlitchMetrics(),
        message: String? = nil
    ) {
        let event = GlitchEvent(
            type: type,
            currentTime: currentTime,
            duration: duration,
            playbackRate: playbackRate,
            metrics: metrics,
            playerType: playerType,
            sessionID: sessionID,
            message: message
        )
        record(event)
    }

    /// Report a segment gap.
    func reportSegmentGap(expected: Int, actual: Int, currentTime: Double, duration: Double) {
        let gapSize = abs(actual - expected)
        PlayerLog.segmentGap(expected: expected, actual: actual, gapSize: gapSize, currentTime: currentTime)

        let event = GlitchEvent(
            type: .segmentGap,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            metrics: GlitchMetrics(segmentIndex: actual),
            playerType: playerType,
            sessionID: sessionID,
            message: "Segment gap: expected \(expected), got \(actual)"
        )
        record(event)
    }

    /// Report a network error.
    func reportNetworkError(httpStatus: Int?, error: String?, currentTime: Double, duration: Double) {
        PlayerLog.networkError(httpStatus: httpStatus, error: error, currentTime: currentTime)

        let event = GlitchEvent(
            type: .networkError,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 0,
            metrics: GlitchMetrics(httpStatus: httpStatus),
            playerType: playerType,
            sessionID: sessionID,
            message: error ?? "Network error (HTTP \(httpStatus ?? 0))"
        )
        record(event)
    }

    // MARK: - Reset

    /// Reset all detection state.
    func reset() {
        lastSampleTime = nil
        lastPlayheadPosition = 0
        freezeStartTime = nil
        lastDroppedFrames = 0
        dropWindowStart = nil
        dropsInWindow = 0
        lastBufferAhead = 0
        underrunStartTime = nil
        seekStartTime = nil
        seekTarget = nil

        Task {
            await history.clear()
        }
    }
}

// MARK: - Convenience Extensions

extension GlitchDetector {
    /// Create a detector for FFmpeg player.
    static func forFFmpeg(sessionID: String? = nil) -> GlitchDetector {
        GlitchDetector(config: .default, playerType: "FFmpeg", sessionID: sessionID)
    }

    /// Create a detector for AVPlayer.
    static func forAVPlayer(sessionID: String? = nil) -> GlitchDetector {
        GlitchDetector(config: .default, playerType: "AVPlayer", sessionID: sessionID)
    }

    /// Create a detector for VLC player.
    static func forVLC(sessionID: String? = nil) -> GlitchDetector {
        GlitchDetector(config: .relaxed, playerType: "VLC", sessionID: sessionID)
    }
}

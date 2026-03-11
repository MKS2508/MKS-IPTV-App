// AVSyncController.swift — A/V Sync Controller for Tier 2/3 Transcode
//
// Adopted from KSPlayer's 3-tier escalation system.
// Provides drift detection and correction for video transcoding scenarios
// where software decode + hardware encode pipelines can introduce timing drift.
//
// Architecture (AD-12):
//   - Tier 0 (passthrough): AVPlayer handles sync natively
//   - Tier 1 (audio transcode): Audio-only, no sync needed
//   - Tier 2/3 (video transcode): Requires explicit sync management
//
// Thresholds (from KSPlayer analysis):
//   - Normal: drift < 4 frames (~133ms at 30fps)
//   - Light correction: drift 4-8 frames
//   - Heavy correction: drift 8 frames to 8 seconds
//   - Catastrophic: drift > 8 seconds (seek required)

import Foundation

// MARK: - Sync Action

/// Actions to correct A/V drift during transcoding.
/// Based on KSPlayer's 3-tier escalation system.
public enum SyncAction: Sendable, Equatable {
    /// Normal operation - drift within acceptable threshold.
    /// Continue presenting frames normally.
    case present

    /// Light correction - skip 1 frame to catch up.
    /// Used when video is slightly ahead of audio.
    case dropFrame

    /// Heavy correction - skip to next keyframe.
    /// Used when video is significantly ahead.
    case dropToKeyframe

    /// Catastrophic drift - seek to audio position.
    /// Used when drift exceeds 8 seconds (likely stream discontinuity).
    case seekToAudio
}

// MARK: - Sync Statistics

/// Statistics for A/V sync monitoring.
public struct SyncStats: Sendable, Equatable {
    /// Number of frames presented normally.
    public var framesPresented: Int = 0

    /// Number of frames dropped for sync correction.
    public var framesDropped: Int = 0

    /// Number of keyframe skips performed.
    public var keyframeSkips: Int = 0

    /// Number of seek corrections performed.
    public var seekCorrections: Int = 0

    /// Maximum drift observed in seconds.
    public var maxDriftSeconds: Double = 0.0

    /// Current drift in seconds (positive = video ahead).
    public var currentDriftSeconds: Double = 0.0

    public init() {}
}

// MARK: - Protocol

/// A/V sync controller for Tier 2/3 transcode operations.
/// Analyzes PTS drift between video and audio streams and recommends corrective actions.
public protocol AVSyncController: AnyObject, Sendable {
    /// Analyze the current A/V sync state and recommend an action.
    /// - Parameters:
    ///   - videoPTS: Current video presentation timestamp (in MPEG-TS timebase: 1/90000).
    ///   - audioPTS: Current audio presentation timestamp (in MPEG-TS timebase: 1/90000).
    ///   - fps: Video frame rate for frame duration calculation.
    /// - Returns: The recommended sync action.
    func analyzeSync(videoPTS: Int64, audioPTS: Int64, fps: Double) -> SyncAction

    /// Get current sync statistics.
    var stats: SyncStats { get }

    /// Reset statistics and internal state.
    func reset()
}

// MARK: - Transcode Implementation

/// A/V sync controller for video transcoding scenarios.
/// Implements KSPlayer's 3-tier escalation strategy with macOS-optimized thresholds.
public final class TranscodeAVSyncController: AVSyncController, Sendable {
    // MARK: - Constants

    /// MPEG-TS timebase denominator (90kHz).
    private static let mpegtsTimebase: Double = 90000.0

    /// Frame multiplier thresholds
    private let normalFrameThreshold: Double
    private let lightCorrectionThreshold: Double
    private let heavyCorrectionThreshold: Double

    // MARK: - State

    private var _stats: SyncStats = SyncStats()
    public var stats: SyncStats { _stats }

    /// Last video PTS for discontinuity detection.
    private var lastVideoPTS: Int64 = 0

    /// Last audio PTS for discontinuity detection.
    private var lastAudioPTS: Int64 = 0

    /// Whether we've seen valid PTS values yet.
    private var hasValidPTS: Bool = false

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create a new sync controller with custom thresholds.
    /// - Parameters:
    ///   - normalFrameThreshold: Maximum frames of drift for normal operation (default: 4).
    ///   - lightCorrectionThreshold: Maximum frames for light correction (default: 8).
    ///   - heavyCorrectionThreshold: Seconds of drift before seek (default: 8.0).
    public init(
        normalFrameThreshold: Double = 4.0,
        lightCorrectionThreshold: Double = 8.0,
        heavyCorrectionThreshold: Double = 8.0
    ) {
        self.normalFrameThreshold = normalFrameThreshold
        self.lightCorrectionThreshold = lightCorrectionThreshold
        self.heavyCorrectionThreshold = heavyCorrectionThreshold
    }

    // MARK: - AVSyncController

    public func analyzeSync(videoPTS: Int64, audioPTS: Int64, fps: Double) -> SyncAction {
        lock.lock()
        defer { lock.unlock() }

        // Guard against invalid PTS
        guard videoPTS > 0, audioPTS > 0, fps > 0 else {
            return .present
        }

        // Calculate drift in PTS units (positive = video ahead)
        let driftPTS = videoPTS - audioPTS

        // Convert to seconds for threshold comparison
        let driftSeconds = Double(driftPTS) / Self.mpegtsTimebase

        // Update statistics
        _stats.currentDriftSeconds = driftSeconds
        if abs(driftSeconds) > abs(_stats.maxDriftSeconds) {
            _stats.maxDriftSeconds = driftSeconds
        }

        // Detect discontinuity (large PTS jump)
        if hasValidPTS {
            let videoJump = abs(videoPTS - lastVideoPTS)
            let audioJump = abs(audioPTS - lastAudioPTS)
            let maxExpectedJump = Int64(10.0 * Self.mpegtsTimebase) // 10 seconds

            if videoJump > maxExpectedJump || audioJump > maxExpectedJump {
                // Discontinuity detected - reset and continue
                lastVideoPTS = videoPTS
                lastAudioPTS = audioPTS
                return .present
            }
        }

        lastVideoPTS = videoPTS
        lastAudioPTS = audioPTS
        hasValidPTS = true

        // Calculate frame duration in seconds
        let frameDuration = 1.0 / fps
        let absDrift = abs(driftSeconds)

        // 3-tier escalation (KSPlayer pattern)
        // Tier 1: Normal - within ±4 frames
        if absDrift < frameDuration * normalFrameThreshold {
            _stats.framesPresented += 1
            return .present
        }

        // Tier 2: Light correction - 4-8 frames
        if absDrift < frameDuration * lightCorrectionThreshold {
            if driftSeconds > 0 { // Video ahead
                _stats.framesDropped += 1
                return .dropFrame
            }
            // Video behind - let it catch up naturally
            _stats.framesPresented += 1
            return .present
        }

        // Tier 3: Heavy correction - 8 frames to 8 seconds
        if absDrift < heavyCorrectionThreshold {
            if driftSeconds > 0 { // Video ahead
                _stats.keyframeSkips += 1
                return .dropToKeyframe
            }
            // Video significantly behind - still present
            _stats.framesPresented += 1
            return .present
        }

        // Tier 4: Catastrophic - seek to audio position
        _stats.seekCorrections += 1
        return .seekToAudio
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        _stats = SyncStats()
        lastVideoPTS = 0
        lastAudioPTS = 0
        hasValidPTS = false
    }
}

// MARK: - Passthrough Implementation

/// No-op sync controller for Tier 0/1 where AVPlayer handles sync natively.
/// Always returns .present without any analysis.
public final class PassthroughAVSyncController: AVSyncController, Sendable {
    public var stats: SyncStats { SyncStats() }

    public init() {}

    public func analyzeSync(videoPTS: Int64, audioPTS: Int64, fps: Double) -> SyncAction {
        .present
    }

    public func reset() {}
}

// MARK: - Factory

/// Factory for creating appropriate sync controller based on transcode tier.
public enum AVSyncControllerFactory {
    /// Create a sync controller appropriate for the given tier.
    /// - Parameter tier: The transcode tier.
    /// - Returns: A sync controller instance.
    public static func create(for tier: TranscodeTier) -> AVSyncController {
        switch tier {
        case .passthrough, .audioOnly:
            // AVPlayer handles sync natively
            return PassthroughAVSyncController()
        case .videoTranscode, .fullTranscode:
            // Explicit sync management required
            return TranscodeAVSyncController()
        }
    }
}

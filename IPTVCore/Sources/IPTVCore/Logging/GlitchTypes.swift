import Foundation

// MARK: - Glitch Severity

/// Severity levels for glitch events, designed for log filtering.
public enum GlitchSeverity: String, Codable, CaseIterable {
    case info = "INF"
    case warning = "WRN"
    case critical = "ERR"

    public var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Glitch Type

/// Categories of playback glitches that can be detected.
/// Raw values are designed for structured logging and grep-friendly output.
public enum PlaybackGlitchType: String, Codable, CaseIterable {
    // Video anomalies
    case videoFreeze = "VIDEO_FREEZE"           // Video frames not advancing
    case videoStutter = "VIDEO_STUTTER"         // Intermittent frame drops
    case frameDrop = "FRAME_DROP"               // Single frame dropped

    // Audio anomalies
    case audioStutter = "AUDIO_STUTTER"         // Audio discontinuity
    case audioMute = "AUDIO_MUTE"               // Unexpected silence
    case audioGlitch = "AUDIO_GLITCH"           // Click/pop/distortion

    // Timing anomalies
    case avDesync = "AV_DESYNC"                 // A/V timestamp drift
    case seekLatency = "SEEK_LATENCY"           // Seek took too long
    case seekFailure = "SEEK_FAILURE"           // Seek did not reach target
    case externalSeek = "EXTERNAL_SEEK"         // Seek from AVPlayerViewController scrubbing (not programmatic)

    // Buffer anomalies
    case bufferUnderrun = "BUFFER_UNDERRUN"     // Playback stalled for buffer
    case bufferStarvation = "BUFFER_STARVATION" // Buffer reached zero
    case segmentGap = "SEGMENT_GAP"             // Missing segment in sequence

    // Network anomalies
    case networkTimeout = "NETWORK_TIMEOUT"     // Segment request timed out
    case networkError = "NETWORK_ERROR"         // HTTP error response

    // MARK: - Computed Properties

    /// Severity level for this glitch type.
    public var severity: GlitchSeverity {
        switch self {
        case .videoFreeze, .audioMute, .seekFailure, .bufferStarvation:
            return .critical
        case .avDesync, .seekLatency, .bufferUnderrun, .segmentGap, .networkTimeout, .networkError, .externalSeek:
            return .warning
        case .videoStutter, .frameDrop, .audioStutter, .audioGlitch:
            return .info
        }
    }

    /// Category for grouping in logs and UI.
    public var category: String {
        switch self {
        case .videoFreeze, .videoStutter, .frameDrop: return "video"
        case .audioStutter, .audioMute, .audioGlitch: return "audio"
        case .avDesync, .seekLatency, .seekFailure, .externalSeek: return "timing"
        case .bufferUnderrun, .bufferStarvation, .segmentGap: return "buffer"
        case .networkTimeout, .networkError: return "network"
        }
    }

    /// Human-readable description.
    public var description: String {
        switch self {
        case .videoFreeze: return "Video frozen"
        case .videoStutter: return "Video stuttering"
        case .frameDrop: return "Frame dropped"
        case .audioStutter: return "Audio stuttering"
        case .audioMute: return "Audio muted unexpectedly"
        case .audioGlitch: return "Audio glitch"
        case .avDesync: return "A/V out of sync"
        case .seekLatency: return "Seek slow"
        case .seekFailure: return "Seek failed"
        case .externalSeek: return "External seek detected"
        case .bufferUnderrun: return "Buffer underrun"
        case .bufferStarvation: return "Buffer empty"
        case .segmentGap: return "Segment gap"
        case .networkTimeout: return "Network timeout"
        case .networkError: return "Network error"
        }
    }
}

// MARK: - Glitch Metrics

/// Glitch-type-specific metrics for detailed logging and analysis.
/// Uses optional fields to accommodate different glitch types.
public struct GlitchMetrics: Codable {
    // Video freeze/stutter
    public var freezeDuration: Double?               // How long frozen (seconds)
    public var framesDropped: Int?                    // Number of dropped frames

    // Audio issues
    public var audioGap: Double?                      // Audio silence duration (seconds)

    // A/V sync
    public var avDriftMs: Double?                     // A/V timestamp difference (milliseconds)
    public var videoPTS: Double?                      // Video presentation timestamp
    public var audioPTS: Double?                      // Audio presentation timestamp

    // Seek
    public var seekTarget: Double?                    // Requested seek position
    public var seekActual: Double?                    // Actual position after seek
    public var seekLatencyMs: Double?                 // Time to complete seek (milliseconds)

    // Buffer
    public var bufferAhead: Double?                   // Seconds buffered ahead
    public var bufferEmpty: Bool?                     // Buffer reached zero
    public var segmentIndex: Int?                     // Affected segment number

    // Network
    public var httpStatus: Int?                       // HTTP response code
    public var bytesTransferred: Int64?               // Bytes before failure

    public init(
        freezeDuration: Double? = nil,
        framesDropped: Int? = nil,
        audioGap: Double? = nil,
        avDriftMs: Double? = nil,
        videoPTS: Double? = nil,
        audioPTS: Double? = nil,
        seekTarget: Double? = nil,
        seekActual: Double? = nil,
        seekLatencyMs: Double? = nil,
        bufferAhead: Double? = nil,
        bufferEmpty: Bool? = nil,
        segmentIndex: Int? = nil,
        httpStatus: Int? = nil,
        bytesTransferred: Int64? = nil
    ) {
        self.freezeDuration = freezeDuration
        self.framesDropped = framesDropped
        self.audioGap = audioGap
        self.avDriftMs = avDriftMs
        self.videoPTS = videoPTS
        self.audioPTS = audioPTS
        self.seekTarget = seekTarget
        self.seekActual = seekActual
        self.seekLatencyMs = seekLatencyMs
        self.bufferAhead = bufferAhead
        self.bufferEmpty = bufferEmpty
        self.segmentIndex = segmentIndex
        self.httpStatus = httpStatus
        self.bytesTransferred = bytesTransferred
    }

    /// Grep-friendly string representation for logs.
    public var grepString: String {
        var parts: [String] = []
        if let v = freezeDuration { parts.append("freeze=\(String(format: "%.2f", v))s") }
        if let v = framesDropped { parts.append("drops=\(v)") }
        if let v = audioGap { parts.append("audioGap=\(String(format: "%.2f", v))s") }
        if let v = avDriftMs { parts.append("drift=\(String(format: "%.0f", v))ms") }
        if let v = seekTarget { parts.append("target=\(String(format: "%.1f", v))s") }
        if let v = seekActual { parts.append("actual=\(String(format: "%.1f", v))s") }
        if let v = seekLatencyMs { parts.append("latency=\(String(format: "%.0f", v))ms") }
        if let v = bufferAhead { parts.append("buf=\(String(format: "%.2f", v))s") }
        if let v = segmentIndex { parts.append("seg=\(v)") }
        if let v = httpStatus { parts.append("http=\(v)") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Glitch Event

/// A single detected glitch event with full context.
/// Designed for JSON serialization and log aggregation.
public struct GlitchEvent: Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let type: PlaybackGlitchType
    public let severity: GlitchSeverity

    // Playback context
    public let currentTime: Double           // Playhead position (seconds)
    public let duration: Double              // Total duration (seconds)
    public let playbackRate: Float           // Current rate (0=paused, 1=normal)

    // Glitch-specific metrics
    public let metrics: GlitchMetrics

    // Source identification
    public let playerType: String            // "AVPlayer", "FFmpeg", "VLC"
    public let sessionID: String?            // Correlate with TransmuxLog session

    // Additional context
    public let message: String               // Human-readable description

    /// Create a new glitch event.
    public init(
        type: PlaybackGlitchType,
        currentTime: Double,
        duration: Double,
        playbackRate: Float,
        metrics: GlitchMetrics = GlitchMetrics(),
        playerType: String,
        sessionID: String? = nil,
        message: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.severity = type.severity
        self.currentTime = currentTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.metrics = metrics
        self.playerType = playerType
        self.sessionID = sessionID
        self.message = message ?? type.description
    }
}

// MARK: - Glitch Detection Configuration

/// Thresholds and settings for glitch detection.
/// Tunable for different sensitivity levels.
public struct GlitchDetectionConfig: Codable {
    // Video freeze detection
    public var freezeThreshold: TimeInterval = 0.5      // Seconds without frame change
    public var freezeMinDuration: TimeInterval = 0.3    // Report if frozen this long

    // Frame drop detection
    public var frameDropWindow: TimeInterval = 1.0      // Window for counting drops
    public var frameDropThreshold: Int = 3              // Drops in window to trigger

    // A/V sync detection
    public var avDriftThresholdMs: Double = 100         // Milliseconds drift to warn
    public var avDriftCriticalMs: Double = 500          // Milliseconds for critical

    // Buffer detection
    public var bufferUnderrunThreshold: Double = 0.5    // Seconds ahead = underrun
    public var bufferStarvationThreshold: Double = 0.1  // Seconds ahead = starvation

    // Seek latency detection
    public var seekLatencyWarnMs: Double = 2000         // Warn if seek > 2 seconds
    public var seekLatencyCriticalMs: Double = 5000     // Critical if > 5 seconds

    // Segment gap detection
    public var segmentTimeoutMs: Double = 10000         // Segment request timeout

    // Detection sampling
    public var sampleInterval: TimeInterval = 0.1       // How often to check (100ms)
    public var historySize: Int = 100                   // Keep last N events

    public init(
        freezeThreshold: TimeInterval = 0.5,
        freezeMinDuration: TimeInterval = 0.3,
        frameDropWindow: TimeInterval = 1.0,
        frameDropThreshold: Int = 3,
        avDriftThresholdMs: Double = 100,
        avDriftCriticalMs: Double = 500,
        bufferUnderrunThreshold: Double = 0.5,
        bufferStarvationThreshold: Double = 0.1,
        seekLatencyWarnMs: Double = 2000,
        seekLatencyCriticalMs: Double = 5000,
        segmentTimeoutMs: Double = 10000,
        sampleInterval: TimeInterval = 0.1,
        historySize: Int = 100
    ) {
        self.freezeThreshold = freezeThreshold
        self.freezeMinDuration = freezeMinDuration
        self.frameDropWindow = frameDropWindow
        self.frameDropThreshold = frameDropThreshold
        self.avDriftThresholdMs = avDriftThresholdMs
        self.avDriftCriticalMs = avDriftCriticalMs
        self.bufferUnderrunThreshold = bufferUnderrunThreshold
        self.bufferStarvationThreshold = bufferStarvationThreshold
        self.seekLatencyWarnMs = seekLatencyWarnMs
        self.seekLatencyCriticalMs = seekLatencyCriticalMs
        self.segmentTimeoutMs = segmentTimeoutMs
        self.sampleInterval = sampleInterval
        self.historySize = historySize
    }

    /// Default configuration with balanced sensitivity.
    public static let `default` = GlitchDetectionConfig()

    /// Sensitive configuration for detailed debugging.
    public static let sensitive = GlitchDetectionConfig(
        freezeThreshold: 0.3,
        freezeMinDuration: 0.2,
        frameDropThreshold: 1,
        avDriftThresholdMs: 50,
        bufferUnderrunThreshold: 1.0,
        seekLatencyWarnMs: 1000
    )

    /// Relaxed configuration for production.
    public static let relaxed = GlitchDetectionConfig(
        freezeThreshold: 1.0,
        freezeMinDuration: 0.5,
        frameDropThreshold: 5,
        avDriftThresholdMs: 200,
        bufferUnderrunThreshold: 0.3,
        seekLatencyWarnMs: 3000
    )
}

// MARK: - Glitch Session Summary

/// Summary statistics for a playback session.
public struct GlitchSessionSummary: Codable {
    public let totalEvents: Int
    public let countsByType: [PlaybackGlitchType: Int]
    public let firstGlitchTime: Date?
    public let lastGlitchTime: Date?
    public let criticalCount: Int
    public let warningCount: Int
    public let infoCount: Int

    public init(
        totalEvents: Int,
        countsByType: [PlaybackGlitchType: Int],
        firstGlitchTime: Date?,
        lastGlitchTime: Date?,
        criticalCount: Int,
        warningCount: Int,
        infoCount: Int
    ) {
        self.totalEvents = totalEvents
        self.countsByType = countsByType
        self.firstGlitchTime = firstGlitchTime
        self.lastGlitchTime = lastGlitchTime
        self.criticalCount = criticalCount
        self.warningCount = warningCount
        self.infoCount = infoCount
    }

    /// Duration of the session (from first to last glitch).
    public var sessionDuration: TimeInterval? {
        guard let first = firstGlitchTime, let last = lastGlitchTime else { return nil }
        return last.timeIntervalSince(first)
    }

    /// Glitch rate (events per minute).
    public var glitchesPerMinute: Double? {
        guard let duration = sessionDuration, duration > 0 else { return nil }
        return Double(totalEvents) / (duration / 60)
    }
}

import Foundation

// MARK: - PlayerLog (Backward Compatibility Alias)

/// **DEPRECATED** — Use `MKSLog` directly for all new code.
///
/// This file exists only for backward compatibility. All functionality
/// has been unified into `MKSLog` which forwards to os.Logger + File + WebSocket.
///
/// Mapping:
/// - `PlayerLog.log(...)` → `MKSLog.log(...)`
/// - `PlayerLog.sessionID` → `MKSLog.sessionID`
/// - `PlayerLog.filePath` → `MKSLog.filePath`
/// - `PlayerLog.seekStart(...)` → `MKSLog.seekStart(...)`
/// - etc.
public enum PlayerLog {

    // MARK: - Forwarded Properties

    public static var sessionID: String {
        get { MKSLog.sessionID }
        set { MKSLog.sessionID = newValue }
    }

    public static var filePath: String { MKSLog.filePath }

    // MARK: - Forwarded Methods

    public static func startSession(playerType: String, url: String?) {
        MKSLog.startSession(playerType: playerType, url: url)
    }

    public static func endSession() {
        MKSLog.endSession()
    }

    public static func log(
        _ action: String,
        category: String,
        level: GlitchSeverity = .info,
        fields: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        MKSLog.log(action, category: category, level: level, fields: fields)
    }

    public static func glitch(_ event: GlitchEvent) { MKSLog.glitch(event) }
    public static func seekStart(target: Double, currentPosition: Double) { MKSLog.seekStart(target: target, currentPosition: currentPosition) }
    public static func seekComplete(target: Double, actual: Double, latencyMs: Double, accuracy: Double) { MKSLog.seekComplete(target: target, actual: actual, latencyMs: latencyMs, accuracy: accuracy) }
    public static func segmentGap(expected: Int, actual: Int, gapSize: Int, currentTime: Double) { MKSLog.segmentGap(expected: expected, actual: actual, gapSize: gapSize, currentTime: currentTime) }
    public static func bufferingChange(reason: String?, bufferAhead: Double?, currentTime: Double) { MKSLog.bufferingChange(reason: reason, bufferAhead: bufferAhead, currentTime: currentTime) }
    public static func stateChange(from: String, to: String, playerType: String) { MKSLog.stateChange(from: from, to: to, playerType: playerType) }
    public static func videoFreeze(duration: Double, currentTime: Double, playbackRate: Float) { MKSLog.videoFreeze(duration: duration, currentTime: currentTime, playbackRate: playbackRate) }
    public static func bufferUnderrun(bufferAhead: Double, currentTime: Double, isStarvation: Bool) { MKSLog.bufferUnderrun(bufferAhead: bufferAhead, currentTime: currentTime, isStarvation: isStarvation) }
    public static func frameDrops(count: Int, totalDropped: Int, currentTime: Double) { MKSLog.frameDrops(count: count, totalDropped: totalDropped, currentTime: currentTime) }
    public static func avSyncDrift(driftMs: Double, videoPTS: Double, audioPTS: Double) { MKSLog.avSyncDrift(driftMs: driftMs, videoPTS: videoPTS, audioPTS: audioPTS) }
    public static func networkError(httpStatus: Int?, error: String?, currentTime: Double) { MKSLog.networkError(httpStatus: httpStatus, error: error, currentTime: currentTime) }
    public static func networkTimeout(segmentIndex: Int?, currentTime: Double, elapsedMs: Double) { MKSLog.networkTimeout(segmentIndex: segmentIndex, currentTime: currentTime, elapsedMs: elapsedMs) }
    public static func metricsSnapshot(currentTime: Double, duration: Double, bufferAhead: Double, bitrate: Double?, stallCount: Int, playbackRate: Float) {
        MKSLog.metricsSnapshot(currentTime: currentTime, duration: duration, bufferAhead: bufferAhead, bitrate: bitrate, stallCount: stallCount, playbackRate: playbackRate)
    }
    public static func generateReport() -> String { MKSLog.generateReport() }
    public static func printReport() { MKSLog.printReport() }
}

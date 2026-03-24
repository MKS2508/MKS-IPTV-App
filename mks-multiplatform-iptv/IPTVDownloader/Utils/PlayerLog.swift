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
enum PlayerLog {

    // MARK: - Forwarded Properties

    static var sessionID: String {
        get { MKSLog.sessionID }
        set { MKSLog.sessionID = newValue }
    }

    static var filePath: String { MKSLog.filePath }

    // MARK: - Forwarded Methods

    static func startSession(playerType: String, url: String?) {
        MKSLog.startSession(playerType: playerType, url: url)
    }

    static func endSession() {
        MKSLog.endSession()
    }

    static func log(
        _ action: String,
        category: String,
        level: GlitchSeverity = .info,
        fields: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        MKSLog.log(action, category: category, level: level, fields: fields)
    }

    static func glitch(_ event: GlitchEvent) { MKSLog.glitch(event) }
    static func seekStart(target: Double, currentPosition: Double) { MKSLog.seekStart(target: target, currentPosition: currentPosition) }
    static func seekComplete(target: Double, actual: Double, latencyMs: Double, accuracy: Double) { MKSLog.seekComplete(target: target, actual: actual, latencyMs: latencyMs, accuracy: accuracy) }
    static func segmentGap(expected: Int, actual: Int, gapSize: Int, currentTime: Double) { MKSLog.segmentGap(expected: expected, actual: actual, gapSize: gapSize, currentTime: currentTime) }
    static func bufferingChange(reason: String?, bufferAhead: Double?, currentTime: Double) { MKSLog.bufferingChange(reason: reason, bufferAhead: bufferAhead, currentTime: currentTime) }
    static func stateChange(from: String, to: String, playerType: String) { MKSLog.stateChange(from: from, to: to, playerType: playerType) }
    static func videoFreeze(duration: Double, currentTime: Double, playbackRate: Float) { MKSLog.videoFreeze(duration: duration, currentTime: currentTime, playbackRate: playbackRate) }
    static func bufferUnderrun(bufferAhead: Double, currentTime: Double, isStarvation: Bool) { MKSLog.bufferUnderrun(bufferAhead: bufferAhead, currentTime: currentTime, isStarvation: isStarvation) }
    static func frameDrops(count: Int, totalDropped: Int, currentTime: Double) { MKSLog.frameDrops(count: count, totalDropped: totalDropped, currentTime: currentTime) }
    static func avSyncDrift(driftMs: Double, videoPTS: Double, audioPTS: Double) { MKSLog.avSyncDrift(driftMs: driftMs, videoPTS: videoPTS, audioPTS: audioPTS) }
    static func networkError(httpStatus: Int?, error: String?, currentTime: Double) { MKSLog.networkError(httpStatus: httpStatus, error: error, currentTime: currentTime) }
    static func networkTimeout(segmentIndex: Int?, currentTime: Double, elapsedMs: Double) { MKSLog.networkTimeout(segmentIndex: segmentIndex, currentTime: currentTime, elapsedMs: elapsedMs) }
    static func metricsSnapshot(currentTime: Double, duration: Double, bufferAhead: Double, bitrate: Double?, stallCount: Int, playbackRate: Float) {
        MKSLog.metricsSnapshot(currentTime: currentTime, duration: duration, bufferAhead: bufferAhead, bitrate: bitrate, stallCount: stallCount, playbackRate: playbackRate)
    }
    static func generateReport() -> String { MKSLog.generateReport() }
    static func printReport() { MKSLog.printReport() }
}

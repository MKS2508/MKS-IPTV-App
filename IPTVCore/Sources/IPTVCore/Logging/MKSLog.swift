import Foundation
import os
import MediaPlayer

// MARK: - MKSLog

/// **THE** unified logger for the entire app. Single source of truth.
/// Every log call forwards to three destinations simultaneously:
///
/// 1. **os.Logger** — visible in Console.app and Xcode
/// 2. **File** — written to disk at `MKSLogConfig.shared.filePath(for: .player)`
/// 3. **WebSocket** — sent to remote transmux-log-viewer when connected
///
/// Also includes all the specialized player logging methods that were previously
/// in `PlayerLog` — session management, seek tracking, glitch detection, etc.
///
/// **Usage**:
/// ```swift
/// MKSLog.player.info("LOAD url=\(url), isLive=\(isLive)")
/// MKSLog.live.warning("Segmenter pipeline failed: \(error)")
/// MKSLog.dlna.debug("SSDP M-SEARCH sent to 239.255.255.250:1900")
/// MKSLog.seekStart(target: 300, currentPosition: 10)
/// MKSLog.stateChange(from: "paused", to: "playing", playerType: "AVPlayer")
/// ```
public enum MKSLog {

    // MARK: - Categories (type-safe)

    public static let player   = Logger(category: "player",     tag: "Player")
    public static let live     = Logger(category: "live",        tag: "LiveTV")
    public static let dlna     = Logger(category: "remoteplay",  tag: "DLNA")
    public static let cast     = Logger(category: "remoteplay",  tag: "Cast")
    public static let transmux = Logger(category: "transmux",    tag: "Transmux")
    public static let app      = Logger(category: "app",         tag: "App")
    public static let network  = Logger(category: "network",     tag: "Network")
    public static let media    = Logger(category: "media",       tag: "Media")
    public static let debug    = Logger(category: "debug",       tag: "Debug")

    // MARK: - Local UI Observer

    /// Callback for the in-app debug view. Every log entry is forwarded here
    /// so DebugStreamingViewModel can display ALL logs (local + transmux + DLNA).
    /// Set by DebugStreamingViewModel on init, cleared on deinit.
    public static var localObserver: ((_ message: String, _ category: String, _ level: String) -> Void)?

    // MARK: - Session Management

    /// Session ID for correlating events across logs.
    public static var sessionID: String = UUID().uuidString.prefix(8).lowercased().description

    /// File path for the log file.
    public static var filePath: String {
        MKSLogConfig.shared.filePath(for: .player)
    }

    /// Start a new logging session.
    public static func startSession(playerType: String, url: String?) {
        sessionID = UUID().uuidString.prefix(8).lowercased().description
        let redactedURL = url?.replacingOccurrences(of: "/[^/]*@", with: "/***@", options: .regularExpression)
        let ts = isoFormatter.string(from: Date())
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] SESSION_START session=\(sessionID) player=\(playerType) url=\(redactedURL ?? "nil")\n\(separator)\n"
        writeToFile(entry)
        player.info("SESSION_START player=\(playerType) url=\(redactedURL ?? "nil")")
    }

    /// End the current logging session.
    public static func endSession() {
        let ts = isoFormatter.string(from: Date())
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] SESSION_END session=\(sessionID)\n\(separator)\n"
        writeToFile(entry)
        player.info("SESSION_END")
    }

    // MARK: - Remote Transport

    /// Shared transport for WebSocket log delivery. Set by RemoteDebugService on connect.
    public static var remoteTransport: RemoteLogTransport?

    // MARK: - Logger Wrapper

    /// A lightweight logger that wraps os.Logger and forwards to file + WebSocket.
    public struct Logger {
        public let category: String
        public let tag: String

        public init(category: String, tag: String) {
            self.category = category
            self.tag = tag
        }

        private var osLogger: os.Logger {
            os.Logger(subsystem: "com.mks.iptv", category: category)
        }

        public func debug(_ message: String, fields: [String: String]? = nil) {
            emit(level: "debug", message: message, fields: fields)
            osLogger.debug("\(message, privacy: .public)")
        }

        public func info(_ message: String, fields: [String: String]? = nil) {
            emit(level: "info", message: message, fields: fields)
            osLogger.info("\(message, privacy: .public)")
        }

        public func warning(_ message: String, fields: [String: String]? = nil) {
            emit(level: "warning", message: message, fields: fields)
            osLogger.warning("\(message, privacy: .public)")
        }

        public func error(_ message: String, fields: [String: String]? = nil) {
            emit(level: "error", message: message, fields: fields)
            osLogger.error("\(message, privacy: .public)")
        }

        private func emit(level: String, message: String, fields: [String: String]?) {
            // Local UI observer (DebugStreamingView)
            let fullMessage = fields.map { f in
                let fStr = f.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                return "[\(tag)] \(message) \(fStr)"
            } ?? "[\(tag)] \(message)"
            MKSLog.localObserver?(fullMessage, category, level)

            // WebSocket transport (non-blocking)
            if let transport = MKSLog.remoteTransport {
                Task {
                    await transport.send(
                        level: level,
                        category: category,
                        tag: tag,
                        message: message,
                        fields: fields,
                        sessionId: MKSLog.sessionID
                    )
                }
            }

            // File transport
            let configLevel: MKSLogConfig.Level = switch level {
            case "debug": .debug
            case "info": .info
            case "warning": .warning
            case "error": .error
            default: .info
            }
            guard configLevel >= MKSLogConfig.shared.level(for: .player) else { return }

            let ts = MKSLog.isoFormatter.string(from: Date())
            let fieldsStr = fields?.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ") ?? ""
            let line = "[\(ts)] [\(level.uppercased())] [\(tag)] \(message) \(fieldsStr)\n"
            MKSLog.writeToFile(line)
        }
    }

    // MARK: - Shared Resources

    private static let fileQueue = DispatchQueue(label: "MKSLog.file", qos: .utility)

    public static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Write a raw string to the log file (thread-safe).
    public static func writeToFile(_ text: String) {
        fileQueue.async {
            guard let data = text.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: filePath) {
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                FileManager.default.createFile(atPath: filePath, contents: data)
            }
        }
    }
}

// MARK: - Specialized Player Logging (formerly PlayerLog)

extension MKSLog {

    /// Log a structured player event (key-value pairs for grepability).
    public static func log(
        _ action: String,
        category: String,
        level: GlitchSeverity = .info,
        fields: [String: Any] = [:]
    ) {
        let configLevel: MKSLogConfig.Level = switch level {
        case .info: .info
        case .warning: .warning
        case .critical: .error
        }
        guard configLevel >= MKSLogConfig.shared.level(for: .player) else { return }

        let ts = isoFormatter.string(from: Date())
        let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        let entry = "[\(ts)] [\(level.rawValue)] [\(category)] \(action) session=\(sessionID) \(fieldsStr)\n"
        writeToFile(entry)

        // Also send via WebSocket
        if let transport = remoteTransport {
            let stringFields = fields.mapValues { "\($0)" }
            Task {
                await transport.send(
                    level: level.rawValue.lowercased(),
                    category: category,
                    tag: category.uppercased(),
                    message: "\(action) \(fieldsStr)",
                    fields: stringFields,
                    sessionId: sessionID
                )
            }
        }
    }

    /// Log a detected glitch.
    public static func glitch(_ event: GlitchEvent) {
        var fields: [String: Any] = [
            "type": event.type.rawValue,
            "currentTime": String(format: "%.3f", event.currentTime),
            "duration": String(format: "%.1f", event.duration),
            "rate": String(format: "%.2f", event.playbackRate),
            "player": event.playerType,
            "message": event.message
        ]
        let metricsStr = event.metrics.grepString
        if !metricsStr.isEmpty { fields[event.type.category] = metricsStr }
        if let sid = event.sessionID { fields["session"] = sid }

        log("GLITCH", category: event.type.category, level: event.severity, fields: fields)
    }

    public static func seekStart(target: Double, currentPosition: Double) {
        log("SEEK_START", category: "timing", fields: [
            "target": String(format: "%.3f", target),
            "from": String(format: "%.3f", currentPosition)
        ])
    }

    public static func seekComplete(target: Double, actual: Double, latencyMs: Double, accuracy: Double) {
        let level: GlitchSeverity = latencyMs > 5000 ? .critical : (latencyMs > 2000 ? .warning : .info)
        log("SEEK_COMPLETE", category: "timing", level: level, fields: [
            "target": String(format: "%.3f", target),
            "actual": String(format: "%.3f", actual),
            "latencyMs": String(format: "%.0f", latencyMs),
            "accuracy": String(format: "%.3f", accuracy)
        ])
    }

    public static func segmentGap(expected: Int, actual: Int, gapSize: Int, currentTime: Double) {
        log("SEGMENT_GAP", category: "buffer", level: .warning, fields: [
            "expected": expected, "actual": actual, "gapSize": gapSize,
            "currentTime": String(format: "%.1f", currentTime)
        ])
    }

    public static func bufferingChange(reason: String?, bufferAhead: Double?, currentTime: Double) {
        log("BUFFERING", category: "buffer", fields: [
            "reason": reason ?? "unknown",
            "bufferAhead": bufferAhead.map { String(format: "%.2f", $0) } ?? "nil",
            "currentTime": String(format: "%.1f", currentTime)
        ])
    }

    public static func stateChange(from: String, to: String, playerType: String) {
        log("STATE_CHANGE", category: "lifecycle", fields: [
            "from": from, "to": to, "player": playerType
        ])
    }

    public static func videoFreeze(duration: Double, currentTime: Double, playbackRate: Float) {
        log("VIDEO_FREEZE", category: "video", level: duration > 1.0 ? .critical : .warning, fields: [
            "freezeDuration": String(format: "%.2f", duration),
            "currentTime": String(format: "%.1f", currentTime),
            "rate": String(format: "%.2f", playbackRate)
        ])
    }

    public static func bufferUnderrun(bufferAhead: Double, currentTime: Double, isStarvation: Bool) {
        log(isStarvation ? "BUFFER_STARVATION" : "BUFFER_UNDERRUN", category: "buffer",
            level: isStarvation ? .critical : .warning, fields: [
            "bufferAhead": String(format: "%.2f", bufferAhead),
            "currentTime": String(format: "%.1f", currentTime)
        ])
    }

    public static func frameDrops(count: Int, totalDropped: Int, currentTime: Double) {
        log("FRAME_DROP", category: "video", level: count >= 3 ? .warning : .info, fields: [
            "drops": count, "totalDropped": totalDropped,
            "currentTime": String(format: "%.1f", currentTime)
        ])
    }

    public static func avSyncDrift(driftMs: Double, videoPTS: Double, audioPTS: Double) {
        let level: GlitchSeverity = driftMs > 500 ? .critical : (driftMs > 100 ? .warning : .info)
        log("AV_DESYNC", category: "timing", level: level, fields: [
            "driftMs": String(format: "%.0f", driftMs),
            "videoPTS": String(format: "%.3f", videoPTS),
            "audioPTS": String(format: "%.3f", audioPTS)
        ])
    }

    public static func networkError(httpStatus: Int?, error: String?, currentTime: Double) {
        var fields: [String: Any] = ["currentTime": String(format: "%.1f", currentTime)]
        if let status = httpStatus { fields["httpStatus"] = status }
        if let error = error { fields["error"] = error }
        log("NETWORK_ERROR", category: "network", level: .critical, fields: fields)
    }

    public static func networkTimeout(segmentIndex: Int?, currentTime: Double, elapsedMs: Double) {
        var fields: [String: Any] = [
            "currentTime": String(format: "%.1f", currentTime),
            "elapsedMs": String(format: "%.0f", elapsedMs)
        ]
        if let idx = segmentIndex { fields["segment"] = idx }
        log("NETWORK_TIMEOUT", category: "network", level: .warning, fields: fields)
    }

    public static func metricsSnapshot(
        currentTime: Double, duration: Double, bufferAhead: Double,
        bitrate: Double?, stallCount: Int, playbackRate: Float
    ) {
        var fields: [String: Any] = [
            "currentTime": String(format: "%.1f", currentTime),
            "duration": String(format: "%.1f", duration),
            "bufferAhead": String(format: "%.2f", bufferAhead),
            "stalls": stallCount,
            "rate": String(format: "%.2f", playbackRate)
        ]
        if let bitrate = bitrate, bitrate > 0 { fields["bitrate"] = String(format: "%.0f", bitrate) }
        log("METRICS", category: "monitoring", fields: fields)
    }
}

// MARK: - Report Generation

extension MKSLog {
    public static func generateReport() -> String {
        var report = "=== Player Glitch Report ===\n\n"
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return "No log file found at \(filePath)"
        }
        let lines = content.components(separatedBy: .newlines)

        let glitchLines = lines.filter { $0.contains("GLITCH") }
        report += "Total glitches: \(glitchLines.count)\n"

        report += "\nBy type:\n"
        for type in PlaybackGlitchType.allCases {
            let count = glitchLines.filter { $0.contains("type=\(type.rawValue)") }.count
            if count > 0 { report += "  \(type.rawValue): \(count)\n" }
        }

        report += "\nBy severity:\n"
        for severity in GlitchSeverity.allCases {
            let count = lines.filter { $0.contains("[\(severity.rawValue)]") }.count
            report += "  \(severity.displayName): \(count)\n"
        }

        let seekLines = lines.filter { $0.contains("SEEK_COMPLETE") }
        let slowSeeks = seekLines.filter { line in
            guard let range = line.range(of: "latencyMs=") else { return false }
            let remainder = line[range.upperBound...]
            return (Double(remainder.prefix(while: { $0.isNumber })) ?? 0) > 2000
        }
        report += "\nSeeks:\n  Total: \(seekLines.count)\n  Slow (>2s): \(slowSeeks.count)\n"
        report += "\nBuffer events:\n"
        report += "  Underruns: \(lines.filter { $0.contains("BUFFER_UNDERRUN") }.count)\n"
        report += "  Starvation: \(lines.filter { $0.contains("BUFFER_STARVATION") }.count)\n"
        return report
    }

    public static func printReport() {
        print(generateReport())
    }
}

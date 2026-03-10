import Foundation

// MARK: - PlayerLog

/// Thread-safe structured logger for player events.
/// Mirrors TransmuxLog design for consistency across the codebase.
/// Output file: <temporaryDirectory>/mks-iptv-player.log
enum PlayerLog {

    // MARK: - Configuration

    public static let filePath: String = {
        let dir = FileManager.default.temporaryDirectory.path
        return (dir as NSString).appendingPathComponent("mks-iptv-player.log")
    }()
    private static let queue = DispatchQueue(label: "PlayerLog.write", qos: .utility)
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Session Management

    /// Session ID for correlating events with TransmuxLog.
    public static var sessionID: String = {
        UUID().uuidString.prefix(8).lowercased()
    }()

    /// Start a new session and write header.
    public static func startSession(playerType: String, url: String?) {
        let redactedURL = url?.replacingOccurrences(of: "/[^/]*@", with: "/***@", options: .regularExpression)
        writeSessionHeader(
            action: "SESSION_START",
            fields: [
                "player": playerType,
                "url": redactedURL ?? "nil"
            ]
        )
    }

    /// End the current session.
    public static func endSession() {
        writeSessionHeader(action: "SESSION_END", fields: [:])
    }

    // MARK: - Core Logging

    /// Log a structured event with key-value pairs for grepability.
    public static func log(
        _ action: String,
        category: String,
        level: GlitchSeverity = .info,
        fields: [String: Any] = [:],
        file: String = #fileID,
        line: Int = #line
    ) {
        let entry = formatEntry(action: action, category: category, level: level, fields: fields)
        queue.async {
            writeEntry(entry)
        }
    }

    // MARK: - Convenience Methods

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
        if !metricsStr.isEmpty {
            fields[event.type.category] = metricsStr
        }

        if let sessionID = event.sessionID {
            fields["session"] = sessionID
        }

        log(
            "GLITCH",
            category: event.type.category,
            level: event.severity,
            fields: fields
        )
    }

    /// Log seek start.
    public static func seekStart(target: Double, currentPosition: Double) {
        log(
            "SEEK_START",
            category: "timing",
            fields: [
                "target": String(format: "%.3f", target),
                "from": String(format: "%.3f", currentPosition)
            ]
        )
    }

    /// Log seek completion.
    public static func seekComplete(target: Double, actual: Double, latencyMs: Double, accuracy: Double) {
        let level: GlitchSeverity
        if latencyMs > 5000 {
            level = .critical
        } else if latencyMs > 2000 {
            level = .warning
        } else {
            level = .info
        }

        log(
            "SEEK_COMPLETE",
            category: "timing",
            level: level,
            fields: [
                "target": String(format: "%.3f", target),
                "actual": String(format: "%.3f", actual),
                "latencyMs": String(format: "%.0f", latencyMs),
                "accuracy": String(format: "%.3f", accuracy)
            ]
        )
    }

    /// Log segment gap detected.
    public static func segmentGap(expected: Int, actual: Int, gapSize: Int, currentTime: Double) {
        log(
            "SEGMENT_GAP",
            category: "buffer",
            level: .warning,
            fields: [
                "expected": expected,
                "actual": actual,
                "gapSize": gapSize,
                "currentTime": String(format: "%.1f", currentTime)
            ]
        )
    }

    /// Log buffering state change.
    public static func bufferingChange(reason: String?, bufferAhead: Double?, currentTime: Double) {
        log(
            "BUFFERING",
            category: "buffer",
            fields: [
                "reason": reason ?? "unknown",
                "bufferAhead": bufferAhead.map { String(format: "%.2f", $0) } ?? "nil",
                "currentTime": String(format: "%.1f", currentTime)
            ]
        )
    }

    /// Log player state change.
    public static func stateChange(from: String, to: String, playerType: String) {
        log(
            "STATE_CHANGE",
            category: "lifecycle",
            fields: [
                "from": from,
                "to": to,
                "player": playerType
            ]
        )
    }

    /// Log video freeze detection.
    public static func videoFreeze(duration: Double, currentTime: Double, playbackRate: Float) {
        log(
            "VIDEO_FREEZE",
            category: "video",
            level: duration > 1.0 ? .critical : .warning,
            fields: [
                "freezeDuration": String(format: "%.2f", duration),
                "currentTime": String(format: "%.1f", currentTime),
                "rate": String(format: "%.2f", playbackRate)
            ]
        )
    }

    /// Log buffer underrun.
    public static func bufferUnderrun(bufferAhead: Double, currentTime: Double, isStarvation: Bool) {
        log(
            isStarvation ? "BUFFER_STARVATION" : "BUFFER_UNDERRUN",
            category: "buffer",
            level: isStarvation ? .critical : .warning,
            fields: [
                "bufferAhead": String(format: "%.2f", bufferAhead),
                "currentTime": String(format: "%.1f", currentTime)
            ]
        )
    }

    /// Log frame drops.
    public static func frameDrops(count: Int, totalDropped: Int, currentTime: Double) {
        log(
            "FRAME_DROP",
            category: "video",
            level: count >= 3 ? .warning : .info,
            fields: [
                "drops": count,
                "totalDropped": totalDropped,
                "currentTime": String(format: "%.1f", currentTime)
            ]
        )
    }

    /// Log A/V sync drift.
    public static func avSyncDrift(driftMs: Double, videoPTS: Double, audioPTS: Double) {
        let level: GlitchSeverity = driftMs > 500 ? .critical : (driftMs > 100 ? .warning : .info)
        log(
            "AV_DESYNC",
            category: "timing",
            level: level,
            fields: [
                "driftMs": String(format: "%.0f", driftMs),
                "videoPTS": String(format: "%.3f", videoPTS),
                "audioPTS": String(format: "%.3f", audioPTS)
            ]
        )
    }

    /// Log network error.
    public static func networkError(httpStatus: Int?, error: String?, currentTime: Double) {
        var fields: [String: Any] = [
            "currentTime": String(format: "%.1f", currentTime)
        ]
        if let status = httpStatus {
            fields["httpStatus"] = status
        }
        if let error = error {
            fields["error"] = error
        }
        log(
            "NETWORK_ERROR",
            category: "network",
            level: .critical,
            fields: fields
        )
    }

    /// Log network timeout.
    public static func networkTimeout(segmentIndex: Int?, currentTime: Double, elapsedMs: Double) {
        var fields: [String: Any] = [
            "currentTime": String(format: "%.1f", currentTime),
            "elapsedMs": String(format: "%.0f", elapsedMs)
        ]
        if let idx = segmentIndex {
            fields["segment"] = idx
        }
        log(
            "NETWORK_TIMEOUT",
            category: "network",
            level: .warning,
            fields: fields
        )
    }

    /// Log playback metrics snapshot (for periodic monitoring).
    public static func metricsSnapshot(
        currentTime: Double,
        duration: Double,
        bufferAhead: Double,
        bitrate: Double?,
        stallCount: Int,
        playbackRate: Float
    ) {
        var fields: [String: Any] = [
            "currentTime": String(format: "%.1f", currentTime),
            "duration": String(format: "%.1f", duration),
            "bufferAhead": String(format: "%.2f", bufferAhead),
            "stalls": stallCount,
            "rate": String(format: "%.2f", playbackRate)
        ]
        if let bitrate = bitrate, bitrate > 0 {
            fields["bitrate"] = String(format: "%.0f", bitrate)
        }
        log(
            "METRICS",
            category: "monitoring",
            level: .info,
            fields: fields
        )
    }

    // MARK: - Format Helpers

    private static func formatEntry(
        action: String,
        category: String,
        level: GlitchSeverity,
        fields: [String: Any]
    ) -> String {
        let ts = dateFormatter.string(from: Date())
        let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return "[\(ts)] [\(level.rawValue)] [\(category)] \(action) session=\(sessionID) \(fieldsStr)"
    }

    private static func writeSessionHeader(action: String, fields: [String: Any]) {
        let ts = dateFormatter.string(from: Date())
        let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] \(action) session=\(sessionID) \(fieldsStr)\n\(separator)\n"
        queue.async {
            writeEntry(entry)
        }
    }

    private static func writeEntry(_ entry: String) {
        let line = entry + "\n"
        print(line, terminator: "")  // Also to console

        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: filePath) {
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            FileManager.default.createFile(atPath: filePath, contents: data)
        }
    }
}

// MARK: - Quick Analysis Helpers

extension PlayerLog {
    /// Generate a summary report from the log file.
    public static func generateReport() -> String {
        var report = "=== Player Glitch Report ===\n\n"

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return "No log file found at \(filePath)"
        }

        let lines = content.components(separatedBy: .newlines)

        // Count glitches
        let glitchLines = lines.filter { $0.contains("GLITCH") }
        report += "Total glitches: \(glitchLines.count)\n"

        // Count by type
        report += "\nBy type:\n"
        for type in PlaybackGlitchType.allCases {
            let count = glitchLines.filter { $0.contains("type=\(type.rawValue)") }.count
            if count > 0 {
                report += "  \(type.rawValue): \(count)\n"
            }
        }

        // Count by severity
        report += "\nBy severity:\n"
        for severity in GlitchSeverity.allCases {
            let count = lines.filter { $0.contains("[\(severity.rawValue)]") }.count
            report += "  \(severity.displayName): \(count)\n"
        }

        // Seeks
        let seekLines = lines.filter { $0.contains("SEEK_COMPLETE") }
        let slowSeeks = seekLines.filter { line in
            guard let range = line.range(of: "latencyMs=") else { return false }
            let remainder = line[range.upperBound...]
            if let ms = Double(remainder.prefix(while: { $0.isNumber })) {
                return ms > 2000
            }
            return false
        }
        report += "\nSeeks:\n"
        report += "  Total: \(seekLines.count)\n"
        report += "  Slow (>2s): \(slowSeeks.count)\n"

        // Buffer events
        report += "\nBuffer events:\n"
        report += "  Underruns: \(lines.filter { $0.contains("BUFFER_UNDERRUN") }.count)\n"
        report += "  Starvation: \(lines.filter { $0.contains("BUFFER_STARVATION") }.count)\n"

        return report
    }

    /// Print the report to console.
    public static func printReport() {
        print(generateReport())
    }
}

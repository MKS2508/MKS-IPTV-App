import Foundation

/// Thread-safe file logger for the transmux pipeline.
/// Writes timestamped entries to `/tmp/mks-iptv-transmux.log`.
/// Also mirrors to stdout via `print()` for Xcode console.
///
/// Usage:
/// ```swift
/// TransmuxLog.log("Something happened", tag: "Server")
/// TransmuxLog.log("Seek to 300s", tag: "Remux", level: .info)
/// ```
///
/// Tail the file live:
/// ```bash
/// tail -f /tmp/mks-iptv-transmux.log
/// ```
enum TransmuxLog {

    enum Level: String {
        case debug = "DBG"
        case info  = "INF"
        case warn  = "WRN"
        case error = "ERR"
    }

    /// Log file path — easy to tail from terminal.
    static let filePath = "/tmp/mks-iptv-transmux.log"

    private static let queue = DispatchQueue(label: "TransmuxLog.write", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Atomic boot marker so we can distinguish sessions in the log file.
    private static let sessionID: String = {
        let id = UUID().uuidString.prefix(8)
        let header = "\n========== TRANSMUX SESSION \(id) @ \(dateFormatter.string(from: Date())) ==========\n"
        // Truncate old log on new session start
        try? header.write(toFile: filePath, atomically: true, encoding: .utf8)
        return String(id)
    }()

    /// Write a log entry to file and stdout.
    static func log(
        _ message: String,
        tag: String,
        level: Level = .info,
        file: String = #fileID,
        line: Int = #line
    ) {
        let ts = dateFormatter.string(from: Date())
        let entry = "[\(ts)] [\(level.rawValue)] [\(tag)] \(message)"

        // Mirror to Xcode console
        print(entry)

        // Write to file (async to avoid blocking callers)
        queue.async {
            // Force session initialization on first call
            _ = sessionID
            guard let handle = FileHandle(forWritingAtPath: filePath) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = (entry + "\n").data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    /// Convenience: log with formatted values.
    static func segment(
        _ action: String,
        segIndex: Int,
        startTime: Double,
        endTime: Double,
        source: String,
        extra: String = ""
    ) {
        let seg = String(format: "seg_%03d", segIndex)
        let t = String(format: "%.1f-%.1fs", startTime, endTime)
        let msg = "\(action) \(seg) [\(t)] source=\(source)\(extra.isEmpty ? "" : " \(extra)")"
        log(msg, tag: "Server")
    }

    /// Convenience: log seek-related events with full state dump.
    static func seekEvent(
        _ action: String,
        seekTime: Double,
        latestTime: Double,
        lastSeekTarget: Double?,
        extra: String = ""
    ) {
        let seek = String(format: "%.1f", seekTime)
        let latest = String(format: "%.1f", latestTime)
        let lastSeek = lastSeekTarget.map { String(format: "%.1f", $0) } ?? "nil"
        let msg = "\(action) seekTime=\(seek)s latestTransmuxed=\(latest)s lastSeekTarget=\(lastSeek)s\(extra.isEmpty ? "" : " \(extra)")"
        log(msg, tag: "Server")
    }

    /// Convenience: log remux loop events.
    static func remux(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "Remux", level: level)
    }

    /// Convenience: log segmenter events.
    static func segmenter(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "Segmenter", level: level)
    }
}

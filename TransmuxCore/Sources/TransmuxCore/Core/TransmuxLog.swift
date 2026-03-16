import Foundation

/// Thread-safe buffered file logger for the transmux pipeline.
/// Writes timestamped entries to `<temporaryDirectory>/mks-iptv-transmux.log`.
/// Also mirrors to stdout via `print()` for Xcode console.
///
/// ## Buffering
/// Entries accumulate in an in-memory ring buffer and are flushed to disk
/// in a single write when the buffer fills (48 entries), a 500ms timer fires,
/// or a warning/error is logged. This reduces file I/O from ~700 open+close
/// cycles per session to ~15-30 batch writes.
///
/// ## Segment Batching
/// Consecutive "immediate" segment serves are accumulated and emitted as
/// a single summary line (e.g., `SERVE seg_004..012 9/9 immediate avg=142KB`).
///
/// Usage:
/// ```swift
/// TransmuxLog.log("Something happened", tag: "Server")
/// TransmuxLog.segmentServed(segIndex: 4, startTime: 24.0, endTime: 30.0,
///                           bytes: 145000, fragments: 3, source: "immediate",
///                           latestBuffered: 36.0)
/// TransmuxLog.flush()  // before reading log or at session end
/// ```
///
/// Tail the file live (macOS):
/// ```bash
/// tail -f $TMPDIR/mks-iptv-transmux.log
/// ```
public enum TransmuxLog {

    // MARK: - Level

    public enum Level: String, Comparable {
        case debug = "DBG"
        case info  = "INF"
        case warn  = "WRN"
        case error = "ERR"

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.order < rhs.order
        }

        private var order: Int {
            switch self {
            case .debug: 0
            case .info:  1
            case .warn:  2
            case .error: 3
            }
        }
    }

    // MARK: - Configuration

    /// Log file path — uses the system temporary directory (sandbox-safe on iOS).
    public static let filePath: String = {
        let dir = FileManager.default.temporaryDirectory.path
        return (dir as NSString).appendingPathComponent("mks-iptv-transmux.log")
    }()

    private static let queue = DispatchQueue(label: "TransmuxLog.write", qos: .utility)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Ring Buffer

    private static var buffer: [String] = []
    private static let bufferCapacity = 48
    private static var persistentHandle: FileHandle?

    // MARK: - Flush Timer (500ms)

    private static let flushTimer: DispatchSourceTimer = {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5)
        t.setEventHandler { flushBuffer() }
        t.resume()
        return t
    }()

    // MARK: - Session ID

    /// Atomic boot marker so we can distinguish sessions in the log file.
    private static let sessionID: String = {
        let id = UUID().uuidString.prefix(8)
        let header = "\n========== TRANSMUX SESSION \(id) @ \(dateFormatter.string(from: Date())) ==========\n"
        // Truncate old log on new session start
        try? header.write(toFile: filePath, atomically: true, encoding: .utf8)
        // Close any stale handle from a previous session
        try? persistentHandle?.close()
        persistentHandle = nil
        return String(id)
    }()

    // MARK: - Segment Batch Tracking

    /// Consecutive "immediate" serves are accumulated and flushed as one line.
    private static var segBatch: (first: Int, last: Int, totalBytes: Int, count: Int, latestBuf: Double)?

    // MARK: - Core Logging

    /// Write a log entry. Warnings and errors flush immediately.
    public static func log(
        _ message: String,
        tag: String,
        level: Level = .info,
        file: String = #fileID,
        line: Int = #line
    ) {
        let entry = formatEntry(tag: tag, level: level, message: message)

        queue.async {
            _ = sessionID          // ensure init on first call
            _ = flushTimer         // ensure timer is started
            buffer.append(entry)

            // Immediate flush for warnings/errors or when buffer full
            if level >= .warn || buffer.count >= bufferCapacity {
                flushBuffer()
            }
        }
    }

    /// Explicit flush — call before reading log file or at session end.
    public static func flush() {
        queue.sync {
            emitSegBatch()
            flushBuffer()
        }
    }

    // MARK: - Segment Serve Logging

    /// Log a segment serve. Immediate serves are batched; polled/seek serves log individually.
    public static func segmentServed(
        segIndex: Int,
        startTime: Double,
        endTime: Double,
        bytes: Int,
        fragments: Int,
        source: String,
        latestBuffered: Double,
        extra: String = ""
    ) {
        queue.async {
            _ = sessionID
            _ = flushTimer

            if source == "immediate" {
                if let b = segBatch, b.last == segIndex - 1 {
                    // Extend current batch
                    segBatch = (b.first, segIndex, b.totalBytes + bytes, b.count + 1, latestBuffered)
                    return
                }
                // Flush old batch, start new
                emitSegBatch()
                segBatch = (segIndex, segIndex, bytes, 1, latestBuffered)
            } else {
                // Non-immediate: flush any pending batch, log this one individually
                emitSegBatch()
                let seg = String(format: "seg_%03d", segIndex)
                let t = String(format: "%.1f-%.1fs", startTime, endTime)
                let kb = bytes / 1024
                let entry = "SERVE \(seg) \(t) \(kb)KB\u{00D7}\(fragments) \(source)\(extra.isEmpty ? "" : " \(extra)")"
                buffer.append(formatEntry(tag: "Server", level: .info, message: entry))
                if buffer.count >= bufferCapacity { flushBuffer() }
            }
        }
    }

    /// Force-emit any pending segment batch. Called internally before flushing.
    private static func emitSegBatch() {
        // Must be called on queue
        guard let b = segBatch else { return }
        segBatch = nil
        let range: String
        if b.first == b.last {
            range = String(format: "seg_%03d", b.first)
        } else {
            range = String(format: "seg_%03d..%03d", b.first, b.last)
        }
        let avgKB = b.count > 0 ? b.totalBytes / b.count / 1024 : 0
        let msg = "SERVE \(range) \(b.count)/\(b.count) immediate avg=\(avgKB)KB buf=\(String(format: "%.1f", b.latestBuf))s"
        buffer.append(formatEntry(tag: "Server", level: .info, message: msg))
    }

    // MARK: - Buffer Flush

    /// Flush accumulated entries to file + stdout in a single batch.
    /// Must be called on `queue`.
    private static func flushBuffer() {
        emitSegBatch()
        guard !buffer.isEmpty else { return }

        let batch = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll(keepingCapacity: true)

        // stdout — single print for entire batch (less interleaving)
        print(batch, terminator: "")

        // File — single write via persistent handle
        if let data = batch.data(using: .utf8) {
            let handle = getOrOpenHandle()
            handle.write(data)
        }
    }

    /// Get or lazily open a persistent file handle for writing.
    private static func getOrOpenHandle() -> FileHandle {
        if let h = persistentHandle { return h }
        // Ensure the file exists before opening for writing
        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: nil)
        }
        guard let h = FileHandle(forWritingAtPath: filePath) else {
            // Fallback: create the file and try again
            FileManager.default.createFile(atPath: filePath, contents: nil)
            guard let fallback = FileHandle(forWritingAtPath: filePath) else {
                // Cannot write to log file — fail silently instead of crashing
                return FileHandle.nullDevice
            }
            persistentHandle = fallback
            return fallback
        }
        h.seekToEndOfFile()
        persistentHandle = h
        return h
    }

    // MARK: - Format Helper

    /// Format a timestamped log entry string.
    private static func formatEntry(tag: String, level: Level, message: String) -> String {
        let ts = dateFormatter.string(from: Date())
        return "[\(ts)] [\(level.rawValue)] [\(tag)] \(message)"
    }

    // MARK: - Convenience Methods

    /// Log segment events (TIMEOUT, GAP SEEK, 404, etc.) — NOT for SERVE batching.
    public static func segmentEvent(
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

    /// Log seek-related events with full state dump.
    public static func seekEvent(
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

    /// Log remux loop events.
    public static func remux(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "Remux", level: level)
    }

    /// Log segmenter events.
    public static func segmenter(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "Segmenter", level: level)
    }

    /// Log service-level events (session management, initialization).
    public static func service(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "Service", level: level)
    }

    /// Log live segmenter events (segment tracking, playlist generation, eviction).
    public static func liveSegmenter(
        _ message: String,
        level: Level = .info
    ) {
        log(message, tag: "LiveSeg", level: level)
    }
}

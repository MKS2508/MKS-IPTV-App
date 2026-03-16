//
//  LogEntryModel.swift
//  mks-multiplatform-iptv
//
//  Unified data models for the Logs Debug Viewer.
//  Supports TransmuxLog, PlayerLog, and CastLog formats.
//

import SwiftUI

// MARK: - Log Source

/// Identifies which subsystem produced the log entry.
enum LogSource: String, CaseIterable, Identifiable, Sendable {
    case transmux = "Transmux"
    case player = "Player"
    case cast = "Cast"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var iconName: String {
        switch self {
        case .transmux: return "gearshape.2"
        case .player: return "play.circle"
        case .cast: return "airplayvideo"
        }
    }

    var color: Color {
        switch self {
        case .transmux: return .purple
        case .player: return .blue
        case .cast: return .green
        }
    }

    /// File path for this log source.
    var filePath: String {
        let dir = FileManager.default.temporaryDirectory.path
        switch self {
        case .transmux: return (dir as NSString).appendingPathComponent("mks-iptv-transmux.log")
        case .player: return (dir as NSString).appendingPathComponent("mks-iptv-player.log")
        case .cast: return (dir as NSString).appendingPathComponent("mks-iptv-cast.log")
        }
    }
}

// MARK: - Log Level

/// Unified log level across all three log sources.
enum LogLevel: String, CaseIterable, Identifiable, Comparable, Sendable {
    case debug = "DBG"
    case info = "INF"
    case warning = "WRN"
    case error = "ERR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var order: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }

    /// Parse level string from log lines.
    static func from(_ string: String) -> LogLevel {
        switch string.uppercased() {
        case "DBG": return .debug
        case "INF": return .info
        case "WRN": return .warning
        case "ERR", "CRI": return .error
        default: return .info
        }
    }
}

// MARK: - Log Entry

/// A single parsed log entry from any of the three log sources.
struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let tag: String
    let action: String
    let fields: [String: String]
    let rawLine: String
    let source: LogSource

    /// Display-formatted timestamp (time only, with milliseconds).
    var formattedTimestamp: String {
        LogEntry.timeFormatter.string(from: timestamp)
    }

    /// Combined fields as a single string for display.
    var fieldsDescription: String {
        fields.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}

// MARK: - Collapsed Log Group

/// A group of consecutive similar log entries collapsed into one row.
struct CollapsedLogGroup: Identifiable, Sendable {
    let id: UUID
    let pattern: String
    let count: Int
    let firstTimestamp: Date
    let lastTimestamp: Date
    let sampleEntry: LogEntry
    let level: LogLevel
    let entries: [LogEntry]

    /// Duration spanned by this group.
    var duration: TimeInterval {
        lastTimestamp.timeIntervalSince(firstTimestamp)
    }

    /// Formatted duration string.
    var formattedDuration: String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = duration.truncatingRemainder(dividingBy: 60)
            return String(format: "%dm %.0fs", minutes, seconds)
        }
    }
}

// MARK: - Display Item

/// Union type for rendering: either a single entry or a collapsed group.
enum LogDisplayItem: Identifiable {
    case single(LogEntry)
    case group(CollapsedLogGroup)

    var id: UUID {
        switch self {
        case .single(let entry): return entry.id
        case .group(let group): return group.id
        }
    }

    var timestamp: Date {
        switch self {
        case .single(let entry): return entry.timestamp
        case .group(let group): return group.firstTimestamp
        }
    }

    var level: LogLevel {
        switch self {
        case .single(let entry): return entry.level
        case .group(let group): return group.level
        }
    }

    var source: LogSource {
        switch self {
        case .single(let entry): return entry.source
        case .group(let group): return group.sampleEntry.source
        }
    }

    /// Raw text for copy operations.
    var copyText: String {
        switch self {
        case .single(let entry):
            return entry.rawLine
        case .group(let group):
            return group.entries.map(\.rawLine).joined(separator: "\n")
        }
    }
}

// MARK: - Log File Stats

/// Statistics about a log file on disk.
struct LogFileStats: Sendable {
    let source: LogSource
    let fileSize: Int64
    let lineCount: Int
    let exists: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

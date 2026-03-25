//
//  LogParser.swift
//  mks-multiplatform-iptv
//
//  Parses log files from TransmuxLog, PlayerLog, and CastLog into unified LogEntry models.
//  Handles two distinct formats:
//    - TransmuxLog: [HH:mm:ss.SSS] [LEVEL] [TAG] MESSAGE
//    - PlayerLog/CastLog: [ISO8601] [LEVEL] [CATEGORY] ACTION session=ID key=value ...
//

import Foundation

/// Parses raw log file text into structured LogEntry arrays.
enum LogParser {

    // MARK: - Public API

    /// Parse an entire log file for the given source.
    static func parse(content: String, source: LogSource) -> [LogEntry] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [LogEntry] = []
        entries.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip session separator lines (=====...)
            if trimmed.hasPrefix("====") { continue }

            if let entry = parseLine(trimmed, source: source) {
                entries.append(entry)
            }
        }

        return entries
    }

    /// Parse a single line for the given source.
    static func parseLine(_ line: String, source: LogSource) -> LogEntry? {
        switch source {
        case .transmux:
            return parseTransmuxLine(line)
        case .player, .cast, .live:
            return parseStructuredLine(line, source: source)
        case .remote:
            return parseStructuredLine(line, source: source)
        }
    }

    // MARK: - TransmuxLog Parser

    /// Parse TransmuxLog format: `[HH:mm:ss.SSS] [LEVEL] [TAG] MESSAGE`
    private static func parseTransmuxLine(_ line: String) -> LogEntry? {
        // Extract bracketed segments: [timestamp] [level] [tag]
        var scanner = BracketScanner(line)

        guard let timestampStr = scanner.nextBracketContent(),
              let levelStr = scanner.nextBracketContent(),
              let tag = scanner.nextBracketContent() else {
            return nil
        }

        let remainder = scanner.remainder.trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        // Parse timestamp (HH:mm:ss.SSS) — use today's date
        guard let timestamp = parseTimeOnly(timestampStr) else { return nil }

        // Extract action (first word) and fields from message
        let (action, fields) = extractActionAndFields(from: remainder)

        return LogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: LogLevel.from(levelStr),
            tag: tag,
            action: action,
            fields: fields,
            rawLine: line,
            source: .transmux
        )
    }

    // MARK: - PlayerLog / CastLog Parser

    /// Parse structured format: `[ISO8601] [LEVEL] [CATEGORY] ACTION session=ID key=value ...`
    private static func parseStructuredLine(_ line: String, source: LogSource) -> LogEntry? {
        var scanner = BracketScanner(line)

        guard let timestampStr = scanner.nextBracketContent(),
              let levelStr = scanner.nextBracketContent(),
              let category = scanner.nextBracketContent() else {
            return nil
        }

        let remainder = scanner.remainder.trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        // Parse ISO8601 timestamp
        guard let timestamp = parseISO8601(timestampStr) else { return nil }

        // Extract action (first word) and key=value pairs
        let (action, fields) = extractActionAndFields(from: remainder)

        return LogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: LogLevel.from(levelStr),
            tag: category,
            action: action,
            fields: fields,
            rawLine: line,
            source: source
        )
    }

    // MARK: - Field Extraction

    /// Extract the action keyword and key=value pairs from a message string.
    /// Example: `SEEK_COMPLETE session=abc123 target=42.5 latencyMs=1200`
    /// Returns: ("SEEK_COMPLETE", ["session": "abc123", "target": "42.5", "latencyMs": "1200"])
    private static func extractActionAndFields(from message: String) -> (String, [String: String]) {
        let parts = message.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return (message, [:]) }

        let action = String(first)
        var fields: [String: String] = [:]

        // Collect non-KV parts as the "message" field if they exist
        var messageParts: [String] = []

        for part in parts.dropFirst() {
            let s = String(part)
            if let eqIndex = s.firstIndex(of: "=") {
                let key = String(s[s.startIndex..<eqIndex])
                let value = String(s[s.index(after: eqIndex)...])
                if !key.isEmpty {
                    fields[key] = value
                } else {
                    messageParts.append(s)
                }
            } else {
                messageParts.append(s)
            }
        }

        if !messageParts.isEmpty {
            fields["_msg"] = messageParts.joined(separator: " ")
        }

        return (action, fields)
    }

    // MARK: - Timestamp Parsing

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse ISO8601 timestamp string.
    private static func parseISO8601(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601FallbackFormatter.date(from: string)
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// Parse HH:mm:ss.SSS into a Date using today's date components.
    private static func parseTimeOnly(_ string: String) -> Date? {
        guard let timeDate = timeOnlyFormatter.date(from: string) else { return nil }

        let calendar = Calendar.current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: timeDate)

        var combined = DateComponents()
        combined.year = today.year
        combined.month = today.month
        combined.day = today.day
        combined.hour = time.hour
        combined.minute = time.minute
        combined.second = time.second
        combined.nanosecond = time.nanosecond

        return calendar.date(from: combined)
    }
}

// MARK: - Bracket Scanner

/// Lightweight scanner for extracting `[content]` segments from log lines.
private struct BracketScanner {
    private let source: String
    private var currentIndex: String.Index

    var remainder: String {
        String(source[currentIndex...])
    }

    init(_ string: String) {
        self.source = string
        self.currentIndex = string.startIndex
    }

    /// Extract content from the next `[...]` bracket pair.
    mutating func nextBracketContent() -> String? {
        // Skip whitespace
        while currentIndex < source.endIndex && source[currentIndex].isWhitespace {
            currentIndex = source.index(after: currentIndex)
        }

        guard currentIndex < source.endIndex, source[currentIndex] == "[" else { return nil }
        let contentStart = source.index(after: currentIndex)

        // Find matching close bracket
        guard let closeIndex = source[contentStart...].firstIndex(of: "]") else { return nil }

        let content = String(source[contentStart..<closeIndex])
        currentIndex = source.index(after: closeIndex)
        return content
    }
}

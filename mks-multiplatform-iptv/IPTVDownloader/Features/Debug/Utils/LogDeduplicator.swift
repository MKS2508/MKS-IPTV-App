//
//  LogDeduplicator.swift
//  mks-multiplatform-iptv
//
//  Groups consecutive similar log entries to reduce visual noise.
//  Targets: SERVE segments, HEARTBEAT pings, METRICS snapshots, and other repeated actions.
//

import Foundation
import IPTVCore

/// Groups consecutive similar log entries into collapsed groups.
enum LogDeduplicator {

    // MARK: - Public API

    /// Process entries into display items, collapsing consecutive duplicates.
    static func deduplicate(_ entries: [LogEntry]) -> [LogDisplayItem] {
        guard !entries.isEmpty else { return [] }

        var result: [LogDisplayItem] = []
        var currentGroupEntries: [LogEntry] = []
        var currentPattern: String?

        for entry in entries {
            let pattern = detectPattern(entry)

            if let pattern, pattern == currentPattern {
                // Extend current group
                currentGroupEntries.append(entry)
            } else {
                // Flush previous group
                flush(groupEntries: &currentGroupEntries, pattern: currentPattern, into: &result)

                if pattern != nil {
                    // Start new group
                    currentGroupEntries = [entry]
                    currentPattern = pattern
                } else {
                    // Non-groupable entry
                    result.append(.single(entry))
                    currentPattern = nil
                }
            }
        }

        // Flush remaining group
        flush(groupEntries: &currentGroupEntries, pattern: currentPattern, into: &result)

        return result
    }

    // MARK: - Pattern Detection

    /// Returns a grouping pattern key if this entry is eligible for collapsing.
    /// Entries with the same pattern key that appear consecutively are grouped.
    private static func detectPattern(_ entry: LogEntry) -> String? {
        let action = entry.action

        // TransmuxLog: SERVE segments (immediate serves)
        if action == "SERVE" && entry.source == .transmux {
            return "SERVE:\(entry.tag)"
        }

        // CastLog: HEARTBEAT ping/pong
        if action == "HEARTBEAT" {
            return "HEARTBEAT:\(entry.source.rawValue)"
        }

        // PlayerLog: periodic METRICS snapshots
        if action == "METRICS" {
            return "METRICS:\(entry.source.rawValue)"
        }

        // CastLog: MSG_ROUTED (can be very chatty)
        if action == "MSG_ROUTED" {
            return "MSG_ROUTED:\(entry.source.rawValue)"
        }

        // CastLog: SEND/RECV socket messages in quick succession
        if (action == "SEND" || action == "RECV") && entry.source == .cast {
            return "\(action):socket:\(entry.source.rawValue)"
        }

        // PlayerLog: STATE_CHANGE can repeat during seek loops
        // Don't collapse these — they carry meaningful state transitions

        return nil
    }

    // MARK: - Flush Helper

    /// Flush accumulated group entries into the result array.
    private static func flush(
        groupEntries: inout [LogEntry],
        pattern: String?,
        into result: inout [LogDisplayItem]
    ) {
        guard !groupEntries.isEmpty else { return }

        if groupEntries.count == 1 {
            // Single entry — no point in grouping
            result.append(.single(groupEntries[0]))
        } else if let pattern {
            // Multiple entries — create collapsed group
            let maxLevel = groupEntries.map(\.level).max() ?? .info
            let group = CollapsedLogGroup(
                id: UUID(),
                pattern: formatPattern(pattern, entries: groupEntries),
                count: groupEntries.count,
                firstTimestamp: groupEntries.first!.timestamp,
                lastTimestamp: groupEntries.last!.timestamp,
                sampleEntry: groupEntries.first!,
                level: maxLevel,
                entries: groupEntries
            )
            result.append(.group(group))
        }

        groupEntries.removeAll(keepingCapacity: true)
    }

    /// Format a human-readable pattern description.
    private static func formatPattern(_ key: String, entries: [LogEntry]) -> String {
        let prefix = key.split(separator: ":").first.map(String.init) ?? key

        switch prefix {
        case "SERVE":
            return "SERVE segments"
        case "HEARTBEAT":
            return "HEARTBEAT"
        case "METRICS":
            return "METRICS snapshot"
        case "MSG_ROUTED":
            return "MSG_ROUTED"
        case "SEND":
            return "Socket SEND"
        case "RECV":
            return "Socket RECV"
        default:
            return prefix
        }
    }
}

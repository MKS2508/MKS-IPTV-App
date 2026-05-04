//
//  EPGModels.swift
//  mks-multiplatform-iptv
//
//  Data models for Electronic Program Guide (EPG) from XMLTV format
//

import Foundation
import IPTVCore

// MARK: - EPG Channel

/// Represents a TV channel from the EPG data
struct EPGChannel: Identifiable, Codable, Equatable {
    let id: String
    let displayNames: [String]
    let iconURL: String?

    static func == (lhs: EPGChannel, rhs: EPGChannel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - EPG Programme

/// Represents a single programme/show entry in the EPG
struct EPGProgramme: Identifiable, Codable, Equatable {
    let channelId: String
    let start: Date
    let stop: Date
    let title: String
    let description: String?
    let category: String?
    let year: String?
    let rating: String?

    var id: String {
        "\(channelId)_\(start.timeIntervalSince1970)"
    }

    /// Whether this programme is currently airing
    var isNow: Bool {
        let now = Date()
        return now >= start && now < stop
    }

    /// Whether this programme is upcoming (starts within the next 3 hours)
    var isUpcoming: Bool {
        let now = Date()
        let threeHoursFromNow = now.addingTimeInterval(3 * 3600)
        return start >= now && start < threeHoursFromNow
    }

    /// Progress through the current programme (0.0 to 1.0)
    var progress: Double {
        let now = Date()
        guard now >= start else { return 0.0 }
        guard now < stop else { return 1.0 }
        let total = stop.timeIntervalSince(start)
        guard total > 0 else { return 0.0 }
        let elapsed = now.timeIntervalSince(start)
        return elapsed / total
    }

    /// Duration in minutes
    var durationMinutes: Int {
        Int(stop.timeIntervalSince(start) / 60)
    }

    /// Formatted start time (HH:mm)
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }

    /// Formatted stop time (HH:mm)
    var formattedStopTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: stop)
    }

    static func == (lhs: EPGProgramme, rhs: EPGProgramme) -> Bool {
        lhs.channelId == rhs.channelId && lhs.start == rhs.start
    }
}

// MARK: - EPG Data Container

/// Complete EPG dataset with channels and programmes
struct EPGData: Codable {
    let channels: [EPGChannel]
    let programmes: [EPGProgramme]
    let fetchedAt: Date
}

// MARK: - EPG Error

/// Errors that can occur during EPG operations
enum EPGError: Error, LocalizedError {
    case fetchFailed(Error)
    case parseFailed(String)
    case invalidURL
    case noData
    case cacheMiss

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let error):
            return "Failed to fetch EPG data: \(error.localizedDescription)"
        case .parseFailed(let reason):
            return "Failed to parse EPG data: \(reason)"
        case .invalidURL:
            return "Invalid EPG URL"
        case .noData:
            return "No EPG data available"
        case .cacheMiss:
            return "EPG data not found in cache"
        }
    }
}

// MARK: - EPG Match Result

/// Result of matching a LiveChannel to an EPG channel
struct EPGMatchResult {
    let liveChannelId: Int
    let epgChannelId: String
    let matchType: MatchType

    enum MatchType {
        case exactId
        case exactName
        case fuzzyName(similarity: Double)
    }
}

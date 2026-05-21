//
//  WSModels.swift
//  mksiptv-server
//
//  WebSocket message models for real-time events.
//

import Vapor
import Foundation

// MARK: - Event Channels

/// Event channels for WebSocket subscriptions
public enum EventChannel: String, Codable {
    case newContent = "new_content"
    case downloads
    case profile
    case streams
}

// MARK: - WebSocket Messages

/// WebSocket message types
public enum WSMessageType: String, Codable {
    case subscribe
    case unsubscribe
    case event
    case ping
    case pong
}

/// WebSocket message wrapper
public struct WSMessage: Codable {
    public let type: WSMessageType
    public let channel: EventChannel?
    public let payload: EventPayload?

    public init(type: WSMessageType, channel: EventChannel? = nil, payload: EventPayload? = nil) {
        self.type = type
        self.channel = channel
        self.payload = payload
    }
}

// MARK: - Event Payloads

/// Generic event payload wrapper
public struct EventPayload: Codable {
    public let channel: EventChannel
    public let timestamp: Date
    public let data: AnyCodable

    public init(channel: EventChannel, data: AnyCodable) {
        self.channel = channel
        self.timestamp = Date()
        self.data = data
    }
}

// MARK: - Specific Event Data

/// New content event data
public struct NewContentEvent: Codable {
    public let type: MediaType
    public let id: Int
    public let name: String
    public let categoryId: String
    public let addedAt: Date

    public init(type: MediaType, id: Int, name: String, categoryId: String, addedAt: Date = Date()) {
        self.type = type
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.addedAt = addedAt
    }
}

/// Media type enumeration
public enum MediaType: String, Codable, Sendable {
    case movie
    case series
    case liveChannel = "live_channel"
}

/// Download status event data
public struct DownloadStatusEvent: Codable {
    public let downloadId: UUID
    public let status: DownloadStatus
    public let progress: Double?
    public let speed: Double?
    public let error: String?

    public init(downloadId: UUID, status: DownloadStatus, progress: Double? = nil, speed: Double? = nil, error: String? = nil) {
        self.downloadId = downloadId
        self.status = status
        self.progress = progress
        self.speed = speed
        self.error = error
    }
}

/// Download status enumeration
public enum DownloadStatus: String, Codable, Sendable {
    case queued
    case started
    case downloading
    case paused
    case transmuxing
    case completed
    case failed
    case cancelled
}

/// Profile changed event data
public struct ProfileChangedEvent: Codable {
    public let profileId: UUID
    public let profileName: String
    public let activatedAt: Date

    public init(profileId: UUID, profileName: String, activatedAt: Date = Date()) {
        self.profileId = profileId
        self.profileName = profileName
        self.activatedAt = activatedAt
    }
}

/// Stream status event data
public struct StreamStatusEvent: Codable {
    public let streamId: UUID
    public let contentId: Int
    public let status: StreamStatus
    public let timestamp: Date

    public init(streamId: UUID, contentId: Int, status: StreamStatus, timestamp: Date = Date()) {
        self.streamId = streamId
        self.contentId = contentId
        self.status = status
        self.timestamp = timestamp
    }
}

/// Stream status enumeration
public enum StreamStatus: String, Codable {
    case started
    case stopped
    case error
}

/// Stream error event data
public struct StreamErrorEvent: Codable {
    public let streamId: UUID
    public let contentId: Int
    public let error: String
    public let timestamp: Date

    public init(streamId: UUID, contentId: Int, error: String, timestamp: Date = Date()) {
        self.streamId = streamId
        self.contentId = contentId
        self.error = error
        self.timestamp = timestamp
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic event data
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

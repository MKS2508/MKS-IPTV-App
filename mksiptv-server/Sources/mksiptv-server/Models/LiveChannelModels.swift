//
//  LiveChannelModels.swift
//  mksiptv-server
//
//  Request/Response models for Live Channel endpoints.
//

import Vapor
import IPTVCore

// MARK: - Response Models

/// Live channel response for list endpoints
public struct LiveChannelResponse: Content {
    public let id: Int
    public let number: Int
    public let name: String
    public let icon: String?
    public let categoryId: String?
    public let hasArchive: Bool

    public init(
        id: Int,
        number: Int,
        name: String,
        icon: String?,
        categoryId: String?,
        hasArchive: Bool
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.icon = icon
        self.categoryId = categoryId
        self.hasArchive = hasArchive
    }

    /// Create from LiveChannel
    public init(from channel: LiveChannel) {
        self.id = channel.streamId
        self.number = channel.num
        self.name = channel.name
        self.icon = channel.streamIcon
        self.categoryId = channel.categoryId
        self.hasArchive = channel.tvArchive > 0
    }
}

/// Live channel detail with additional metadata
public struct LiveChannelDetailResponse: Content {
    public let id: Int
    public let number: Int
    public let name: String
    public let icon: String?
    public let categoryId: String?
    public let hasArchive: Bool
    public let epgChannelId: String?
    public let customSid: String?

    public init(
        id: Int,
        number: Int,
        name: String,
        icon: String?,
        categoryId: String?,
        hasArchive: Bool,
        epgChannelId: String?,
        customSid: String?
    ) {
        self.id = id
        self.number = number
        self.name = name
        self.icon = icon
        self.categoryId = categoryId
        self.hasArchive = hasArchive
        self.epgChannelId = epgChannelId
        self.customSid = customSid
    }

    /// Create from LiveChannel
    public init(from channel: LiveChannel) {
        self.id = channel.streamId
        self.number = channel.num
        self.name = channel.name
        self.icon = channel.streamIcon
        self.categoryId = channel.categoryId
        self.hasArchive = channel.tvArchive > 0
        self.epgChannelId = channel.epgChannelId
        self.customSid = channel.customSid
    }
}

/// Live channel stream URL response
public struct LiveStreamURLResponse: Content {
    public let channelId: Int
    public let url: String
    public let headers: [String: String]?

    public init(channelId: Int, url: String, headers: [String: String]? = nil) {
        self.channelId = channelId
        self.url = url
        self.headers = headers
    }
}

/// EPG programme response
public struct EPGProgrammeResponse: Content {
    public let title: String
    public let description: String?
    public let start: Date
    public let stop: Date
    public let category: String?

    public init(
        title: String,
        description: String?,
        start: Date,
        stop: Date,
        category: String?
    ) {
        self.title = title
        self.description = description
        self.start = start
        self.stop = stop
        self.category = category
    }
}

/// Live channel EPG response
public struct LiveChannelEPGResponse: Content {
    public let channelId: Int
    public let programmes: [EPGProgrammeResponse]

    public init(channelId: Int, programmes: [EPGProgrammeResponse]) {
        self.channelId = channelId
        self.programmes = programmes
    }
}

/// Live channel category response
public struct LiveChannelCategoryResponse: Content {
    public let id: String
    public let name: String
    public let parentId: Int

    public init(id: String, name: String, parentId: Int) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }

    /// Create from LiveChannelCategory
    public init(from category: LiveChannelCategory) {
        self.id = category.categoryId
        self.name = category.categoryName
        self.parentId = category.parentId
    }
}

/// Channels list response with pagination
public struct ChannelsListResponse: Content {
    public let channels: [LiveChannelResponse]
    public let page: Int
    public let totalPages: Int?
    public let totalChannels: Int?

    public init(
        channels: [LiveChannelResponse],
        page: Int,
        totalPages: Int? = nil,
        totalChannels: Int? = nil
    ) {
        self.channels = channels
        self.page = page
        self.totalPages = totalPages
        self.totalChannels = totalChannels
    }
}

// MARK: - Error Responses

/// Live channel error response
public struct LiveChannelErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Live Channel Error Types

public enum LiveChannelError: String {
    case channelNotFound = "CHANNEL_NOT_FOUND"
    case streamUnavailable = "STREAM_UNAVAILABLE"
    case noActiveProfile = "NO_ACTIVE_PROFILE"
    case invalidCategory = "INVALID_CATEGORY"
    case apiError = "API_ERROR"
}

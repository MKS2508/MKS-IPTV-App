//
//  LiveChannel.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 16/1/25.
//

import Foundation

public struct LiveChannel: Identifiable, Codable, Equatable {
    public let num: Int
    public let name: String
    public let streamType: String
    public let streamId: Int
    public let streamIcon: String?
    public let epgChannelId: String?
    public let added: String
    public let isAdult: String?
    public let categoryId: String?
    public let customSid: String?
    public let tvArchive: Int
    public let directSource: String?
    public let tvArchiveDuration: Int

    public var id: Int { streamId }

    public init(
        num: Int,
        name: String,
        streamType: String,
        streamId: Int,
        streamIcon: String?,
        epgChannelId: String?,
        added: String,
        isAdult: String?,
        categoryId: String?,
        customSid: String?,
        tvArchive: Int,
        directSource: String?,
        tvArchiveDuration: Int
    ) {
        self.num = num
        self.name = name
        self.streamType = streamType
        self.streamId = streamId
        self.streamIcon = streamIcon
        self.epgChannelId = epgChannelId
        self.added = added
        self.isAdult = isAdult
        self.categoryId = categoryId
        self.customSid = customSid
        self.tvArchive = tvArchive
        self.directSource = directSource
        self.tvArchiveDuration = tvArchiveDuration
    }

    public enum CodingKeys: String, CodingKey {
        case num
        case name
        case streamType = "stream_type"
        case streamId = "stream_id"
        case streamIcon = "stream_icon"
        case epgChannelId = "epg_channel_id"
        case added
        case isAdult = "is_adult"
        case categoryId = "category_id"
        case customSid = "custom_sid"
        case tvArchive = "tv_archive"
        case directSource = "direct_source"
        case tvArchiveDuration = "tv_archive_duration"
    }

    public var formattedTitle: String {
        name.replacingOccurrences(of: "\\s+\\([0-9]{4}\\).*$", with: "", options: .regularExpression)
    }

    public var quality: String? {
        if let match = name.firstMatch(of: /\d{3,4}[pi]/) {
            return String(match.0)
        }
        return nil
    }

    public static func == (lhs: LiveChannel, rhs: LiveChannel) -> Bool {
        lhs.id == rhs.id
    }
}

extension LiveChannel {
    public static var placeholder: LiveChannel {
        LiveChannel(
            num: 0,
            name: "Placeholder Channel",
            streamType: "live",
            streamId: 0,
            streamIcon: nil,
            epgChannelId: nil,
            added: "",
            isAdult: "0",
            categoryId: "0",
            customSid: nil,
            tvArchive: 0,
            directSource: nil,
            tvArchiveDuration: 0
        )
    }
}

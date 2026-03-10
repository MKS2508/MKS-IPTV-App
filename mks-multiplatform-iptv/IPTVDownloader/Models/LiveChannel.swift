//
//  LiveChannel.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 16/1/25.
//

import Foundation

struct LiveChannel: Identifiable, Codable, Equatable {
    let num: Int
    let name: String
    let streamType: String
    let streamId: Int
    let streamIcon: String?
    let epgChannelId: String?
    let added: String
    let isAdult: String
    let categoryId: String?
    let customSid: String?
    let tvArchive: Int
    let directSource: String?
    let tvArchiveDuration: Int

    var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
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

    var formattedTitle: String {
        name.replacingOccurrences(of: "\\s+\\([0-9]{4}\\).*$", with: "", options: .regularExpression)
    }

    var quality: String? {
        if let match = name.firstMatch(of: /\d{3,4}[pi]/) {
            return String(match.0)
        }
        return nil
    }

    static func == (lhs: LiveChannel, rhs: LiveChannel) -> Bool {
        lhs.id == rhs.id
    }
}

extension LiveChannel {
    static var placeholder: LiveChannel {
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

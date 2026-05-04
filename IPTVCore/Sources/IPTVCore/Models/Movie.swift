//
//  Movie.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 30/10/24.
//
import Foundation

public struct Movie: Identifiable, Codable, Equatable, TitleParseable {
    public let name: String
    public let streamType: String?
    public let streamId: Int
    public let tmdbId: String?
    public let streamIcon: String?
    public let rating: String?
    public let rating5Based: Double?
    public let added: String?
    public let isAdult: String?
    public let categoryId: String
    public let containerExtension: String?
    public let customSid: String?
    public let directSource: String?
    
    public let id = UUID()
    
    public var apiId: Int { streamId }
    
    public enum CodingKeys: String, CodingKey {
        case name
        case streamType = "stream_type"
        case streamId = "stream_id"
        case tmdbId = "tmdb_id"
        case streamIcon = "stream_icon"
        case rating5Based = "rating_5based"
        case added
        case rating
        case isAdult = "is_adult"
        case categoryId = "category_id"
        case containerExtension = "container_extension"
        case customSid = "custom_sid"
        case directSource = "direct_source"
    }

    public init(name: String, streamType: String?, streamId: Int, tmdbId: String?, streamIcon: String?, rating: String?, rating5Based: Double?, added: String?, isAdult: String?, categoryId: String, containerExtension: String?, customSid: String?, directSource: String?) {
        self.name = name
        self.streamType = streamType
        self.streamId = streamId
        self.tmdbId = tmdbId
        self.streamIcon = streamIcon
        self.rating = rating
        self.rating5Based = rating5Based
        self.added = added
        self.isAdult = isAdult
        self.categoryId = categoryId
        self.containerExtension = containerExtension
        self.customSid = customSid
        self.directSource = directSource
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        streamType = try container.decodeIfPresent(String.self, forKey: .streamType)
        streamId = try container.decode(Int.self, forKey: .streamId)
        // tmdb_id comes as String or Int from the API
        if let str = try? container.decodeIfPresent(String.self, forKey: .tmdbId) {
            tmdbId = str
        } else if let num = try? container.decodeIfPresent(Int.self, forKey: .tmdbId) {
            tmdbId = String(num)
        } else {
            tmdbId = nil
        }
        streamIcon = try container.decodeIfPresent(String.self, forKey: .streamIcon)
        // rating can come as String or Double from different servers
        if let str = try? container.decodeIfPresent(String.self, forKey: .rating) {
            rating = str
        } else if let num = try? container.decodeIfPresent(Double.self, forKey: .rating) {
            rating = String(num)
        } else {
            rating = nil
        }
        rating5Based = try container.decodeIfPresent(Double.self, forKey: .rating5Based)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        isAdult = try container.decodeIfPresent(String.self, forKey: .isAdult)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
        customSid = try container.decodeIfPresent(String.self, forKey: .customSid)
        directSource = try container.decodeIfPresent(String.self, forKey: .directSource)
    }

    public static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.streamId == rhs.streamId
    }
}

extension Movie {
    public static var placeholder: Movie {
        Movie(name: "Placeholder Movie",
              streamType: "movie",
              streamId: 0,
              tmdbId: nil,
              streamIcon: nil,
              rating: "0.0",
              rating5Based: 0.0,
              added: nil,
              isAdult: "0",
              categoryId: "0",
              containerExtension: nil,
              customSid: nil,
              directSource: nil)
    }
}

//
//  Movie.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 30/10/24.
//
import Foundation

struct Movie: Identifiable, Codable, Equatable {
    let name: String
    let streamType: String?
    let streamId: Int
    let tmdbId: String?
    let streamIcon: String?
    let rating: String?
    let rating5Based: Double?
    let added: String?
    let isAdult: String?
    let categoryId: String
    let containerExtension: String?
    let customSid: String?
    let directSource: String?
    
    var id: Int { streamId }
    
    enum CodingKeys: String, CodingKey {
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

    init(name: String, streamType: String?, streamId: Int, tmdbId: String?, streamIcon: String?, rating: String?, rating5Based: Double?, added: String?, isAdult: String?, categoryId: String, containerExtension: String?, customSid: String?, directSource: String?) {
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

    init(from decoder: Decoder) throws {
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
        rating = try container.decodeIfPresent(String.self, forKey: .rating)
        rating5Based = try container.decodeIfPresent(Double.self, forKey: .rating5Based)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        isAdult = try container.decodeIfPresent(String.self, forKey: .isAdult)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        containerExtension = try container.decodeIfPresent(String.self, forKey: .containerExtension)
        customSid = try container.decodeIfPresent(String.self, forKey: .customSid)
        directSource = try container.decodeIfPresent(String.self, forKey: .directSource)
    }

    var parsedMetadata: TitleMetadata {
        TitleParser.parse(name)
    }
    
    var quality: String? {
        parsedMetadata.quality
    }
    
    var codec: String? {
        parsedMetadata.codec
    }
    
    var source: String? {
        parsedMetadata.source
    }
    
    var cleanTitle: String {
        parsedMetadata.cleanTitle
    }
    
    var isHDR: Bool {
        parsedMetadata.isHDR
    }
    
    var is3D: Bool {
        parsedMetadata.is3D
    }
    
    static func == (lhs: Movie, rhs: Movie) -> Bool {
        lhs.id == rhs.id
    }
}

extension Movie {
    static var placeholder: Movie {
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

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
    

    
    var quality: String? {
        if let match = name.firstMatch(of: /\d{3,4}[pi]/) {
            return String(match.0)
        }
        return nil
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

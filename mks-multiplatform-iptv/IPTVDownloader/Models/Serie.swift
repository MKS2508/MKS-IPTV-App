//
//  Movie.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 30/10/24.
//
import Foundation
struct Serie: Identifiable, Codable, Equatable {
    let number: Int
    let name: String
    let seriesId: Int
    let cover: String?
    let plot: String
    let cast: String
    let director: String?
    let genre: String
    let releaseDate: String
    let lastModified: String
    let rating: String
    let rating5Based: Double
    let backdropPath: [String]
    let youtubeTrailer: String?
    let episodeRunTime: String
    let categoryId: String
    
    var id: Int { seriesId }
    
    enum CodingKeys: String, CodingKey {
        case number = "num"
        case name
        case seriesId = "series_id"
        case cover
        case plot
        case cast
        case director
        case genre
        case releaseDate = "releaseDate"
        case lastModified = "last_modified"
        case rating
        case rating5Based = "rating_5based"
        case backdropPath = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
        case episodeRunTime = "episode_run_time"
        case categoryId = "category_id"
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
}

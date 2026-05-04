//
//  Movie.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 30/10/24.
//
import Foundation
public struct Serie: Identifiable, Codable, Equatable, TitleParseable {
    public let number: Int
    public let name: String
    public let seriesId: Int
    public let cover: String?
    public let plot: String
    public let cast: String
    public let director: String?
    public let genre: String
    public let releaseDate: String
    public let lastModified: String
    public let rating: String
    public let rating5Based: Double
    public let backdropPath: [String]
    public let youtubeTrailer: String?
    public let episodeRunTime: String
    public let categoryId: String
    
    public let id = UUID()
    
    public var apiId: Int { seriesId }
    
    public enum CodingKeys: String, CodingKey {
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

    public init(
        number: Int,
        name: String,
        seriesId: Int,
        cover: String?,
        plot: String,
        cast: String,
        director: String?,
        genre: String,
        releaseDate: String,
        lastModified: String,
        rating: String,
        rating5Based: Double,
        backdropPath: [String],
        youtubeTrailer: String?,
        episodeRunTime: String,
        categoryId: String
    ) {
        self.number = number
        self.name = name
        self.seriesId = seriesId
        self.cover = cover
        self.plot = plot
        self.cast = cast
        self.director = director
        self.genre = genre
        self.releaseDate = releaseDate
        self.lastModified = lastModified
        self.rating = rating
        self.rating5Based = rating5Based
        self.backdropPath = backdropPath
        self.youtubeTrailer = youtubeTrailer
        self.episodeRunTime = episodeRunTime
        self.categoryId = categoryId
    }
}

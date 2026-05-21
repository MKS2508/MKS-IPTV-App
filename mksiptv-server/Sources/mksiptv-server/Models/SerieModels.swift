//
//  SerieModels.swift
//  mksiptv-server
//
//  Request/Response models for Series management endpoints.
//

import Vapor
import IPTVCore

// MARK: - Response Models

/// Series list item response
public struct SerieResponse: Content {
    public let id: Int
    public let name: String
    public let cover: String?
    public let plot: String?
    public let genre: String?
    public let rating: String?
    public let categoryId: String?
    public let episodeCount: Int?

    public init(
        id: Int,
        name: String,
        cover: String?,
        plot: String?,
        genre: String?,
        rating: String?,
        categoryId: String?,
        episodeCount: Int?
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.plot = plot
        self.genre = genre
        self.rating = rating
        self.categoryId = categoryId
        self.episodeCount = episodeCount
    }

    /// Create from Serie model
    public init(from serie: Serie) {
        self.id = serie.seriesId
        self.name = serie.name
        self.cover = serie.cover
        self.plot = serie.plot.isEmpty ? nil : serie.plot
        self.genre = serie.genre.isEmpty ? nil : serie.genre
        self.rating = serie.rating.isEmpty ? nil : serie.rating
        self.categoryId = serie.categoryId.isEmpty ? nil : serie.categoryId
        self.episodeCount = nil // Not available in Serie model, requires detail fetch
    }
}

/// Paginated series list response
public struct SeriesListResponse: Content {
    public let series: [SerieResponse]
    public let page: Int
    public let totalPages: Int?
    public let totalItems: Int?

    public init(
        series: [SerieResponse],
        page: Int,
        totalPages: Int? = nil,
        totalItems: Int? = nil
    ) {
        self.series = series
        self.page = page
        self.totalPages = totalPages
        self.totalItems = totalItems
    }
}

/// Series category response
public struct SeriesCategoryResponse: Content {
    public let categoryId: String
    public let categoryName: String
    public let parentId: Int

    public init(categoryId: String, categoryName: String, parentId: Int) {
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.parentId = parentId
    }

    /// Create from SeriesCategory model
    public init(from category: SeriesCategory) {
        self.categoryId = category.categoryId
        self.categoryName = category.categoryName
        self.parentId = category.parentId
    }
}

/// Series detail with seasons
public struct SerieDetailResponse: Content {
    public let id: Int
    public let name: String
    public let cover: String?
    public let plot: String
    public let genre: String
    public let cast: String
    public let director: String?
    public let rating: String?
    public let releaseDate: String
    public let backdropPaths: [String]?
    public let youtubeTrailer: String?
    public let seasons: [SeasonResponse]
    public let episodeCount: Int

    public init(
        id: Int,
        name: String,
        cover: String?,
        plot: String,
        genre: String,
        cast: String,
        director: String?,
        rating: String?,
        releaseDate: String,
        backdropPaths: [String]?,
        youtubeTrailer: String?,
        seasons: [SeasonResponse],
        episodeCount: Int
    ) {
        self.id = id
        self.name = name
        self.cover = cover
        self.plot = plot
        self.genre = genre
        self.cast = cast
        self.rating = rating
        self.director = director
        self.releaseDate = releaseDate
        self.backdropPaths = backdropPaths
        self.youtubeTrailer = youtubeTrailer
        self.seasons = seasons
        self.episodeCount = episodeCount
    }

    /// Create from SerieDetail model
    public init(from detail: SerieDetail, seriesId: Int) {
        self.id = seriesId
        self.name = detail.info.name
        self.cover = detail.info.cover == nil || detail.info.cover!.isEmpty ? nil : detail.info.cover
        self.plot = detail.info.plot
        self.genre = detail.info.genre
        self.cast = detail.info.cast
        self.director = detail.info.director
        self.rating = detail.info.rating.isEmpty ? nil : detail.info.rating
        self.releaseDate = detail.info.releaseDate
        self.backdropPaths = detail.info.backdropPath.isEmpty ? nil : detail.info.backdropPath
        self.youtubeTrailer = detail.info.youtubeTrailer == nil || detail.info.youtubeTrailer!.isEmpty ? nil : detail.info.youtubeTrailer
        self.seasons = detail.seasons.map { SeasonResponse(from: $0) }
        self.episodeCount = detail.seasons.reduce(0) { $0 + $1.episodeCount }
    }
}

/// Season summary response
public struct SeasonResponse: Content {
    public let seasonNumber: Int
    public let name: String
    public let cover: String?
    public let episodeCount: Int
    public let overview: String
    public let airDate: String

    public init(
        seasonNumber: Int,
        name: String,
        cover: String?,
        episodeCount: Int,
        overview: String,
        airDate: String
    ) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.cover = cover
        self.episodeCount = episodeCount
        self.overview = overview
        self.airDate = airDate
    }

    /// Create from SerieDetail.Season model
    public init(from season: SerieDetail.Season) {
        self.seasonNumber = season.seasonNumber
        self.name = season.name
        self.cover = season.cover == nil || season.cover!.isEmpty ? nil : season.cover
        self.episodeCount = season.episodeCount
        self.overview = season.overview
        self.airDate = season.airDate
    }
}

/// Episode response
public struct EpisodeResponse: Content {
    public let episodeNum: Int
    public let title: String
    public let plot: String?
    public let duration: String?
    public let cover: String?
    public let added: String
    public let streamId: Int
    public let duplicateIndex: Int

    public init(
        episodeNum: Int,
        title: String,
        plot: String?,
        duration: String?,
        cover: String?,
        added: String,
        streamId: Int,
        duplicateIndex: Int = 0
    ) {
        self.episodeNum = episodeNum
        self.title = title
        self.plot = plot
        self.duration = duration
        self.cover = cover
        self.added = added
        self.streamId = streamId
        self.duplicateIndex = duplicateIndex
    }

    /// Create from SerieDetail.Episode model
    public init(from episode: SerieDetail.Episode) {
        self.episodeNum = episode.episodeNum
        self.title = episode.displayTitle
        self.plot = episode.info.plot.isEmpty ? nil : episode.info.plot
        self.duration = episode.info.duration.isEmpty ? nil : episode.info.duration
        self.cover = episode.info.movieImage.isEmpty ? nil : episode.info.movieImage
        self.added = episode.added
        self.streamId = Int(episode.id) ?? 0
        self.duplicateIndex = episode.duplicateIndex
    }
}

/// Episodes list response
public struct EpisodesResponse: Content {
    public let seriesId: Int
    public let seasonNumber: Int
    public let episodes: [EpisodeResponse]

    public init(seriesId: Int, seasonNumber: Int, episodes: [EpisodeResponse]) {
        self.seriesId = seriesId
        self.seasonNumber = seasonNumber
        self.episodes = episodes
    }
}

/// Episode stream URL response
public struct EpisodeStreamURLResponse: Content {
    public let seriesId: Int
    public let season: Int
    public let episode: Int
    public let episodeStreamId: Int
    public let url: String
    public let containerExtension: String

    public init(
        seriesId: Int,
        season: Int,
        episode: Int,
        episodeStreamId: Int,
        url: String,
        containerExtension: String
    ) {
        self.seriesId = seriesId
        self.season = season
        self.episode = episode
        self.episodeStreamId = episodeStreamId
        self.url = url
        self.containerExtension = containerExtension
    }
}

// MARK: - Error Responses

/// Series error response
public struct SeriesErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Series Error Types

public enum SeriesError: String {
    case serieNotFound = "SERIE_NOT_FOUND"
    case episodeNotFound = "EPISODE_NOT_FOUND"
    case invalidSeason = "INVALID_SEASON"
    case invalidEpisode = "INVALID_EPISODE"
    case noActiveProfile = "NO_ACTIVE_PROFILE"
}

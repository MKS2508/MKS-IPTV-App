//
//  MediaProtocols.swift
//  mks-multiplatform-iptv
//
//  Unified protocol hierarchy for media types.
//  Eliminates duplicate protocols (LibraryItem, MediaItem) and enums
//  (LibraryMediaType, MediaType) that were scattered across view/viewmodel files.
//

import Foundation

// MARK: - Media Type (Canonical)

/// Single source of truth for media type classification.
/// Replaces the former `LibraryMediaType` (MediaListViewModel) and `MediaType` (DownloadItem).
enum MediaType: Sendable {
    case movie
    case series
}

// MARK: - Title Parseable

/// Protocol for models that carry a raw IPTV title from which metadata can be parsed.
/// Provides default implementations for cleanTitle, year, quality, codec, source, isHDR, is3D
/// so that Movie and Serie don't duplicate these computed properties.
protocol TitleParseable {
    var name: String { get }
}

extension TitleParseable {
    var parsedMetadata: TitleMetadata {
        TitleParser.parse(name)
    }

    var cleanTitle: String { parsedMetadata.cleanTitle }
    var year: String? { parsedMetadata.year }
    var quality: String? { parsedMetadata.quality }
    var codec: String? { parsedMetadata.codec }
    var source: String? { parsedMetadata.source }
    var isHDR: Bool { parsedMetadata.isHDR }
    var is3D: Bool { parsedMetadata.is3D }

    /// Alias used by card views
    var formattedTitle: String { cleanTitle }
}

// MARK: - Library Item (List-Level Protocol)

/// Base protocol for gallery/list views. Both `Movie` and `Serie` conform.
/// Provides the minimum surface needed to render cards, carousels, and the hero banner.
protocol LibraryItem: TitleParseable {
    var streamId: Int { get }
    var categoryId: String { get }
    var coverImage: String? { get }
    var displayRating: String { get }
    var displayRating5Based: Double { get }
    var added: String? { get }
    var mediaType: MediaType { get }

    /// TMDB ID for enriched metadata lookup (nil if not available)
    var tmdbIdInt: Int? { get }
}

// MARK: - Media Detail Item (Detail-Level Protocol)

/// Extended protocol for detail views. `MovieDetail` and `SerieDetail` conform.
/// Adds plot, genre, cast, director, backdrop, trailer, etc. on top of `LibraryItem`.
protocol MediaDetailItem: LibraryItem {
    var detailPlot: String { get }
    var detailGenre: String { get }
    var detailCast: [String] { get }
    var detailDirector: String? { get }
    var detailBackdropPaths: [String] { get }
    var detailYoutubeTrailer: String? { get }
    var detailDurationSeconds: Int { get }
    var detailReleaseDate: String { get }
    var detailPosterURL: String? { get }
}

// MARK: - Movie + LibraryItem

extension Movie: LibraryItem {
    var coverImage: String? { streamIcon }
    var displayRating: String { rating ?? "0" }
    var displayRating5Based: Double { rating5Based ?? 0.0 }
    var mediaType: MediaType { .movie }
    var tmdbIdInt: Int? { tmdbId.flatMap { Int($0) } }
}

// MARK: - Serie + LibraryItem

extension Serie: LibraryItem {
    var streamId: Int { seriesId }
    var coverImage: String? { cover }
    var added: String? { lastModified }
    var displayRating: String { rating }
    var displayRating5Based: Double { rating5Based }
    var mediaType: MediaType { .series }

    /// Serie model does not carry a TMDB ID from the Xtream Codes API.
    /// Enrichment falls back to title+year search in metadata providers.
    var tmdbIdInt: Int? { nil }
}

// MARK: - MovieDetail + MediaDetailItem

extension MovieDetail: TitleParseable, MediaDetailItem {
    // TitleParseable — delegate to the embedded Movie
    var name: String { movieData.name }

    // LibraryItem — delegate to the embedded Movie
    var streamId: Int { movieData.streamId }
    var categoryId: String { movieData.categoryId }
    var coverImage: String? { movieImage }
    var displayRating: String { rating ?? "0" }
    var displayRating5Based: Double { Double(rating ?? "") ?? 0 }
    var added: String? { movieData.added }
    var mediaType: MediaType { .movie }
    var tmdbIdInt: Int? { tmdbId }

    // MediaDetailItem
    var detailPlot: String { plot }
    var detailGenre: String { genre }
    var detailCast: [String] { cast }
    var detailDirector: String? { director }
    var detailBackdropPaths: [String] { backdropPath ?? [] }
    var detailYoutubeTrailer: String? { youtubeTrailer }
    var detailDurationSeconds: Int { durationSecs }
    var detailReleaseDate: String { releaseDate }
    var detailPosterURL: String? { movieImage }
}

// MARK: - SerieDetail + MediaDetailItem

extension SerieDetail: TitleParseable, MediaDetailItem {
    // TitleParseable
    var name: String { info.name }

    // LibraryItem
    var streamId: Int { seriesId }
    var categoryId: String { info.categoryId }
    var coverImage: String? { info.cover }
    var displayRating: String { info.rating }
    var displayRating5Based: Double { info.rating5Based }
    var added: String? { info.lastModified }
    var mediaType: MediaType { .series }
    var tmdbIdInt: Int? { nil }

    // MediaDetailItem
    var detailPlot: String { info.plot }
    var detailGenre: String { info.genre }
    var detailCast: [String] { info.cast.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    var detailDirector: String? { info.director }
    var detailBackdropPaths: [String] { info.backdropPath }
    var detailYoutubeTrailer: String? { info.youtubeTrailer }
    var detailDurationSeconds: Int { 0 }
    var detailReleaseDate: String { info.releaseDate }
    var detailPosterURL: String? { info.cover }
}


//
//  MediaProtocols.swift
//  mks-multiplatform-iptv
//
//  Unified protocol hierarchy for media types.
//  Eliminates duplicate protocols (MediaLibraryItem, MediaItem) and enums
//  (LibraryMediaType, MediaType) that were scattered across view/viewmodel files.
//

import Foundation

// MARK: - Media Type (Canonical)

/// Single source of truth for media type classification.
/// Replaces the former `LibraryMediaType` (MediaListViewModel) and `MediaType` (DownloadItem).
public enum MediaType: String, Sendable, Codable {
    case movie
    case series
}

// MARK: - Title Parseable

/// Protocol for models that carry a raw IPTV title from which metadata can be parsed.
/// Provides default implementations for cleanTitle, year, quality, codec, source, isHDR, is3D
/// so that Movie and Serie don't duplicate these computed properties.
public protocol TitleParseable {
    var name: String { get }
}

extension TitleParseable {
    public var parsedMetadata: TitleMetadata {
        TitleParser.parse(name)
    }

    public var cleanTitle: String { parsedMetadata.cleanTitle }
    public var year: String? { parsedMetadata.year }
    public var quality: String? { parsedMetadata.quality }
    public var codec: String? { parsedMetadata.codec }
    public var source: String? { parsedMetadata.source }
    public var isHDR: Bool { parsedMetadata.isHDR }
    public var is3D: Bool { parsedMetadata.is3D }

    /// Alias used by card views
    public var formattedTitle: String { cleanTitle }
}

// MARK: - Library Item (List-Level Protocol)

/// Base protocol for gallery/list views. Both `Movie` and `Serie` conform.
/// Provides the minimum surface needed to render cards, carousels, and the hero banner.
public protocol MediaLibraryItem: TitleParseable {
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
/// Adds plot, genre, cast, director, backdrop, trailer, etc. on top of `MediaLibraryItem`.
public protocol MediaDetailItem: MediaLibraryItem {
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

// MARK: - Movie + MediaLibraryItem

extension Movie: MediaLibraryItem {
    public var coverImage: String? { streamIcon }
    public var displayRating: String { rating ?? "0" }
    public var displayRating5Based: Double { rating5Based ?? 0.0 }
    public var mediaType: MediaType { .movie }
    public var tmdbIdInt: Int? { tmdbId.flatMap { Int($0) } }
}

// MARK: - Serie + MediaLibraryItem

extension Serie: MediaLibraryItem {
    public var streamId: Int { seriesId }
    public var coverImage: String? { cover }
    public var added: String? { lastModified }
    public var displayRating: String { rating }
    public var displayRating5Based: Double { rating5Based }
    public var mediaType: MediaType { .series }

    /// Serie model does not carry a TMDB ID from the Xtream Codes API.
    /// Enrichment falls back to title+year search in metadata providers.
    public var tmdbIdInt: Int? { nil }
}

// MARK: - MovieDetail + MediaDetailItem

extension MovieDetail: TitleParseable, MediaDetailItem {
    // TitleParseable — delegate to the embedded Movie
    public var name: String { movieData.name }

    // MediaLibraryItem — delegate to the embedded Movie
    public var streamId: Int { movieData.streamId }
    public var categoryId: String { movieData.categoryId }
    public var coverImage: String? { movieImage }
    public var displayRating: String { rating ?? "0" }
    public var displayRating5Based: Double { Double(rating ?? "") ?? 0 }
    public var added: String? { movieData.added }
    public var mediaType: MediaType { .movie }
    public var tmdbIdInt: Int? { tmdbId }

    // MediaDetailItem
    public var detailPlot: String { plot }
    public var detailGenre: String { genre }
    public var detailCast: [String] { cast }
    public var detailDirector: String? { director }
    public var detailBackdropPaths: [String] { backdropPath ?? [] }
    public var detailYoutubeTrailer: String? { youtubeTrailer }
    public var detailDurationSeconds: Int { durationSecs }
    public var detailReleaseDate: String { releaseDate }
    public var detailPosterURL: String? { movieImage }
}

// MARK: - SerieDetail + MediaDetailItem

extension SerieDetail: TitleParseable, MediaDetailItem {
    // TitleParseable
    public var name: String { info.name }

    // MediaLibraryItem
    public var streamId: Int { seriesId }
    public var categoryId: String { info.categoryId }
    public var coverImage: String? { info.cover }
    public var displayRating: String { info.rating }
    public var displayRating5Based: Double { info.rating5Based }
    public var added: String? { info.lastModified }
    public var mediaType: MediaType { .series }
    public var tmdbIdInt: Int? { nil }

    // MediaDetailItem
    public var detailPlot: String { info.plot }
    public var detailGenre: String { info.genre }
    public var detailCast: [String] { info.cast.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    public var detailDirector: String? { info.director }
    public var detailBackdropPaths: [String] { info.backdropPath }
    public var detailYoutubeTrailer: String? { info.youtubeTrailer }
    public var detailDurationSeconds: Int { 0 }
    public var detailReleaseDate: String { info.releaseDate }
    public var detailPosterURL: String? { info.cover }
}

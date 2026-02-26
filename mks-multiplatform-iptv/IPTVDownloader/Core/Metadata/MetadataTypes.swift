import Foundation

// MARK: - Media Type

/// Type of media content for metadata resolution
enum MetadataMediaType: String, Codable, Sendable {
    case movie
    case series
    case episode
}

// MARK: - Metadata Error

/// Errors that can occur during metadata resolution and tagging
enum MetadataError: LocalizedError {
    case providerUnavailable(String)
    case networkError(Error)
    case noResultsFound
    case parsingFailed(String)
    case ffmpegNotAvailable
    case fileNotFound(String)
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let name):
            return "Metadata provider '\(name)' is unavailable"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .noResultsFound:
            return "No metadata results found"
        case .parsingFailed(let detail):
            return "Metadata parsing failed: \(detail)"
        case .ffmpegNotAvailable:
            return "FFmpeg C API not available for metadata writing"
        case .fileNotFound(let path):
            return "File not found at: \(path)"
        case .writeError(let detail):
            return "Failed to write metadata: \(detail)"
        }
    }
}

// MARK: - Tagging Status

/// Tracks the state of metadata enrichment for a download
enum MetadataTaggingStatus: Equatable, Sendable {
    case pending
    case enriching
    case tagging
    case completed
    case failed(String)
    case skipped

    static func == (lhs: MetadataTaggingStatus, rhs: MetadataTaggingStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.enriching, .enriching),
             (.tagging, .tagging),
             (.completed, .completed),
             (.skipped, .skipped):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Scored Metadata Result

/// A metadata result paired with its heuristic match score.
/// Used for presenting multiple candidates to the user for selection.
struct ScoredMetadataResult: Identifiable, Sendable {
    let id = UUID()
    let result: MetadataResult
    let score: Double

    /// Human-readable match percentage (0–100)
    var matchPercentage: Int {
        Int((score * 100).rounded())
    }
}

// MARK: - Editable Metadata

/// Mutable copy of MetadataResult for user editing before tag writing.
///
/// Users can modify any field before the metadata is written to the file.
/// Call ``toMetadataResult()`` to convert back to an immutable result.
struct EditableMetadata: Sendable {
    var title: String
    var originalTitle: String?
    var year: Int?
    var releaseDate: String?
    var genre: [String]
    var plot: String?
    var director: String?
    var cast: [String]
    var rating: Double?
    var ratingSource: String?
    var runtimeMinutes: Int?
    var posterURL: String?
    var backdropURL: String?
    var artworkURLs: [String]
    var tmdbId: Int?
    var imdbId: String?
    var providerName: String
    var confidence: Double
    var mediaType: MetadataMediaType
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeTitle: String?
    var showTitle: String?
    var itunesTrackId: Int?
    var contentAdvisoryRating: String?

    /// Create an editable copy from an immutable MetadataResult.
    init(from result: MetadataResult) {
        self.title = result.title
        self.originalTitle = result.originalTitle
        self.year = result.year
        self.releaseDate = result.releaseDate
        self.genre = result.genre
        self.plot = result.plot
        self.director = result.director
        self.cast = result.cast
        self.rating = result.rating
        self.ratingSource = result.ratingSource
        self.runtimeMinutes = result.runtimeMinutes
        self.posterURL = result.posterURL
        self.backdropURL = result.backdropURL
        self.artworkURLs = result.artworkURLs
        self.tmdbId = result.tmdbId
        self.imdbId = result.imdbId
        self.providerName = result.providerName
        self.confidence = result.confidence
        self.mediaType = result.mediaType
        self.seasonNumber = result.seasonNumber
        self.episodeNumber = result.episodeNumber
        self.episodeTitle = result.episodeTitle
        self.showTitle = result.showTitle
        self.itunesTrackId = result.itunesTrackId
        self.contentAdvisoryRating = result.contentAdvisoryRating
    }

    /// Convert the edited metadata back to an immutable MetadataResult.
    func toMetadataResult() -> MetadataResult {
        MetadataResult(
            title: title,
            originalTitle: originalTitle,
            year: year,
            releaseDate: releaseDate,
            genre: genre,
            plot: plot,
            director: director,
            cast: cast,
            rating: rating,
            ratingSource: ratingSource,
            runtimeMinutes: runtimeMinutes,
            posterURL: posterURL,
            backdropURL: backdropURL,
            artworkURLs: artworkURLs,
            tmdbId: tmdbId,
            imdbId: imdbId,
            providerName: providerName + " (edited)",
            confidence: confidence,
            mediaType: mediaType,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: episodeTitle,
            showTitle: showTitle,
            itunesTrackId: itunesTrackId,
            contentAdvisoryRating: contentAdvisoryRating
        )
    }
}

// MARK: - Metadata Search Query

/// Input query for metadata provider searches
struct MetadataSearchQuery: Sendable {
    let title: String
    let year: Int?
    let tmdbId: Int?
    let genre: String?
    let runtimeMinutes: Int?
    let mediaType: MetadataMediaType
    let seasonNumber: Int?
    let episodeNumber: Int?
    let showTitle: String?

    init(
        title: String,
        year: Int? = nil,
        tmdbId: Int? = nil,
        genre: String? = nil,
        runtimeMinutes: Int? = nil,
        mediaType: MetadataMediaType = .movie,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        showTitle: String? = nil
    ) {
        self.title = title
        self.year = year
        self.tmdbId = tmdbId
        self.genre = genre
        self.runtimeMinutes = runtimeMinutes
        self.mediaType = mediaType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.showTitle = showTitle
    }
}

// MARK: - Metadata Result

/// Standardized metadata result from any provider, with a confidence score
struct MetadataResult: Codable, Sendable {
    let title: String
    let originalTitle: String?
    let year: Int?
    let releaseDate: String?
    let genre: [String]
    let plot: String?
    let director: String?
    let cast: [String]
    let rating: Double?
    let ratingSource: String?
    let runtimeMinutes: Int?
    let posterURL: String?
    let backdropURL: String?
    let artworkURLs: [String]
    let tmdbId: Int?
    let imdbId: String?
    let providerName: String
    let confidence: Double
    let mediaType: MetadataMediaType

    // Series-specific
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let showTitle: String?

    // iTunes-specific
    let itunesTrackId: Int?
    let contentAdvisoryRating: String?

    init(
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil,
        releaseDate: String? = nil,
        genre: [String] = [],
        plot: String? = nil,
        director: String? = nil,
        cast: [String] = [],
        rating: Double? = nil,
        ratingSource: String? = nil,
        runtimeMinutes: Int? = nil,
        posterURL: String? = nil,
        backdropURL: String? = nil,
        artworkURLs: [String] = [],
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        providerName: String,
        confidence: Double,
        mediaType: MetadataMediaType,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeTitle: String? = nil,
        showTitle: String? = nil,
        itunesTrackId: Int? = nil,
        contentAdvisoryRating: String? = nil
    ) {
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.releaseDate = releaseDate
        self.genre = genre
        self.plot = plot
        self.director = director
        self.cast = cast
        self.rating = rating
        self.ratingSource = ratingSource
        self.runtimeMinutes = runtimeMinutes
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.artworkURLs = artworkURLs
        self.tmdbId = tmdbId
        self.imdbId = imdbId
        self.providerName = providerName
        self.confidence = confidence
        self.mediaType = mediaType
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeTitle = episodeTitle
        self.showTitle = showTitle
        self.itunesTrackId = itunesTrackId
        self.contentAdvisoryRating = contentAdvisoryRating
    }
}

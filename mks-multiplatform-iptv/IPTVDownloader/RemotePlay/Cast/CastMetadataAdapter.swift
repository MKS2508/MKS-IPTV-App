//
//  CastMetadataAdapter.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Google Cast metadata adapter placeholder
//

import Foundation

/// Converts MetadataResult to Google Cast media metadata format.
///
/// ## Status
/// This is a **placeholder** for future Cast SDK integration.
///
/// ## Implementation Notes
/// When implementing Cast support, this adapter will:
/// 1. Convert MetadataResult to GCKMediaMetadata
/// 2. Add appropriate metadata types (movie, TV series)
/// 3. Include images for poster artwork
/// 4. Handle Cast-specific metadata requirements
///
/// ## References
/// - [Cast Media Metadata](https://developers.google.com/cast/docs/reference/ios/GCKMediaMetadata)
///
enum CastMetadataAdapter {

    // MARK: - Constants

    /// Cast media type for movies.
    private static let castMovieType = "movie"

    /// Cast media type for TV series.
    private static let castTVSeriesType = "tvseries"

    // MARK: - Metadata Building

    /// Build Cast media metadata from app metadata.
    /// - Parameters:
    ///   - metadata: App media metadata
    ///   - contentURL: The URL of the content being cast
    ///   - duration: Optional content duration in seconds
    /// - Returns: Cast-compatible metadata dictionary
    ///
    /// ## Note
    /// This returns a dictionary representation for reference.
    /// The actual implementation will return GCKMediaMetadata.
    static func buildMetadata(
        from metadata: MetadataResult?,
        contentURL: URL,
        duration: Double?
    ) -> [String: Any] {
        var result: [String: Any] = [:]

        guard let metadata = metadata else {
            return result
        }

        // Basic metadata
        result["title"] = formatTitle(from: metadata)

        // Duration (milliseconds for Cast)
        if let duration = duration {
            result["duration"] = Int(duration * 1000)
        }

        // Content type
        result["contentType"] = "video/mp4"

        // Stream type (LIVE vs BUFFERED)
        result["streamType"] = "BUFFERED"

        // Media type (movie vs TV series)
        if metadata.showTitle != nil {
            result["mediaType"] = castTVSeriesType
            result["seriesTitle"] = metadata.showTitle ?? ""

            if let season = metadata.seasonNumber {
                result["seasonNumber"] = season
            }
            if let episode = metadata.episodeNumber {
                result["episodeNumber"] = episode
            }
            if let episodeTitle = metadata.episodeTitle {
                result["episodeTitle"] = episodeTitle
            }
        } else {
            result["mediaType"] = castMovieType
        }

        // Images
        if let posterURL = metadata.posterURL ?? metadata.artworkURLs.first {
            result["posterURL"] = posterURL
        }

        // Additional metadata
        if let overview = metadata.plot {
            result["overview"] = overview
        }

        if let rating = metadata.rating {
            result["rating"] = rating
        }

        if let year = metadata.year {
            result["releaseYear"] = year
        }

        if let director = metadata.director {
            result["director"] = director
        }

        if !metadata.cast.isEmpty {
            result["actors"] = Array(metadata.cast.prefix(5))
        }

        if !metadata.genre.isEmpty {
            result["genres"] = Array(metadata.genre.prefix(3))
        }

        return result
    }

    // MARK: - Content Type

    /// Derive MIME type from URL file extension for Cast LOAD command.
    /// Reuses the same extension-to-MIME mapping as DLNA.
    /// - Parameter url: Content URL.
    /// - Returns: MIME type string (e.g. "video/mp4").
    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        case "ts", "m2ts":
            return "video/mp2t"
        case "mov":
            return "video/quicktime"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        case "webm":
            return "video/webm"
        case "m3u8":
            return "application/x-mpegURL"
        default:
            return "video/mp4"
        }
    }

    // MARK: - Cast LOAD Payload

    /// Build the `metadata` dictionary for a Cast LOAD command.
    /// Returns a dictionary matching the Cast receiver's expected JSON metadata format.
    ///
    /// ```json
    /// {
    ///   "metadataType": 1,
    ///   "title": "Movie Title",
    ///   "images": [{ "url": "https://..." }]
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - metadata: App metadata (title, poster, episode info).
    ///   - contentURL: The URL of the content being cast.
    ///   - duration: Optional content duration in seconds.
    /// - Returns: Dictionary suitable for the `metadata` field of a Cast LOAD media object.
    static func buildCastLoadPayload(
        from metadata: MetadataResult?,
        contentURL: URL,
        duration: Double?
    ) -> [String: Any] {
        var result: [String: Any] = [:]

        let title = formatTitle(from: metadata)
        result["title"] = title
        result["metadataType"] = metadataTypeCode(from: metadata)

        // Series-specific fields
        if let metadata {
            if let showTitle = metadata.showTitle {
                result["seriesTitle"] = showTitle
            }
            if let season = metadata.seasonNumber {
                result["season"] = season
            }
            if let episode = metadata.episodeNumber {
                result["episode"] = episode
            }

            // Images array for poster artwork
            var images: [[String: Any]] = []
            if let posterURL = metadata.posterURL {
                images.append(["url": posterURL])
            } else if let firstArtwork = metadata.artworkURLs.first {
                images.append(["url": firstArtwork])
            }
            if let backdropURL = metadata.backdropURL {
                images.append(["url": backdropURL])
            }
            if !images.isEmpty {
                result["images"] = images
            }

            // Optional subtitle (plot)
            if let plot = metadata.plot {
                result["subtitle"] = String(plot.prefix(200))
            }

            // Release year
            if let year = metadata.year {
                result["releaseDate"] = String(year)
            }
        }

        return result
    }

    // MARK: - Metadata Type Code

    /// Map metadata to Cast metadataType code.
    /// - 0: GENERIC_MEDIA
    /// - 1: MOVIE
    /// - 2: TV_SHOW
    /// - Parameter metadata: App metadata.
    /// - Returns: Integer metadata type code for Cast.
    static func metadataTypeCode(from metadata: MetadataResult?) -> Int {
        guard let metadata else { return 0 }

        if metadata.showTitle != nil {
            return 2 // TV_SHOW
        }
        return 1 // MOVIE
    }

    // MARK: - Title Formatting

    /// Format display title for Cast metadata.
    /// Delegates to DLNAMetadataAdapter.formatTitle for consistent formatting across protocols.
    static func formatTitle(from metadata: MetadataResult?) -> String {
        DLNAMetadataAdapter.formatTitle(from: metadata)
    }
}

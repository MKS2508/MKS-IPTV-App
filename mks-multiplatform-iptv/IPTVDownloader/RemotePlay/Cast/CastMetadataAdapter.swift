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

    // MARK: - Title Formatting

    /// Format display title for Cast metadata.
    /// - Episode: "ShowTitle - S01E03 - EpisodeTitle"
    /// - Series: showTitle
    /// - Movie: title
    static func formatTitle(from metadata: MetadataResult?) -> String {
        guard let metadata = metadata else {
            return "Unknown"
        }

        // Episode with all info
        if let showTitle = metadata.showTitle,
           let season = metadata.seasonNumber,
           let episode = metadata.episodeNumber,
           let episodeTitle = metadata.episodeTitle,
           season > 0, episode > 0 {
            let seasonStr = String(format: "%02d", season)
            let episodeStr = String(format: "%02d", episode)
            return "\(showTitle) - S\(seasonStr)E\(episodeStr) - \(episodeTitle)"
        }

        // Episode with show title only
        if let showTitle = metadata.showTitle,
           let season = metadata.seasonNumber,
           let episode = metadata.episodeNumber,
           season > 0, episode > 0 {
            let seasonStr = String(format: "%02d", season)
            let episodeStr = String(format: "%02d", episode)
            return "\(showTitle) - S\(seasonStr)E\(episodeStr)"
        }

        // Series with show title
        if let showTitle = metadata.showTitle {
            return showTitle
        }

        // Movie title
        return metadata.title ?? "Unknown"
    }
}

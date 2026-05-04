import Foundation
import IPTVCore

/// Protocol that all metadata providers must conform to.
///
/// Each provider queries a single external API and returns
/// standardized ``MetadataResult`` values with confidence scores.
protocol MetadataProvider: Sendable {
    /// Human-readable name of the provider (e.g. "TMDB", "iTunes Search")
    var name: String { get }

    /// Whether this provider is currently configured and ready to use
    func isAvailable() -> Bool

    /// Search for metadata matching the given query.
    ///
    /// Returns an array of results ordered by relevance,
    /// each with a raw confidence score (0.0–1.0).
    func search(query: MetadataSearchQuery) async throws -> [MetadataResult]

    /// Fetch detailed metadata for a known TMDB ID.
    ///
    /// Returns `nil` if this provider does not support ID-based lookup.
    func fetchById(tmdbId: Int, mediaType: MetadataMediaType) async throws -> MetadataResult?
}

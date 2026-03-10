import Foundation

/// Top-level orchestrator for the metadata enrichment pipeline.
///
/// Coordinates provider resolution, artwork download, and FFmpeg tagging.
/// Used both as a post-download hook and for on-demand enrichment in detail views.
actor MetadataEnrichmentService {
    static let shared = MetadataEnrichmentService()

    private let resolver: MetadataResolver
    private let writer: FFmpegMetadataWriter
    private let session: URLSession

    /// TTL for cached metadata results (24 hours — metadata is stable)
    private let cacheTTL: TimeInterval = 86400

    private init() {
        let providers: [any MetadataProvider] = [
            TMDBMetadataProvider(),
            ITunesSearchProvider(),
            TheTVDBMetadataProvider()
        ]
        self.resolver = MetadataResolver(providers: providers)
        self.writer = FFmpegMetadataWriter.shared
        self.session = URLSession.shared
    }

    // MARK: - Full Pipeline

    /// Enrich a downloaded file with metadata.
    ///
    /// 1. Check cache for existing metadata
    /// 2. Resolve best metadata from providers
    /// 3. Download artwork
    /// 4. Write metadata + artwork to file using FFmpeg
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the downloaded file
    ///   - query: Search parameters for metadata resolution
    ///   - progressHandler: Optional callback for status updates
    /// - Returns: The resolved metadata result
    func enrichDownloadedFile(
        at fileURL: URL,
        query: MetadataSearchQuery,
        progressHandler: ((MetadataTaggingStatus) -> Void)? = nil
    ) async throws -> MetadataResult {
        // Check cache first
        let cacheKey = metadataCacheKey(for: query)
        if let cached = getCachedMetadata(key: cacheKey) {
            progressHandler?(.enriching)
            try await writeToFile(fileURL: fileURL, metadata: cached, progressHandler: progressHandler)
            return cached
        }

        // Resolve metadata from providers
        progressHandler?(.enriching)
        guard let result = await resolver.resolve(query: query) else {
            progressHandler?(.failed("No metadata found"))
            throw MetadataError.noResultsFound
        }

        // Cache the result
        cacheMetadata(result, key: cacheKey)

        // Download artwork and write to file
        try await writeToFile(fileURL: fileURL, metadata: result, progressHandler: progressHandler)

        return result
    }

    /// On-demand metadata resolution for detail views (no file writing).
    ///
    /// - Parameter query: Search parameters
    /// - Returns: Best matching metadata, or `nil`
    func fetchMetadata(query: MetadataSearchQuery) async -> MetadataResult? {
        let cacheKey = metadataCacheKey(for: query)
        if let cached = getCachedMetadata(key: cacheKey) {
            return cached
        }

        let result = await resolver.resolve(query: query)
        if let result = result {
            cacheMetadata(result, key: cacheKey)
        }
        return result
    }

    // MARK: - Interactive Flow (User Selects & Edits)

    /// Fetch all metadata candidates from all providers for user selection.
    ///
    /// Returns scored results sorted by match quality. The UI presents these
    /// as selectable cards; the user picks one, optionally edits it, then
    /// calls ``writeChosenMetadata(to:metadata:progressHandler:)`` to commit.
    ///
    /// - Parameter query: Search parameters
    /// - Returns: All scored candidates sorted best-first
    func fetchAllCandidates(query: MetadataSearchQuery) async -> [ScoredMetadataResult] {
        await resolver.resolveAll(query: query)
    }

    /// Write user-chosen (and possibly edited) metadata to a downloaded file.
    ///
    /// This is the second phase of the interactive flow — called after the user
    /// selects and edits a metadata candidate.
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the downloaded file
    ///   - metadata: The user's chosen (and possibly edited) metadata
    ///   - progressHandler: Optional callback for status updates
    func writeChosenMetadata(
        to fileURL: URL,
        metadata: MetadataResult,
        progressHandler: ((MetadataTaggingStatus) -> Void)? = nil
    ) async throws {
        // Cache the chosen result
        let cacheKey = "metadata_\(StringSimilarity.cleanTitle(metadata.title).lowercased().replacingOccurrences(of: " ", with: "_"))_\(metadata.year ?? 0)_\(metadata.tmdbId ?? 0)"
        cacheMetadata(metadata, key: cacheKey)

        try await writeToFile(fileURL: fileURL, metadata: metadata, progressHandler: progressHandler)
    }

    // MARK: - File Writing

    private func writeToFile(
        fileURL: URL,
        metadata: MetadataResult,
        progressHandler: ((MetadataTaggingStatus) -> Void)?
    ) async throws {
        // Download artwork
        var artworkData: Data?
        if let posterURL = metadata.posterURL ?? metadata.artworkURLs.first,
           let url = URL(string: posterURL) {
            artworkData = try? await downloadArtwork(from: url)
        }

        // Write metadata to file
        progressHandler?(.tagging)
        try await writer.writeMetadata(to: fileURL, metadata: metadata, artworkData: artworkData)
        progressHandler?(.completed)
    }

    private func downloadArtwork(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MetadataError.networkError(
                NSError(domain: "ArtworkDownload", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP error downloading artwork"])
            )
        }
        return data
    }

    // MARK: - Cache (uses CacheManager's disk cache)

    private func metadataCacheKey(for query: MetadataSearchQuery) -> String {
        let cleanTitle = StringSimilarity.cleanTitle(query.title)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        return "metadata_\(cleanTitle)_\(query.year ?? 0)_\(query.tmdbId ?? 0)"
    }

    private func getCachedMetadata(key: String) -> MetadataResult? {
        CacheManager.shared.getCachedMetadata(key: key)
    }

    private func cacheMetadata(_ result: MetadataResult, key: String) {
        CacheManager.shared.cacheMetadata(result, key: key)
    }
}

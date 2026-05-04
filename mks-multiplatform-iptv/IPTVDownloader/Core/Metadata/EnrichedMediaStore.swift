import Foundation
import IPTVCore

/// Actor that manages enriched metadata for Movie/Serie items.
///
/// Implements stale-while-revalidate: returns cached data immediately
/// and refreshes in background when stale. Deduplicates in-flight
/// requests so multiple concurrent callers share a single fetch.
///
/// Three-tier lookup:
/// 1. In-memory cache (instant)
/// 2. Disk cache via ``CacheManager`` (fast, survives app restart)
/// 3. Network fetch via ``MetadataEnrichmentService`` (parallel providers)
actor EnrichedMediaStore {
    static let shared = EnrichedMediaStore()

    // MARK: - Types

    /// A cached metadata entry with timestamp for staleness checks.
    struct EnrichedEntry {
        let result: MetadataResult
        let fetchedAt: Date

        /// Entry is considered stale after 1 hour.
        var isStale: Bool {
            Date().timeIntervalSince(fetchedAt) > 3600
        }
    }

    // MARK: - State

    /// In-memory cache keyed by "enriched_{movie|serie}_{id}"
    private var memoryCache: [String: EnrichedEntry] = [:]

    /// In-flight fetch tasks for request deduplication.
    /// Multiple concurrent callers for the same key await the same Task.
    private var inFlightRequests: [String: Task<MetadataResult?, Never>] = [:]

    // MARK: - Public API

    /// Retrieve enriched metadata with stale-while-revalidate semantics.
    ///
    /// - Parameters:
    ///   - item: The library item (Movie or Serie) to enrich
    ///   - tmdbId: Optional TMDB ID for exact lookup (confidence 1.0)
    /// - Returns: Best matching ``MetadataResult``, or `nil` if no providers returned data
    func getEnrichedMetadata(
        for item: any MediaLibraryItem,
        tmdbId: Int? = nil
    ) async -> MetadataResult? {
        let key = cacheKey(for: item)

        // 1. In-memory cache hit
        if let entry = memoryCache[key] {
            if !entry.isStale {
                return entry.result
            }
            // Stale: return immediately, revalidate in background
            Task { await revalidate(key: key, item: item, tmdbId: tmdbId) }
            return entry.result
        }

        // 2. Disk cache hit (CacheManager, 24h TTL)
        if let diskCached = CacheManager.shared.getCachedMetadata(key: key) {
            memoryCache[key] = EnrichedEntry(result: diskCached, fetchedAt: Date())
            return diskCached
        }

        // 3. Network fetch (with dedup)
        return await fetchWithDedup(key: key, item: item, tmdbId: tmdbId)
    }

    /// Invalidate cached metadata for a specific item, forcing a fresh fetch
    /// on the next access.
    func invalidate(for item: any MediaLibraryItem) {
        let key = cacheKey(for: item)
        memoryCache.removeValue(forKey: key)
    }

    /// Batch prefetch metadata for multiple items concurrently.
    ///
    /// Uses a TaskGroup with limited concurrency to avoid overwhelming
    /// metadata providers. Items that already have cached metadata are skipped.
    ///
    /// - Parameters:
    ///   - items: Library items to prefetch metadata for
    ///   - maxConcurrency: Maximum number of concurrent provider requests (default 5)
    func prefetch(
        items: [any MediaLibraryItem],
        maxConcurrency: Int = 5
    ) async {
        // Filter out items already in memory cache
        let uncachedItems = items.filter { memoryCache[cacheKey(for: $0)] == nil }
        guard !uncachedItems.isEmpty else { return }

        // Use limited concurrency to avoid rate limiting
        await withTaskGroup(of: Void.self) { group in
            var launched = 0
            for item in uncachedItems {
                if launched >= maxConcurrency {
                    // Wait for one to finish before launching next
                    await group.next()
                }
                let tmdbId = (item as? Movie)?.tmdbId.flatMap { Int($0) }
                group.addTask {
                    _ = await self.getEnrichedMetadata(for: item, tmdbId: tmdbId)
                }
                launched += 1
            }
        }
    }

    // MARK: - Private

    /// Fetch with deduplication: if a request for the same key is already in-flight,
    /// await the existing Task instead of launching a duplicate.
    private func fetchWithDedup(
        key: String,
        item: any MediaLibraryItem,
        tmdbId: Int?
    ) async -> MetadataResult? {
        // Dedup: reuse in-flight request
        if let existing = inFlightRequests[key] {
            return await existing.value
        }

        let task = Task<MetadataResult?, Never> {
            let query = buildQuery(for: item, tmdbId: tmdbId)
            let result = await MetadataEnrichmentService.shared.fetchMetadata(query: query)
            if let result {
                memoryCache[key] = EnrichedEntry(result: result, fetchedAt: Date())
                CacheManager.shared.cacheMetadata(result, key: key)
            }
            return result
        }

        inFlightRequests[key] = task
        let result = await task.value
        inFlightRequests.removeValue(forKey: key)
        return result
    }

    /// Background revalidation for stale entries.
    /// Does not block the caller — updates cache silently.
    private func revalidate(
        key: String,
        item: any MediaLibraryItem,
        tmdbId: Int?
    ) async {
        // Skip if already revalidating
        guard inFlightRequests[key] == nil else { return }

        let query = buildQuery(for: item, tmdbId: tmdbId)
        if let result = await MetadataEnrichmentService.shared.fetchMetadata(query: query) {
            memoryCache[key] = EnrichedEntry(result: result, fetchedAt: Date())
            CacheManager.shared.cacheMetadata(result, key: key)
        }
    }

    // MARK: - Helpers

    private func cacheKey(for item: any MediaLibraryItem) -> String {
        let type = item.mediaType == .movie ? "movie" : "serie"
        return "enriched_\(type)_\(item.streamId)"
    }

    private func buildQuery(
        for item: any MediaLibraryItem,
        tmdbId: Int?
    ) -> MetadataSearchQuery {
        let parsed = TitleParser.parse(item.name)
        let yearInt = parsed.year.flatMap { Int($0) }
        return MetadataSearchQuery(
            title: parsed.cleanTitle,
            year: yearInt,
            tmdbId: tmdbId,
            genre: nil,
            runtimeMinutes: nil,
            mediaType: item.mediaType == .movie ? .movie : .series
        )
    }
}

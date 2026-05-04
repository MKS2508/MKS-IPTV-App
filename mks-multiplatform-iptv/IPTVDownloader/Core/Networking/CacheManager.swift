import Foundation
import IPTVCore

// MARK: - Cache TTL Configuration

/// Centralized TTL configuration for all cache data types.
///
/// Each type defines two thresholds:
/// - `freshTTL`: Data younger than this is **fresh** (no background refresh needed).
/// - `staleTTL`: Data younger than this is **stale but usable** (return immediately, refresh in background).
///   Data older than `staleTTL` is considered **expired** and is not returned.
enum CacheTTL: String, CaseIterable, Sendable {
    case mediaList
    case mediaDetail
    case metadata
    case epg
    case matchTable
    case categories
    case liveChannels

    var freshTTL: TimeInterval {
        switch self {
        case .mediaList:    return 1800    // 30 minutes
        case .mediaDetail:  return 1800    // 30 minutes
        case .metadata:     return 86400   // 24 hours
        case .epg:          return 14400   // 4 hours
        case .matchTable:   return 14400   // 4 hours
        case .categories:   return 3600    // 1 hour
        case .liveChannels: return 1800    // 30 minutes
        }
    }

    var staleTTL: TimeInterval {
        switch self {
        case .mediaList:    return 86400   // 24 hours
        case .mediaDetail:  return 86400   // 24 hours
        case .metadata:     return 259200  // 72 hours
        case .epg:          return 43200   // 12 hours
        case .matchTable:   return 43200   // 12 hours
        case .categories:   return 172800  // 48 hours
        case .liveChannels: return 86400   // 24 hours
        }
    }

    var displayName: String {
        switch self {
        case .mediaList:    return "Media Lists"
        case .mediaDetail:  return "Media Details"
        case .metadata:     return "Metadata"
        case .epg:          return "EPG"
        case .matchTable:   return "Match Table"
        case .categories:   return "Categories"
        case .liveChannels: return "Live Channels"
        }
    }

    /// File name prefix used to classify cache files by type.
    var keyPrefix: String {
        switch self {
        case .mediaList:    return "media_list_"
        case .mediaDetail:  return "movie_detail_,serie_detail_"
        case .metadata:     return "metadata_,enriched_"
        case .epg:          return "epg_data"
        case .matchTable:   return "epg_match_table"
        case .categories:   return "categories_"
        case .liveChannels: return "live_channels"
        }
    }

    /// Determine the CacheTTL for a given cache file name.
    static func ttlForFile(named name: String) -> CacheTTL? {
        if name.hasPrefix("categories_") { return .categories }
        if name.hasPrefix("live_channels") { return .liveChannels }
        if name.hasPrefix("media_list_") { return .mediaList }
        if name.hasPrefix("movie_detail_") || name.hasPrefix("serie_detail_") { return .mediaDetail }
        if name.hasPrefix("metadata_") || name.hasPrefix("enriched_") { return .metadata }
        if name.hasPrefix("epg_data") { return .epg }
        if name.hasPrefix("epg_match_table") { return .matchTable }
        return nil
    }
}

// MARK: - Cache Result (SWR)

/// Result of a stale-while-revalidate cache lookup.
///
/// Contains the deserialized value plus staleness metadata so callers
/// can decide whether to trigger a background refresh.
struct CacheResult<T> {
    let value: T
    let age: TimeInterval
    let isStale: Bool
    let key: String
}

// MARK: - Cache Statistics

/// Snapshot of cache state for the debug view.
struct CacheStats {
    struct Entry: Identifiable {
        let id: String // file name
        let key: String
        let sizeBytes: Int64
        let age: TimeInterval
        let ttlType: CacheTTL?
        let isStale: Bool
        let isExpired: Bool
    }

    let totalSizeBytes: Int64
    let entries: [Entry]

    var entryCount: Int { entries.count }

    func count(for type: CacheTTL) -> Int {
        entries.filter { $0.ttlType == type }.count
    }

    func freshCount(for type: CacheTTL) -> Int {
        entries.filter { $0.ttlType == type && !$0.isStale && !$0.isExpired }.count
    }

    func staleCount(for type: CacheTTL) -> Int {
        entries.filter { $0.ttlType == type && $0.isStale && !$0.isExpired }.count
    }

    func expiredCount(for type: CacheTTL) -> Int {
        entries.filter { $0.ttlType == type && $0.isExpired }.count
    }

    func sizeBytes(for type: CacheTTL) -> Int64 {
        entries.filter { $0.ttlType == type }.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Human-readable total size.
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - CacheManager

class CacheManager {
    static let shared = CacheManager()

    private(set) var cacheDirectory: URL
    private let queue = DispatchQueue(label: "com.iptv.cachemanager", attributes: .concurrent)

    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("IPTVCache")

        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            MKSLog.network.error("Failed to create cache directory: \(error)")
            cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("IPTVCache")
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                MKSLog.network.error("Failed to create temp cache directory: \(error)")
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                cacheDirectory = documentsPath.appendingPathComponent("IPTVCache")
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Cache Keys

    private func movieDetailKey(id: Int) -> String {
        "movie_detail_\(id)"
    }

    private func serieDetailKey(id: Int) -> String {
        "serie_detail_\(id)"
    }

    private func mediaListKey(type: String, categoryId: String?) -> String {
        let category = categoryId ?? "all"
        return "media_list_\(type)_\(category)"
    }

    private func categoriesKey(type: String) -> String {
        "categories_\(type)"
    }

    private func liveChannelsKey() -> String {
        "live_channels"
    }

    // MARK: - Stale-While-Revalidate Generic

    /// Read from disk cache with stale-while-revalidate semantics.
    ///
    /// - Returns cached data if within `staleTTL`, annotated with freshness.
    /// - Returns `nil` only if file is missing or older than `staleTTL`.
    /// - Callers should check `result.isStale` to decide on background refresh.
    func getCacheWithStaleness<T: Decodable>(
        key: String,
        type: T.Type,
        ttl: CacheTTL
    ) -> CacheResult<T>? {
        queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let age = Date().timeIntervalSince(modDate)

                // Beyond stale TTL: truly expired, don't return
                if age > ttl.staleTTL { return nil }

                let data = try Data(contentsOf: fileURL)
                let value = try JSONDecoder().decode(type, from: data)

                return CacheResult(
                    value: value,
                    age: age,
                    isStale: age > ttl.freshTTL,
                    key: key
                )
            } catch {
                MKSLog.network.debug("SWR read error for \(key): \(error)")
                return nil
            }
        }
    }

    // MARK: - Typed SWR Convenience Methods

    func getCachedMovieDetailSWR(id: Int) -> CacheResult<MovieDetail>? {
        getCacheWithStaleness(key: movieDetailKey(id: id), type: MovieDetail.self, ttl: .mediaDetail)
    }

    func getCachedSerieDetailSWR(id: Int) -> CacheResult<SerieDetail>? {
        getCacheWithStaleness(key: serieDetailKey(id: id), type: SerieDetail.self, ttl: .mediaDetail)
    }

    func getCachedMoviesSWR(categoryId: String? = nil) -> CacheResult<[Movie]>? {
        getCacheWithStaleness(
            key: mediaListKey(type: "movies", categoryId: categoryId),
            type: [Movie].self,
            ttl: .mediaList
        )
    }

    func getCachedSeriesSWR(categoryId: String? = nil) -> CacheResult<[Serie]>? {
        getCacheWithStaleness(
            key: mediaListKey(type: "series", categoryId: categoryId),
            type: [Serie].self,
            ttl: .mediaList
        )
    }

    // MARK: - Categories SWR

    func getCachedMovieCategoriesSWR() -> CacheResult<[MovieCategory]>? {
        getCacheWithStaleness(key: categoriesKey(type: "movies"), type: [MovieCategory].self, ttl: .categories)
    }

    func getCachedSeriesCategoriesSWR() -> CacheResult<[SeriesCategory]>? {
        getCacheWithStaleness(key: categoriesKey(type: "series"), type: [SeriesCategory].self, ttl: .categories)
    }

    func getCachedLiveChannelCategoriesSWR() -> CacheResult<[LiveChannelCategory]>? {
        getCacheWithStaleness(key: categoriesKey(type: "live"), type: [LiveChannelCategory].self, ttl: .categories)
    }

    // MARK: - Live Channels SWR

    func getCachedLiveChannelsSWR() -> CacheResult<[LiveChannel]>? {
        getCacheWithStaleness(key: liveChannelsKey(), type: [LiveChannel].self, ttl: .liveChannels)
    }

    // MARK: - Legacy Accessors (Binary TTL — kept for backward compatibility)

    func getCachedMovieDetail(id: Int) -> MovieDetail? {
        getCachedMovieDetailSWR(id: id)?.value
    }

    func getCachedSerieDetail(id: Int) -> SerieDetail? {
        getCachedSerieDetailSWR(id: id)?.value
    }

    func getCachedMovies(categoryId: String? = nil) -> [Movie]? {
        getCachedMoviesSWR(categoryId: categoryId)?.value
    }

    func getCachedSeries(categoryId: String? = nil) -> [Serie]? {
        getCachedSeriesSWR(categoryId: categoryId)?.value
    }

    // MARK: - Write Operations

    func cacheMovieDetail(_ detail: MovieDetail, id: Int) {
        saveCache(detail, key: movieDetailKey(id: id))
    }

    func cacheSerieDetail(_ detail: SerieDetail, id: Int) {
        saveCache(detail, key: serieDetailKey(id: id))
    }

    func cacheMovies(_ movies: [Movie], categoryId: String? = nil) {
        saveCache(movies, key: mediaListKey(type: "movies", categoryId: categoryId))
    }

    func cacheSeries(_ series: [Serie], categoryId: String? = nil) {
        saveCache(series, key: mediaListKey(type: "series", categoryId: categoryId))
    }

    func cacheMovieCategories(_ categories: [MovieCategory]) {
        saveCache(categories, key: categoriesKey(type: "movies"))
    }

    func cacheSeriesCategories(_ categories: [SeriesCategory]) {
        saveCache(categories, key: categoriesKey(type: "series"))
    }

    func cacheLiveChannelCategories(_ categories: [LiveChannelCategory]) {
        saveCache(categories, key: categoriesKey(type: "live"))
    }

    func cacheLiveChannels(_ channels: [LiveChannel]) {
        saveCache(channels, key: liveChannelsKey())
    }

    // MARK: - Generic Cache Operations

    private func saveCache<T: Encodable>(_ object: T, key: String) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).json")

            do {
                let data = try JSONEncoder().encode(object)
                try data.write(to: fileURL)
            } catch {
                MKSLog.network.error("Write error for \(key): \(error)")
            }
        }
    }

    // MARK: - Metadata Cache

    func getCachedMetadata(key: String) -> MetadataResult? {
        getCacheWithStaleness(key: key, type: MetadataResult.self, ttl: .metadata)?.value
    }

    func cacheMetadata(_ result: MetadataResult, key: String) {
        saveCache(result, key: key)
    }

    // MARK: - EPG Cache (Binary PropertyList)

    func getCachedEPG() -> EPGData? {
        queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("epg_data.plist")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let age = Date().timeIntervalSince(modDate)
                if age > CacheTTL.epg.staleTTL { return nil }

                let data = try Data(contentsOf: fileURL)
                return try PropertyListDecoder().decode(EPGData.self, from: data)
            } catch {
                MKSLog.network.debug("EPG plist read error: \(error)")
                return nil
            }
        }
    }

    func cacheEPG(_ data: EPGData) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("epg_data.plist")

            do {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let plistData = try encoder.encode(data)
                try plistData.write(to: fileURL)
            } catch {
                MKSLog.network.error("EPG plist write error: \(error)")
            }

            // Remove legacy JSON cache
            let legacyURL = self.cacheDirectory.appendingPathComponent("epg_data.json")
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    // MARK: - EPG Match Table Cache (Binary PropertyList)

    func getCachedMatchTable() -> [Int: String]? {
        queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("epg_match_table.plist")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                let age = Date().timeIntervalSince(modDate)
                if age > CacheTTL.matchTable.staleTTL { return nil }

                let data = try Data(contentsOf: fileURL)
                let stringKeyed = try PropertyListDecoder().decode([String: String].self, from: data)
                var result: [Int: String] = [:]
                for (key, value) in stringKeyed {
                    if let intKey = Int(key) {
                        result[intKey] = value
                    }
                }
                return result
            } catch {
                MKSLog.network.debug("Match table plist read error: \(error)")
                return nil
            }
        }
    }

    func cacheMatchTable(_ table: [Int: String]) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("epg_match_table.plist")

            do {
                let stringKeyed = Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) })
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(stringKeyed)
                try data.write(to: fileURL)
            } catch {
                MKSLog.network.error("Match table plist write error: \(error)")
            }
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        queue.async(flags: .barrier) {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: self.cacheDirectory, includingPropertiesForKeys: nil
                )
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
                MKSLog.network.info("Cleared all cache (\(files.count) files)")
            } catch {
                MKSLog.network.error("Error clearing cache: \(error)")
            }
        }
    }

    /// Remove files that exceed their type-specific stale TTL.
    ///
    /// Unlike the previous implementation which used a single 1-hour TTL,
    /// this respects each data type's `staleTTL` (e.g. 24h for media, 72h for metadata).
    func clearExpiredCache() {
        queue.async(flags: .barrier) {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: self.cacheDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )
                let now = Date()
                var removedCount = 0

                for file in files {
                    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                    guard let modDate = attrs[.modificationDate] as? Date else { continue }
                    let age = now.timeIntervalSince(modDate)

                    let fileName = file.lastPathComponent
                    let ttl = CacheTTL.ttlForFile(named: fileName)
                    let maxAge = ttl?.staleTTL ?? 3600 // Default 1h for unknown files

                    if age > maxAge {
                        try FileManager.default.removeItem(at: file)
                        removedCount += 1
                    }
                }

                if removedCount > 0 {
                    MKSLog.network.info("Cleared \(removedCount) expired files")
                }
            } catch {
                MKSLog.network.error("Error clearing expired cache: \(error)")
            }
        }
    }

    /// Clear cache files for a specific data type only.
    func clearCache(type: CacheTTL) {
        queue.async(flags: .barrier) {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: self.cacheDirectory, includingPropertiesForKeys: nil
                )
                var removedCount = 0
                for file in files {
                    if CacheTTL.ttlForFile(named: file.lastPathComponent) == type {
                        try FileManager.default.removeItem(at: file)
                        removedCount += 1
                    }
                }
                MKSLog.network.info("Cleared \(removedCount) \(type.displayName) files")
            } catch {
                MKSLog.network.error("Error clearing \(type.displayName) cache: \(error)")
            }
        }
    }

    // MARK: - Cache Info

    func isCached(movieId: Int) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent("\(movieDetailKey(id: movieId)).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func isCached(serieId: Int) -> Bool {
        let fileURL = cacheDirectory.appendingPathComponent("\(serieDetailKey(id: serieId)).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func getCacheAge(movieId: Int) -> TimeInterval? {
        getCacheAge(key: movieDetailKey(id: movieId))
    }

    func getCacheAge(serieId: Int) -> TimeInterval? {
        getCacheAge(key: serieDetailKey(id: serieId))
    }

    private func getCacheAge(key: String) -> TimeInterval? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modDate = attrs[.modificationDate] as? Date {
                return Date().timeIntervalSince(modDate)
            }
        } catch {
            MKSLog.network.debug("Error getting cache age for \(key): \(error)")
        }
        return nil
    }

    // MARK: - Cache Statistics

    /// Compute a snapshot of all cache entries with size, age, and staleness info.
    func getCacheStats() -> CacheStats {
        queue.sync {
            do {
                let files = try FileManager.default.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                let now = Date()
                var totalSize: Int64 = 0
                var entries: [CacheStats.Entry] = []

                for file in files {
                    let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                    let size = (attrs[.size] as? Int64) ?? 0
                    let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
                    let age = now.timeIntervalSince(modDate)

                    let fileName = file.lastPathComponent
                    let keyName = fileName
                        .replacingOccurrences(of: ".json", with: "")
                        .replacingOccurrences(of: ".plist", with: "")
                    let ttl = CacheTTL.ttlForFile(named: fileName)

                    totalSize += size
                    entries.append(CacheStats.Entry(
                        id: fileName,
                        key: keyName,
                        sizeBytes: size,
                        age: age,
                        ttlType: ttl,
                        isStale: ttl.map { age > $0.freshTTL } ?? false,
                        isExpired: ttl.map { age > $0.staleTTL } ?? (age > 3600)
                    ))
                }

                // Sort by most recent first
                entries.sort { $0.age < $1.age }

                return CacheStats(totalSizeBytes: totalSize, entries: entries)
            } catch {
                MKSLog.network.error("Error computing stats: \(error)")
                return CacheStats(totalSizeBytes: 0, entries: [])
            }
        }
    }
}

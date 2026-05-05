//
//  TVCacheManager.swift
//  mks-multiplataforma-tvos-iptv
//
//  Disk-based stale-while-revalidate cache for tvOS.
//  Stores JSON files in Library/Caches/TVIPTVCache/.
//  Actor isolation ensures thread safety for Swift 6 concurrency.
//

import Foundation
import IPTVCore

// MARK: - Cache TTL Configuration

enum TVCacheTTL: Sendable {
    case mediaList      // [Movie], [Serie], [LiveChannel]
    case mediaDetail    // MovieDetail, SerieDetail
    case categories     // [MovieCategory], [SeriesCategory], [LiveChannelCategory]
    case tmdbMeta       // TMDBEnrichment

    var freshTTL: TimeInterval {
        switch self {
        case .mediaList:   return 1_800      // 30 min
        case .mediaDetail: return 1_800      // 30 min
        case .categories:  return 3_600      // 1 hour
        case .tmdbMeta:    return 604_800    // 7 days
        }
    }

    var staleTTL: TimeInterval {
        switch self {
        case .mediaList:   return 86_400     // 24 hours
        case .mediaDetail: return 86_400     // 24 hours
        case .categories:  return 172_800    // 48 hours
        case .tmdbMeta:    return 2_592_000  // 30 days
        }
    }
}

// MARK: - Cache Result (SWR)

/// A cached value with its age and staleness flag.
/// `isStale == true` means the caller should background-refresh.
struct TVCacheResult<T> {
    let value: T
    let age: TimeInterval
    let isStale: Bool
}

// MARK: - TVCacheManager

/// Actor-based disk cache with stale-while-revalidate semantics.
/// All JSON files live in Library/Caches/TVIPTVCache/.
actor TVCacheManager {
    static let shared = TVCacheManager()

    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = paths.first ?? FileManager.default.temporaryDirectory
        cacheDirectory = base.appendingPathComponent("TVIPTVCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        MKSLog.network.debug("TVCacheManager directory: \(cacheDirectory.path)")
    }

    // MARK: - Generic SWR Read / Write

    /// Returns a cached value if it exists and is within staleTTL, with freshness info.
    func get<T: Decodable>(key: String, as type: T.Type = T.self, ttl: TVCacheTTL) -> TVCacheResult<T>? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modDate = (attrs[.modificationDate] as? Date) ?? .distantPast
            let age = Date().timeIntervalSince(modDate)

            guard age <= ttl.staleTTL else { return nil }

            let data = try Data(contentsOf: fileURL)
            let value = try decoder.decode(type, from: data)
            return TVCacheResult(value: value, age: age, isStale: age > ttl.freshTTL)
        } catch {
            MKSLog.network.debug("TVCache read error for \(key): \(error)")
            return nil
        }
    }

    /// Persists a value to disk as JSON.
    func set<T: Encodable>(_ value: T, key: String) {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        do {
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            MKSLog.network.error("TVCache write error for \(key): \(error)")
        }
    }

    // MARK: - Typed Convenience Read Methods

    func cachedMovies() -> TVCacheResult<[Movie]>? {
        get(key: "movies_all", as: [Movie].self, ttl: .mediaList)
    }

    func cachedSeries() -> TVCacheResult<[Serie]>? {
        get(key: "series_all", as: [Serie].self, ttl: .mediaList)
    }

    func cachedLiveChannels() -> TVCacheResult<[LiveChannel]>? {
        get(key: "live_all", as: [LiveChannel].self, ttl: .mediaList)
    }

    func cachedMovieCategories() -> TVCacheResult<[MovieCategory]>? {
        get(key: "categories_movies", as: [MovieCategory].self, ttl: .categories)
    }

    func cachedSeriesCategories() -> TVCacheResult<[SeriesCategory]>? {
        get(key: "categories_series", as: [SeriesCategory].self, ttl: .categories)
    }

    func cachedLiveChannelCategories() -> TVCacheResult<[LiveChannelCategory]>? {
        get(key: "categories_live", as: [LiveChannelCategory].self, ttl: .categories)
    }

    func cachedMovieDetail(id: Int) -> TVCacheResult<MovieDetail>? {
        get(key: "movie_detail_\(id)", as: MovieDetail.self, ttl: .mediaDetail)
    }

    func cachedSerieDetail(id: Int) -> TVCacheResult<SerieDetail>? {
        get(key: "serie_detail_\(id)", as: SerieDetail.self, ttl: .mediaDetail)
    }

    func cachedTMDB(key: String) -> TVCacheResult<TMDBEnrichment>? {
        get(key: key, as: TMDBEnrichment.self, ttl: .tmdbMeta)
    }

    // MARK: - Typed Convenience Write Methods

    func cacheMovies(_ movies: [Movie]) {
        set(movies, key: "movies_all")
    }

    func cacheSeries(_ series: [Serie]) {
        set(series, key: "series_all")
    }

    func cacheLiveChannels(_ channels: [LiveChannel]) {
        set(channels, key: "live_all")
    }

    func cacheMovieCategories(_ categories: [MovieCategory]) {
        set(categories, key: "categories_movies")
    }

    func cacheSeriesCategories(_ categories: [SeriesCategory]) {
        set(categories, key: "categories_series")
    }

    func cacheLiveChannelCategories(_ categories: [LiveChannelCategory]) {
        set(categories, key: "categories_live")
    }

    func cacheMovieDetail(_ detail: MovieDetail, id: Int) {
        set(detail, key: "movie_detail_\(id)")
    }

    func cacheSerieDetail(_ detail: SerieDetail, id: Int) {
        set(detail, key: "serie_detail_\(id)")
    }

    func cacheTMDB(_ enrichment: TMDBEnrichment, key: String) {
        set(enrichment, key: key)
    }

    // MARK: - Maintenance

    /// Removes files that have exceeded their staleTTL. Call once on app launch.
    func clearExpired() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let now = Date()
        var removed = 0

        for file in files {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let modDate = attrs[.modificationDate] as? Date else { continue }

            let age = now.timeIntervalSince(modDate)
            let maxAge = ttlForFile(file.lastPathComponent)?.staleTTL ?? 86_400

            if age > maxAge {
                try? FileManager.default.removeItem(at: file)
                removed += 1
            }
        }

        if removed > 0 {
            MKSLog.network.info("TVCache: cleared \(removed) expired file(s)")
        }
    }

    /// Removes all cached files.
    func clearAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        ) else { return }

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        MKSLog.network.info("TVCache: cleared all \(files.count) file(s)")
    }

    // MARK: - Helpers

    private func ttlForFile(_ fileName: String) -> TVCacheTTL? {
        if fileName.hasPrefix("movies_all") || fileName.hasPrefix("series_all") || fileName.hasPrefix("live_all") {
            return .mediaList
        }
        if fileName.hasPrefix("movie_detail_") || fileName.hasPrefix("serie_detail_") {
            return .mediaDetail
        }
        if fileName.hasPrefix("categories_") {
            return .categories
        }
        if fileName.hasPrefix("tmdb_") {
            return .tmdbMeta
        }
        return nil
    }
}

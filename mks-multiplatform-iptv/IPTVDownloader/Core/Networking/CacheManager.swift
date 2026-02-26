import Foundation

class CacheManager {
    static let shared = CacheManager()
    
    private var cacheDirectory: URL
    private let cacheExpiration: TimeInterval = 3600 // 1 hour
    private let queue = DispatchQueue(label: "com.iptv.cachemanager", attributes: .concurrent)
    
    private init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("IPTVCache")
        
        // Create cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create cache directory: \(error)")
            // Fall back to a temporary directory if cache creation fails
            cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("IPTVCache")
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create temporary cache directory: \(error)")
                // Use app's documents directory as last resort
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                cacheDirectory = documentsPath.appendingPathComponent("IPTVCache")
                try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Cache Keys
    
    private func movieDetailKey(id: Int) -> String {
        return "movie_detail_\(id)"
    }
    
    private func serieDetailKey(id: Int) -> String {
        return "serie_detail_\(id)"
    }
    
    private func mediaListKey(type: String, categoryId: String?) -> String {
        let category = categoryId ?? "all"
        return "media_list_\(type)_\(category)"
    }
    
    // MARK: - Movie Details Cache
    
    func getCachedMovieDetail(id: Int) -> MovieDetail? {
        return getCache(key: movieDetailKey(id: id), type: MovieDetail.self)
    }
    
    func cacheMovieDetail(_ detail: MovieDetail, id: Int) {
        saveCache(detail, key: movieDetailKey(id: id))
    }
    
    // MARK: - Serie Details Cache
    
    func getCachedSerieDetail(id: Int) -> SerieDetail? {
        return getCache(key: serieDetailKey(id: id), type: SerieDetail.self)
    }
    
    func cacheSerieDetail(_ detail: SerieDetail, id: Int) {
        saveCache(detail, key: serieDetailKey(id: id))
    }
    
    // MARK: - Media List Cache
    
    func getCachedMovies(categoryId: String? = nil) -> [Movie]? {
        return getCache(key: mediaListKey(type: "movies", categoryId: categoryId), type: [Movie].self)
    }
    
    func cacheMovies(_ movies: [Movie], categoryId: String? = nil) {
        saveCache(movies, key: mediaListKey(type: "movies", categoryId: categoryId))
    }
    
    func getCachedSeries(categoryId: String? = nil) -> [Serie]? {
        return getCache(key: mediaListKey(type: "series", categoryId: categoryId), type: [Serie].self)
    }
    
    func cacheSeries(_ series: [Serie], categoryId: String? = nil) {
        saveCache(series, key: mediaListKey(type: "series", categoryId: categoryId))
    }
    
    // MARK: - Generic Cache Operations
    
    private func getCache<T: Decodable>(key: String, type: T.Type) -> T? {
        return queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > cacheExpiration {
                        // Cache is expired
                        return nil
                    }
                }
                
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode(type, from: data)
            } catch {
                print("Cache read error for key \(key): \(error)")
                return nil
            }
        }
    }
    
    private func saveCache<T: Encodable>(_ object: T, key: String) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).json")
            
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(object)
                try data.write(to: fileURL)
            } catch {
                print("Cache write error for key \(key): \(error)")
            }
        }
    }
    
    // MARK: - Metadata Cache

    /// Longer TTL for metadata (24 hours) since it's more stable than content lists
    private let metadataCacheExpiration: TimeInterval = 86400

    func getCachedMetadata(key: String) -> MetadataResult? {
        return queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > metadataCacheExpiration {
                        return nil
                    }
                }

                let data = try Data(contentsOf: fileURL)
                return try JSONDecoder().decode(MetadataResult.self, from: data)
            } catch {
                print("Metadata cache read error for key \(key): \(error)")
                return nil
            }
        }
    }

    func cacheMetadata(_ result: MetadataResult, key: String) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("\(key).json")

            do {
                let data = try JSONEncoder().encode(result)
                try data.write(to: fileURL)
            } catch {
                print("Metadata cache write error for key \(key): \(error)")
            }
        }
    }

    // MARK: - EPG Cache (Binary PropertyList)

    /// Longer TTL for EPG data (4 hours) since it changes less frequently
    private let epgCacheExpiration: TimeInterval = 14400

    func getCachedEPG() -> EPGData? {
        return queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("epg_data.plist")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > epgCacheExpiration {
                        return nil
                    }
                }

                let data = try Data(contentsOf: fileURL)
                let decoder = PropertyListDecoder()
                return try decoder.decode(EPGData.self, from: data)
            } catch {
                print("EPG plist cache read error: \(error)")
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
                print("EPG plist cache write error: \(error)")
            }

            // Remove legacy JSON cache if it exists
            let legacyURL = self.cacheDirectory.appendingPathComponent("epg_data.json")
            try? FileManager.default.removeItem(at: legacyURL)
        }
    }

    // MARK: - EPG Match Table Cache (Binary PropertyList)

    /// TTL for match table (4 hours) — same as EPG data
    private let matchTableCacheExpiration: TimeInterval = 14400

    func getCachedMatchTable() -> [Int: String]? {
        return queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("epg_match_table.plist")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > matchTableCacheExpiration {
                        return nil
                    }
                }

                let data = try Data(contentsOf: fileURL)
                let decoder = PropertyListDecoder()
                // PropertyList keys must be strings, so decode as [String: String] and convert
                let stringKeyed = try decoder.decode([String: String].self, from: data)
                var result: [Int: String] = [:]
                for (key, value) in stringKeyed {
                    if let intKey = Int(key) {
                        result[intKey] = value
                    }
                }
                return result
            } catch {
                print("Match table plist cache read error: \(error)")
                return nil
            }
        }
    }

    func cacheMatchTable(_ table: [Int: String]) {
        queue.async(flags: .barrier) {
            let fileURL = self.cacheDirectory.appendingPathComponent("epg_match_table.plist")

            do {
                // Convert Int keys to String for PropertyList compatibility
                let stringKeyed = Dictionary(uniqueKeysWithValues: table.map { (String($0.key), $0.value) })
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(stringKeyed)
                try data.write(to: fileURL)
            } catch {
                print("Match table plist cache write error: \(error)")
            }
        }
    }

    // MARK: - Generic Cache with Custom TTL

    private func getCache<T: Decodable>(key: String, type: T.Type, expiration: TimeInterval) -> T? {
        return queue.sync {
            let fileURL = cacheDirectory.appendingPathComponent("\(key).json")

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }

            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    let age = Date().timeIntervalSince(modificationDate)
                    if age > expiration {
                        return nil
                    }
                }

                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                return try decoder.decode(type, from: data)
            } catch {
                print("Cache read error for key \(key): \(error)")
                return nil
            }
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        queue.async(flags: .barrier) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: nil)
                for file in files {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                print("Error clearing cache: \(error)")
            }
        }
    }
    
    func clearExpiredCache() {
        queue.async(flags: .barrier) {
            do {
                let files = try FileManager.default.contentsOfDirectory(at: self.cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
                let now = Date()
                
                for file in files {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    if let modificationDate = attributes[.modificationDate] as? Date {
                        let age = now.timeIntervalSince(modificationDate)
                        if age > self.cacheExpiration {
                            try FileManager.default.removeItem(at: file)
                        }
                    }
                }
            } catch {
                print("Error clearing expired cache: \(error)")
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
        return getCacheAge(key: movieDetailKey(id: movieId))
    }
    
    func getCacheAge(serieId: Int) -> TimeInterval? {
        return getCacheAge(key: serieDetailKey(id: serieId))
    }
    
    private func getCacheAge(key: String) -> TimeInterval? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                return Date().timeIntervalSince(modificationDate)
            }
        } catch {
            print("Error getting cache age for key \(key): \(error)")
        }
        
        return nil
    }
}

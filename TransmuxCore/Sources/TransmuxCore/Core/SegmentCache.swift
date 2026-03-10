import Foundation

// MARK: - Segment LRU Cache

/// Thread-safe LRU cache for fully-rewritten HLS segment data (post-tfdt rewrite).
///
/// When TransmuxServer serves a segment, the moof+mdat bytes (with patched tfdt
/// timestamps) are stored here. On subsequent requests for the same segment
/// (e.g., backward seek to a previously-visited position), the cache returns
/// the data instantly — no pipeline involvement, no av_seek_frame, no polling.
///
/// Uses NSLock (not actor) for synchronous access from `nonisolated` contexts
/// in TransmuxServer's handleGetSegment method.
public final class SegmentCache {

    // MARK: - Types

    private struct Entry {
        let data: Data
        var lastAccessed: UInt64
    }

    // MARK: - Properties

    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var totalBytes: Int = 0
    private let maxBytes: Int
    private var accessCounter: UInt64 = 0

    // MARK: - Initialization

    /// Create a cache with a maximum size in bytes.
    /// Default: 150MB (~25 segments at typical 5Mbps video, 6s each).
    public init(maxBytes: Int = 150 * 1024 * 1024) {
        self.maxBytes = maxBytes
    }

    // MARK: - Public API

    /// Retrieve cached segment data. Returns nil on miss.
    /// Updates LRU access counter on hit.
    public func get(segmentIndex: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = entries[segmentIndex] else { return nil }
        accessCounter += 1
        entry.lastAccessed = accessCounter
        entries[segmentIndex] = entry
        return entry.data
    }

    /// Store segment data. Evicts LRU entries if over capacity.
    public func put(segmentIndex: Int, data: Data) {
        guard data.count > 0 else { return }
        guard data.count <= maxBytes else { return }

        lock.lock()
        defer { lock.unlock() }

        // Remove existing entry if re-caching (e.g., after seek produces different data)
        if let existing = entries.removeValue(forKey: segmentIndex) {
            totalBytes -= existing.data.count
        }

        // Evict LRU entries until we have room
        while totalBytes + data.count > maxBytes && !entries.isEmpty {
            evictLRU()
        }

        accessCounter += 1
        entries[segmentIndex] = Entry(data: data, lastAccessed: accessCounter)
        totalBytes += data.count
    }

    /// Clear all cached data. Called on new transmux session.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }

        entries.removeAll()
        totalBytes = 0
        accessCounter = 0
    }

    /// Current cache utilization for diagnostics.
    public var stats: (entryCount: Int, totalBytes: Int, maxBytes: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (entries.count, totalBytes, maxBytes)
    }

    // MARK: - Private

    /// Evict the least recently used entry. Caller must hold lock.
    private func evictLRU() {
        guard let (lruKey, lruEntry) = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) else { return }
        totalBytes -= lruEntry.data.count
        entries.removeValue(forKey: lruKey)
    }
}

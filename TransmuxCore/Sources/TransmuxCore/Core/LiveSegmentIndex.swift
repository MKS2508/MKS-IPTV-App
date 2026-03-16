import Foundation

// MARK: - LiveSegmentIndex

/// Ordered index of all live segments produced during a session.
/// Tracks metadata for each segment to enable future timeshift seeking.
///
/// Every segment ever produced is recorded, even after its file is evicted
/// from disk (`isOnDisk = false`). This allows future timeshift logic to
/// know what content existed and compute time ranges without the file being
/// present. If timeshift retention is extended, the index already has all
/// the metadata needed to generate a seek-back playlist.
///
/// Thread-safe: all access goes through an NSLock.
public struct LiveSegmentIndex {

    // MARK: - Types

    public struct Entry: Sendable {
        /// Global sequence number (monotonically increasing from 0).
        public let sequenceNumber: Int
        /// Segment file path on disk.
        public let filePath: String
        /// Segment duration in seconds (from FFmpeg segment muxer).
        public let duration: Double
        /// Absolute start time in seconds (from session start, based on DTS).
        public let startTime: Double
        /// File size in bytes (for disk usage monitoring).
        public let fileSize: Int64
        /// Whether this segment file is still on disk (not evicted).
        public internal(set) var isOnDisk: Bool

        public init(
            sequenceNumber: Int,
            filePath: String,
            duration: Double,
            startTime: Double,
            fileSize: Int64,
            isOnDisk: Bool = true
        ) {
            self.sequenceNumber = sequenceNumber
            self.filePath = filePath
            self.duration = duration
            self.startTime = startTime
            self.fileSize = fileSize
            self.isOnDisk = isOnDisk
        }
    }

    // MARK: - State

    private var entries: [Entry] = []
    private let lock = NSLock()

    public init() {}

    // MARK: - Mutating API

    /// Append a new segment entry. Must be called with monotonically increasing sequence numbers.
    public mutating func append(_ entry: Entry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    /// Mark a segment as evicted from disk (file deleted).
    /// The entry remains in the index for timeshift metadata.
    public mutating func markEvicted(sequenceNumber: Int) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = entries.firstIndex(where: { $0.sequenceNumber == sequenceNumber }) {
            entries[idx].isOnDisk = false
        }
    }

    /// Mark all segments with sequence number < threshold as evicted.
    public mutating func markEvictedBelow(sequenceNumber threshold: Int) {
        lock.lock()
        defer { lock.unlock() }
        for i in entries.indices where entries[i].sequenceNumber < threshold && entries[i].isOnDisk {
            entries[i].isOnDisk = false
        }
    }

    // MARK: - Query API

    /// Get a specific entry by its position in the array (0-based).
    public func entry(at index: Int) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0 && index < entries.count else { return nil }
        return entries[index]
    }

    /// Get a specific entry by sequence number.
    public func entry(sequenceNumber: Int) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first(where: { $0.sequenceNumber == sequenceNumber })
    }

    /// Return all entries whose time range overlaps [start, end).
    /// An entry overlaps if: entry.startTime + entry.duration > start AND entry.startTime < end.
    public func entriesInTimeRange(start: Double, end: Double) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { entry in
            let entryEnd = entry.startTime + entry.duration
            return entryEnd > start && entry.startTime < end
        }
    }

    /// Return entries still on disk, ordered by sequence number.
    public func entriesOnDisk() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(\.isOnDisk)
    }

    /// The last N entries (for sliding window playlist generation).
    public func lastEntries(_ count: Int) -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, entries.count - count)
        return Array(entries[start...])
    }

    /// Total number of entries (including evicted).
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Number of entries still on disk.
    public var onDiskCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(\.isOnDisk).count
    }

    /// Total bytes of segments still on disk.
    public var onDiskBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(\.isOnDisk).reduce(0) { $0 + $1.fileSize }
    }

    /// Latest time covered (startTime + duration of the last entry).
    /// Returns 0 if no entries exist.
    public var latestTime: Double {
        lock.lock()
        defer { lock.unlock() }
        guard let last = entries.last else { return 0 }
        return last.startTime + last.duration
    }

    /// Earliest time still available on disk.
    /// Returns nil if no entries are on disk.
    public var earliestOnDiskTime: Double? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first(where: \.isOnDisk)?.startTime
    }

    /// The sequence number of the first entry, or 0 if empty.
    public var firstSequenceNumber: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.first?.sequenceNumber ?? 0
    }

    /// The sequence number of the last entry, or -1 if empty.
    public var lastSequenceNumber: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.last?.sequenceNumber ?? -1
    }
}

import Foundation

// MARK: - LiveSegmenter

/// Generates and maintains a live HLS EVENT playlist with a sliding window
/// for live MPEG-TS streams segmented by FFmpeg's segment muxer.
///
/// ## Architecture
/// FFmpeg's segment muxer writes `.ts` segment files to a directory. FFmpeg
/// also generates its own m3u8, but we **discard it**. Instead, LiveSegmenter
/// maintains its own playlist because:
/// - FFmpeg writes a single growing playlist (not sliding window)
/// - We need EVENT type (no `#EXT-X-ENDLIST`) with incrementing `#EXT-X-MEDIA-SEQUENCE`
/// - We need the sliding window to only show the last N segments
/// - We need to keep older segments on disk for future timeshift/DVR
///
/// ## Segment Lifecycle
/// ```
/// 1. FFmpeg segment muxer completes a segment → file appears on disk
/// 2. LiveSegmenter.notifySegmentReady() is called with the file path
/// 3. Segment is registered in the LiveSegmentIndex
/// 4. Playlist is regenerated with the sliding window
/// 5. Old segments beyond retention policy are deleted from disk
/// ```
///
/// ## Playlist Format
/// ```
/// #EXTM3U
/// #EXT-X-VERSION:3
/// #EXT-X-TARGETDURATION:3
/// #EXT-X-MEDIA-SEQUENCE:42
///
/// #EXTINF:2.003,
/// seg_00042.ts
/// #EXTINF:2.001,
/// seg_00043.ts
/// #EXTINF:2.005,
/// seg_00044.ts
/// ```
///
/// Note: No `#EXT-X-PLAYLIST-TYPE:EVENT` is used because EVENT playlists
/// MUST NOT remove segments from the beginning. Since we use a sliding
/// window that drops old segments, we use a standard live playlist instead.
/// AVPlayer detects live mode from the absence of `#EXT-X-ENDLIST`.
public class LiveSegmenter {

    // MARK: - Configuration

    public struct Config: Sendable {
        /// Target segment duration in seconds (matches FFmpeg `segment_time`).
        /// Lower = less latency, higher = better compression efficiency.
        public var segmentDuration: Double

        /// Number of segments visible in the HLS playlist sliding window.
        /// AVPlayer typically needs at least 3 segments to start playback.
        public var windowSize: Int

        /// Maximum number of segments retained on disk (for future timeshift).
        /// Once exceeded, oldest segments are deleted. 0 = unlimited retention.
        /// Default: 300 segments = ~10 minutes at 2s/segment.
        public var maxRetainedSegments: Int

        /// Segment file name pattern (must match FFmpeg `segment_format` output).
        /// Uses C-style format: `%05d` = 5 digits zero-padded.
        public var segmentPattern: String

        public init(
            segmentDuration: Double = 2.0,
            windowSize: Int = 5,
            maxRetainedSegments: Int = 300,
            segmentPattern: String = "seg_%05d.ts"
        ) {
            self.segmentDuration = segmentDuration
            self.windowSize = windowSize
            self.maxRetainedSegments = maxRetainedSegments
            self.segmentPattern = segmentPattern
        }
    }

    // MARK: - Properties

    public let config: Config
    public let outputDir: String
    public let playlistPath: String
    public private(set) var index = LiveSegmentIndex()

    /// Current media sequence number (first segment in the playlist window).
    /// Increments as older segments fall out of the window.
    public private(set) var mediaSequence: Int = 0

    /// Total segments produced since session start.
    public private(set) var totalSegmentsProduced: Int = 0

    /// Whether the live stream has ended (cancellation, error, or EOF).
    public private(set) var isEnded: Bool = false

    /// In-memory playlist data for instant serving (no disk read).
    private var cachedPlaylist: Data?

    private let queue = DispatchQueue(label: "LiveSegmenter.write", qos: .userInitiated)

    // MARK: - Init

    public init(outputDir: String, config: Config = Config()) {
        self.config = config
        self.outputDir = outputDir
        self.playlistPath = (outputDir as NSString).appendingPathComponent("stream.m3u8")

        TransmuxLog.liveSegmenter("Created: dir=\(outputDir), segDur=\(config.segmentDuration)s, window=\(config.windowSize), retention=\(config.maxRetainedSegments)")
    }

    // MARK: - Public API

    /// Called by the remux loop when a new `.ts` segment file is complete on disk.
    /// Registers the segment, regenerates the playlist, and evicts old segments.
    ///
    /// - Parameters:
    ///   - segmentIndex: Zero-based segment index (matches FFmpeg output numbering).
    ///   - filePath: Absolute path to the completed `.ts` file.
    ///   - duration: Segment duration in seconds.
    ///   - startTime: Absolute start time in seconds (from session start).
    public func notifySegmentReady(
        segmentIndex: Int,
        filePath: String,
        duration: Double,
        startTime: Double
    ) {
        queue.sync {
            // Get file size for monitoring
            let fileSize: Int64
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int64 {
                fileSize = size
            } else {
                fileSize = 0
            }

            // Register in the index
            let entry = LiveSegmentIndex.Entry(
                sequenceNumber: segmentIndex,
                filePath: filePath,
                duration: duration,
                startTime: startTime,
                fileSize: fileSize
            )
            index.append(entry)
            totalSegmentsProduced += 1

            // Update media sequence (first segment in the sliding window)
            let totalInIndex = index.count
            if totalInIndex > config.windowSize {
                mediaSequence = segmentIndex - config.windowSize + 1
            }

            // Evict old segments from disk
            evictOldSegments()

            // Regenerate the playlist
            regeneratePlaylist()

            if totalSegmentsProduced == 1 || totalSegmentsProduced == 5 || totalSegmentsProduced % 25 == 0 {
                TransmuxLog.liveSegmenter("seg[\(segmentIndex)] dur=\(String(format: "%.3f", duration))s start=\(String(format: "%.3f", startTime))s size=\(fileSize / 1024)KB total=\(totalSegmentsProduced) onDisk=\(index.onDiskCount)")
            }
        }
    }

    /// Get the current playlist content as Data for HTTP serving.
    /// Returns nil if no playlist has been generated yet.
    public func getPlaylist() -> Data? {
        queue.sync {
            return cachedPlaylist
        }
    }

    /// Mark the live stream as ended. Writes `#EXT-X-ENDLIST` to the playlist
    /// so AVPlayer knows there will be no more segments.
    public func markEnded() {
        queue.sync {
            guard !isEnded else { return }
            isEnded = true
            regeneratePlaylist()
            TransmuxLog.liveSegmenter("Ended: \(totalSegmentsProduced) total segments, latest=\(String(format: "%.1f", index.latestTime))s")
        }
    }

    /// Check if a segment file exists on disk (for TransmuxServer polling).
    public func segmentExistsOnDisk(segmentIndex: Int) -> Bool {
        let fileName = String(format: config.segmentPattern, segmentIndex)
        let path = (outputDir as NSString).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: path)
    }

    /// Get the file path for a segment by index.
    public func segmentFilePath(segmentIndex: Int) -> String {
        let fileName = String(format: config.segmentPattern, segmentIndex)
        return (outputDir as NSString).appendingPathComponent(fileName)
    }

    // MARK: - Private

    /// Evict segments from disk that exceed the retention policy.
    private func evictOldSegments() {
        guard config.maxRetainedSegments > 0 else { return }  // 0 = unlimited

        let onDisk = index.onDiskCount
        guard onDisk > config.maxRetainedSegments else { return }

        let toEvict = onDisk - config.maxRetainedSegments

        // Get the oldest on-disk entries
        let oldEntries = index.entriesOnDisk().prefix(toEvict)
        for entry in oldEntries {
            // Delete file from disk
            try? FileManager.default.removeItem(atPath: entry.filePath)
            index.markEvicted(sequenceNumber: entry.sequenceNumber)
        }

        if !oldEntries.isEmpty {
            let firstEvicted = oldEntries.first!.sequenceNumber
            let lastEvicted = oldEntries.last!.sequenceNumber
            TransmuxLog.liveSegmenter("Evicted seg[\(firstEvicted)..\(lastEvicted)] (\(oldEntries.count) files), onDisk=\(index.onDiskCount)")
        }
    }

    /// Regenerate the EVENT playlist with the current sliding window.
    /// The playlist is written atomically to prevent AVPlayer from reading a partial file.
    /// Also cached in memory for instant serving via `getPlaylist()`.
    private func regeneratePlaylist() {
        let windowEntries = index.lastEntries(config.windowSize)
        guard !windowEntries.isEmpty else { return }

        // Compute target duration (must be >= max segment duration in the playlist, rounded up)
        let maxDuration = windowEntries.map(\.duration).max() ?? config.segmentDuration
        let targetDuration = Int(ceil(maxDuration))

        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:3\n"
        m3u8 += "#EXT-X-TARGETDURATION:\(targetDuration)\n"
        m3u8 += "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)\n"

        for entry in windowEntries {
            let fileName = (entry.filePath as NSString).lastPathComponent
            m3u8 += "\n#EXTINF:\(String(format: "%.3f", entry.duration)),\n"
            m3u8 += "\(fileName)\n"
        }

        if isEnded {
            m3u8 += "\n#EXT-X-ENDLIST\n"
        }

        // Cache in memory for getPlaylist()
        cachedPlaylist = m3u8.data(using: .utf8)

        // Write to disk atomically (temp file → rename)
        let tempPath = playlistPath + ".tmp"
        do {
            try m3u8.write(toFile: tempPath, atomically: false, encoding: .utf8)
            try FileManager.default.moveItem(atPath: tempPath, toPath: playlistPath)
        } catch {
            // Fallback: direct write (still atomic via Foundation)
            try? m3u8.write(toFile: playlistPath, atomically: true, encoding: .utf8)
        }
    }
}

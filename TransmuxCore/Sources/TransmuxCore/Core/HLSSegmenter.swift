import Foundation

// MARK: - HLSSegmenter

/// Generates a static VOD HLS playlist upfront and tracks real fMP4 segments
/// as they are transmuxed, enabling full seeking from the very start of playback.
///
/// ## How it works
/// On `start()`, writes a complete VOD playlist (with `#EXT-X-ENDLIST`) that declares
/// all virtual segments for the full duration using URL-based segment references
/// (`seg_000.mp4`, `seg_001.mp4`, etc.). AVPlayer sees the full duration immediately
/// and allows seeking to any position.
///
/// In parallel, the segmenter scans the growing fMP4 file for moof+mdat box pairs,
/// extracting timing from tfdt atoms to track which byte ranges correspond to which
/// time ranges. TransmuxServer uses this mapping to serve segment data on demand.
///
/// ## Buffered segment approach
/// Each raw moof+mdat pair is buffered until the NEXT pair arrives. This lets
/// us compute accurate duration = (tfdt[N+1] - tfdt[N]) / timescale for every
/// segment, including the first one (which would otherwise have no preceding
/// tfdt to delta from).
///
/// ## MP4 Box Layout (fragmented MP4 with empty_moov)
/// ```
/// [ftyp][moov]                     <- init segment (bytes 0..initSize)
/// [moof][mdat][moof][mdat]...      <- media segments (one moof+mdat = one HLS segment)
/// ```
public class HLSSegmenter {

    // MARK: - Types

    public struct Segment {
        public let index: Int
        public let byteOffset: Int64
        public let byteLength: Int64
        public let duration: Double
        public let startTime: Double       // output decode time in seconds (rebased tfdt)
        public let sourceStartTime: Double // source time in seconds (for virtual segment lookups)
    }

    /// A real moof+mdat fragment with its file location and source timing.
    /// Used by TransmuxServer to read fragment data and rewrite tfdt values
    /// at serve time with the correct source-timeline timestamps.
    public struct RealFragment {
        public let offset: Int64
        public let length: Int64
        public let sourceStartTime: Double
    }

    /// Parsed timing from a moof's first traf: the tfdt value AND which track
    /// it belongs to. Returned by `parseTfdt()` so the scanner can look up the
    /// correct per-track timescale for duration calculations.
    private struct MoofTimingInfo {
        let decodeTime: UInt64
        let trackID: UInt32
    }

    // MARK: - Properties

    public let fmp4Path: String
    public let playlistPath: String
    public let initSegmentSize: Int64
    public let totalDuration: Double
    public let targetSegmentDuration: Double = 6.0
    public private(set) var totalSegmentCount: Int
    public let subtitleTracks: [SubtitleTrackInfo]

    private var segments: [Segment] = []
    private var scanOffset: Int64 = 0

    /// Fallback timescale used when `trackTimescales[trackID]` has no entry.
    /// Set to the lowest track_ID's timescale during moov parsing, or 90000 as default.
    private var timescale: UInt32 = 0

    /// Track ID → timescale mapping extracted from moov. Used by the scanner
    /// for per-track duration calculations and by TransmuxServer for tfdt rewriting.
    public private(set) var trackTimescales: [UInt32: UInt32] = [:]

    private var pendingMoofOffset: Int64 = -1
    private var pendingMoofSize: Int64 = 0
    private var pendingDecodeTime: UInt64 = 0
    private var pendingTrackID: UInt32 = 0
    private var isCompleted = false
    private var maxDuration: Double = 0

    /// The previous complete moof+mdat, waiting for the next tfdt to compute
    /// its accurate duration. Emitted when the following segment arrives.
    /// Includes the trackID so we can look up the correct timescale.
    private var bufferedRawSegment: (byteOffset: Int64, byteLength: Int64, decodeTime: UInt64, trackID: UInt32)?

    /// Source-to-output time offset. After a seek, output timestamps are rebased
    /// to continue monotonically. This offset maps: sourceTime + offset = outputTime.
    /// Updated when the first segment after a seek is detected.
    private var sourceToOutputOffset: Double = 0.0
    /// When a seek occurs, records the target source time so the first post-seek
    /// segment can compute the new sourceToOutputOffset.
    private var pendingSeekSourceTime: Double?

    private var scanTimer: DispatchSourceTimer?
    private let scanQueue = DispatchQueue(label: "HLSSegmenter.scan", qos: .userInitiated)

    // MARK: - Init

    public init(fmp4Path: String, playlistPath: String, initSegmentSize: Int64, duration: Double, subtitleTracks: [SubtitleTrackInfo] = []) {
        self.fmp4Path = fmp4Path
        self.playlistPath = playlistPath
        self.initSegmentSize = initSegmentSize
        self.totalDuration = duration
        self.totalSegmentCount = max(1, Int(ceil(duration / 6.0)))
        self.subtitleTracks = subtitleTracks
        self.scanOffset = initSegmentSize
        TransmuxLog.segmenter("Created: fmp4=\(fmp4Path), playlist=\(playlistPath), initSize=\(initSegmentSize), duration=\(String(format: "%.1f", duration))s, virtualSegments=\(totalSegmentCount), subtitles=\(subtitleTracks.count)")
    }

    // MARK: - Public API

    /// Start scanning the fMP4 file for new segments. Call after the fMP4 header
    /// is flushed to disk.
    public func start() {
        // Parse timescale from the moov atom before starting the scan loop
        parseTimescaleFromMoov()

        // Write the complete VOD playlist with all virtual segments from the start.
        // This is written ONCE and never changes — AVPlayer sees full duration immediately.
        writeVODPlaylist()

        // Scan every 300ms with 200ms initial delay — fast enough that the first
        // segments are detected before AVPlayer times out, but not so fast that
        // we waste CPU on a file that barely changed.
        let timer = DispatchSource.makeTimerSource(queue: scanQueue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.3)
        timer.setEventHandler { [weak self] in
            self?.scanForNewSegments()
        }
        timer.resume()
        scanTimer = timer
        TransmuxLog.segmenter("Started scanning (fallbackTimescale=\(timescale), tracks=\(trackTimescales.count))")
    }

    /// Stop the scanning timer.
    public func stop() {
        scanTimer?.cancel()
        scanTimer = nil
        TransmuxLog.segmenter("Stopped")
    }

    /// Notify the segmenter that a seek discontinuity is about to occur.
    /// Called by the remux loop just before `av_seek_frame` on the input.
    /// Flushes the AVIO buffer and emits the currently buffered segment
    /// with an estimated duration (since the next tfdt will be from the new position).
    /// - Parameter seekTargetTime: The source time (seconds) that the input will seek to.
    /// When true, the next complete moof+mdat is emitted immediately with an estimated
    /// duration instead of being buffered. Reduces post-seek latency by ~one segment duration.
    private var emitNextSegmentImmediately = false

    public func notifySeekDiscontinuity(seekTargetTime: Double) {
        scanQueue.sync {
            self.scanForNewSegments()      // pick up any data flushed before seek
            self.flushBufferedSegment()    // emit buffered segment with estimated duration
            // Reset pending moof state — any partially scanned moof is from before seek
            self.pendingMoofOffset = -1
            self.pendingMoofSize = 0
            self.pendingDecodeTime = 0
            self.pendingTrackID = 0
            // Record the seek target so the first post-seek segment can compute the mapping
            self.pendingSeekSourceTime = seekTargetTime
            // Emit the first post-seek segment immediately (estimated duration)
            // rather than buffering it. Getting data to AVPlayer fast is more
            // important than perfect segment duration after a seek.
            self.emitNextSegmentImmediately = true
        }
    }

    /// Mark the transmux as complete. Flushes the last buffered segment and stops the timer.
    /// No playlist rewrite needed — the VOD playlist was written once on start().
    public func markComplete() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            self.isCompleted = true

            // Final scan to detect any remaining boxes on disk
            self.scanForNewSegments()

            // Flush the last buffered segment (no next tfdt, use average duration)
            self.flushBufferedSegment()

            self.scanTimer?.cancel()
            self.scanTimer = nil

            let lastSrc = self.segments.last.map { String(format: "%.1f", $0.sourceStartTime + $0.duration) } ?? "0"
            TransmuxLog.segmenter("Marked COMPLETE: \(self.segments.count) real segments, latestSrcTime=\(lastSrc)s")
        }
    }

    // MARK: - Moov Parsing (timescale extraction)

    /// Parse the moov atom to extract per-track timescales.
    /// Walks moov → trak* and for each trak extracts track_ID from tkhd
    /// and timescale from mdia → mdhd. Populates `trackTimescales` map.
    /// Sets `self.timescale` as a fallback to the lowest track_ID's timescale.
    private func parseTimescaleFromMoov() {
        guard let handle = FileHandle(forReadingAtPath: fmp4Path) else {
            TransmuxLog.segmenter("WARNING: Cannot open fMP4 to parse moov, using default timescale 90000", level: .warn)
            timescale = 90000
            return
        }
        defer { try? handle.close() }

        var offset: UInt64 = 0
        let fileSize = Self.currentFileSize(fmp4Path)

        while offset < fileSize {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }

            if box.type == "moov" {
                parseTracksInMoov(handle: handle, containerStart: offset + UInt64(box.headerSize), containerEnd: offset + UInt64(box.size))
                break
            }
            offset += UInt64(box.size)
        }

        if trackTimescales.isEmpty {
            timescale = 90000
            TransmuxLog.segmenter("WARNING: Could not parse any track timescales from moov, using default \(timescale)", level: .warn)
        } else {
            // Use the lowest track_ID's timescale as fallback. This is only used when
            // trackTimescales[trackID] misses — the primary path always uses per-track lookup.
            let sorted = trackTimescales.sorted(by: { $0.key < $1.key })
            timescale = sorted.first!.value
            TransmuxLog.segmenter("TRACKS {\(sorted.map { "\($0.key):\($0.value)" }.joined(separator: ","))} fallback=\(timescale)")
        }
    }

    /// Walk moov children to find all trak boxes and extract track_ID + timescale from each.
    private func parseTracksInMoov(handle: FileHandle, containerStart: UInt64, containerEnd: UInt64) {
        var offset = containerStart
        while offset + 8 <= containerEnd {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }
            let boxEnd = offset + UInt64(box.size)
            if boxEnd > containerEnd { break }

            if box.type == "trak" {
                let trackID = parseTrackID(handle: handle, trakStart: offset + UInt64(box.headerSize), trakEnd: boxEnd)
                let ts = findTimescaleInTrak(handle: handle, containerStart: offset + UInt64(box.headerSize), containerEnd: boxEnd)
                if let id = trackID, let scale = ts {
                    trackTimescales[id] = scale
                }
            }
            offset = boxEnd
        }
    }

    /// Parse tkhd box inside a trak to extract track_ID.
    /// tkhd layout: [8-byte header][1-byte version][3-byte flags]
    ///   v0: [4B creation][4B modification][4B track_ID]...
    ///   v1: [8B creation][8B modification][4B track_ID]...
    private func parseTrackID(handle: FileHandle, trakStart: UInt64, trakEnd: UInt64) -> UInt32? {
        var offset = trakStart
        while offset + 8 <= trakEnd {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }
            let boxEnd = offset + UInt64(box.size)
            if boxEnd > trakEnd { break }

            if box.type == "tkhd" {
                guard box.size >= 24 else { return nil }
                do { try handle.seek(toOffset: offset + UInt64(box.headerSize)) } catch { return nil }
                let vfData = handle.readData(ofLength: 4)
                guard vfData.count == 4 else { return nil }
                let version = vfData[0]
                // track_ID offset after version+flags: v0 = 4+4+4=12, v1 = 4+8+8=20
                let trackIDOffset: UInt64 = version == 0
                    ? (offset + UInt64(box.headerSize) + 4 + 8)
                    : (offset + UInt64(box.headerSize) + 4 + 16)
                guard trackIDOffset + 4 <= boxEnd else { return nil }
                do { try handle.seek(toOffset: trackIDOffset) } catch { return nil }
                let idData = handle.readData(ofLength: 4)
                guard idData.count == 4 else { return nil }
                return idData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            }
            offset = boxEnd
        }
        return nil
    }

    /// Recursively find mdhd timescale inside a trak's mdia container.
    private func findTimescaleInTrak(handle: FileHandle, containerStart: UInt64, containerEnd: UInt64) -> UInt32? {
        var offset = containerStart
        while offset + 8 <= containerEnd {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }
            let boxEnd = offset + UInt64(box.size)
            if boxEnd > containerEnd { break }

            switch box.type {
            case "mdia":
                if let ts = findTimescaleInTrak(handle: handle, containerStart: offset + UInt64(box.headerSize), containerEnd: boxEnd) {
                    return ts
                }
            case "mdhd":
                return parseMdhd(handle: handle, boxStart: offset, boxSize: box.size)
            default:
                break
            }
            offset = boxEnd
        }
        return nil
    }

    /// Parse mdhd box to extract timescale.
    /// Layout: [8-byte header][1-byte version][3-byte flags][creation_time][modification_time][timescale][duration]
    private func parseMdhd(handle: FileHandle, boxStart: UInt64, boxSize: Int64) -> UInt32? {
        guard boxSize >= 24 else { return nil }

        do { try handle.seek(toOffset: boxStart + 8) } catch { return nil }
        let fullboxHeader = handle.readData(ofLength: 4)
        guard fullboxHeader.count == 4 else { return nil }

        let version = fullboxHeader[0]
        let timeFieldSize = version == 0 ? 4 : 8
        let skipSize = timeFieldSize * 2
        guard boxSize >= Int64(8 + 4 + skipSize + 4) else { return nil }

        do { try handle.seek(toOffset: boxStart + 8 + 4 + UInt64(skipSize)) } catch { return nil }
        let tsData = handle.readData(ofLength: 4)
        guard tsData.count == 4 else { return nil }

        return tsData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    // MARK: - Segment Scanning

    /// Scan the fMP4 file for new moof+mdat pairs starting from the last known position.
    ///
    /// Uses a one-segment buffer: each complete moof+mdat is stored as
    /// `bufferedRawSegment`. When the NEXT moof+mdat arrives, we compute the
    /// buffered segment's duration from the tfdt delta and emit it.
    ///
    /// Duration calculations use per-track timescale lookup via `trackTimescales[trackID]`,
    /// ensuring the timescale always matches the track whose tfdt was read. Falls back to
    /// `self.timescale` only if the track_ID is not in the map.
    private func scanForNewSegments() {
        let fileSize = Self.currentFileSize(fmp4Path)
        guard fileSize > scanOffset else { return }

        guard let handle = FileHandle(forReadingAtPath: fmp4Path) else { return }
        defer { try? handle.close() }

        var offset = UInt64(scanOffset)
        var newSegmentsFound = false

        while offset + 8 <= fileSize {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }

            let boxEnd = offset + UInt64(box.size)
            guard boxEnd <= fileSize else { break }

            switch box.type {
            case "moof":
                if let timing = parseTfdt(handle: handle, moofStart: offset, moofSize: box.size) {
                    pendingMoofOffset = Int64(offset)
                    pendingMoofSize = Int64(box.size)
                    pendingDecodeTime = timing.decodeTime
                    pendingTrackID = timing.trackID
                } else {
                    // Could not parse tfdt/tfhd — skip this moof
                    pendingMoofOffset = -1
                }

            case "mdat":
                if pendingMoofOffset >= 0 {
                    let rawOffset = pendingMoofOffset
                    let rawSize = pendingMoofSize + Int64(box.size)
                    let rawDecodeTime = pendingDecodeTime
                    let rawTrackID = pendingTrackID

                    // Emit the previously buffered segment using current tfdt for duration.
                    if let buffered = bufferedRawSegment {
                        let duration: Double
                        let startTimeSec: Double

                        // Look up the exact timescale for the buffered segment's track
                        let effectiveTimescale = trackTimescales[buffered.trackID] ?? timescale

                        if effectiveTimescale > 0 {
                            // Cross-track guard: if the buffered and current fragments come
                            // from different tracks, the tfdt delta is meaningless (different
                            // timescale domains). Fall back to average duration.
                            // In practice this never happens with FFmpeg's deterministic
                            // traf ordering, but it makes the code correct by construction.
                            let sameTrack = buffered.trackID == rawTrackID

                            if !sameTrack {
                                if !segments.isEmpty {
                                    duration = segments.map(\.duration).reduce(0, +) / Double(segments.count)
                                } else {
                                    duration = targetSegmentDuration
                                }
                                TransmuxLog.segmenter("Cross-track tfdt: buffered=track\(buffered.trackID) current=track\(rawTrackID), using avg duration=\(String(format: "%.3f", duration))s", level: .warn)
                            } else {
                                let maxDeltaTicks = UInt64(2.0 * targetSegmentDuration * Double(effectiveTimescale))
                                let isBackwardSeek = rawDecodeTime < buffered.decodeTime
                                let dtDelta = isBackwardSeek ? UInt64(0) : (rawDecodeTime - buffered.decodeTime)
                                let isDiscontinuity = isBackwardSeek || dtDelta > maxDeltaTicks

                                if isDiscontinuity {
                                    if !segments.isEmpty {
                                        duration = segments.map(\.duration).reduce(0, +) / Double(segments.count)
                                    } else {
                                        duration = targetSegmentDuration
                                    }
                                    TransmuxLog.segmenter("DISCONTINUITY (safety net): dtDelta=\(dtDelta) ticks, backward=\(isBackwardSeek), est duration=\(String(format: "%.3f", duration))s, rawDT=\(rawDecodeTime) bufferedDT=\(buffered.decodeTime)", level: .warn)
                                } else {
                                    duration = dtDelta > 0 ? Double(dtDelta) / Double(effectiveTimescale) : 0.1
                                }
                            }

                            startTimeSec = Double(buffered.decodeTime) / Double(effectiveTimescale)
                        } else {
                            duration = 1.0
                            startTimeSec = Double(segments.count)
                        }

                        // Compute sourceStartTime: maps rebased output time back to source time
                        let sourceStartTimeSec: Double
                        if let seekTarget = pendingSeekSourceTime {
                            // First segment after a seek: establish the new mapping
                            sourceToOutputOffset = startTimeSec - seekTarget
                            sourceStartTimeSec = seekTarget
                            pendingSeekSourceTime = nil
                        } else {
                            // Normal segment: reverse the mapping
                            sourceStartTimeSec = startTimeSec - sourceToOutputOffset
                        }

                        let segment = Segment(
                            index: segments.count,
                            byteOffset: buffered.byteOffset,
                            byteLength: buffered.byteLength,
                            duration: duration,
                            startTime: startTimeSec,
                            sourceStartTime: sourceStartTimeSec
                        )
                        segments.append(segment)
                        if duration > maxDuration { maxDuration = duration }

                        newSegmentsFound = true
                    }

                    // Buffer the current raw segment for next iteration —
                    // UNLESS this is the first segment after a seek, in which case
                    // emit it immediately with estimated duration to reduce latency.
                    if emitNextSegmentImmediately {
                        emitNextSegmentImmediately = false

                        let effectiveTimescale = trackTimescales[rawTrackID] ?? timescale
                        let estDuration: Double
                        if !segments.isEmpty {
                            estDuration = segments.map(\.duration).reduce(0, +) / Double(segments.count)
                        } else {
                            estDuration = targetSegmentDuration
                        }
                        let startTimeSec = effectiveTimescale > 0
                            ? Double(rawDecodeTime) / Double(effectiveTimescale)
                            : Double(segments.count)

                        let sourceStartTimeSec: Double
                        if let seekTarget = pendingSeekSourceTime {
                            sourceToOutputOffset = startTimeSec - seekTarget
                            sourceStartTimeSec = seekTarget
                            pendingSeekSourceTime = nil
                        } else {
                            sourceStartTimeSec = startTimeSec - sourceToOutputOffset
                        }

                        let segment = Segment(
                            index: segments.count,
                            byteOffset: rawOffset,
                            byteLength: rawSize,
                            duration: estDuration,
                            startTime: startTimeSec,
                            sourceStartTime: sourceStartTimeSec
                        )
                        segments.append(segment)
                        if estDuration > maxDuration { maxDuration = estDuration }
                        newSegmentsFound = true

                        // No buffered segment — next moof+mdat goes back to normal buffer flow
                        bufferedRawSegment = nil
                    } else {
                        bufferedRawSegment = (byteOffset: rawOffset, byteLength: rawSize, decodeTime: rawDecodeTime, trackID: rawTrackID)
                    }

                    pendingMoofOffset = -1
                    pendingMoofSize = 0
                }

            default:
                break
            }

            offset = boxEnd
        }

        scanOffset = Int64(offset)

        if newSegmentsFound && (segments.count == 1 || segments.count == 10 || segments.count % 50 == 0) {
            TransmuxLog.segmenter("\(segments.count) segs scanOff=\(scanOffset)")
        }
    }

    /// Flush the last buffered segment using an estimated duration.
    /// Called by markComplete() after the final scan.
    private func flushBufferedSegment() {
        guard let buffered = bufferedRawSegment else { return }

        // Use average duration of previously emitted segments, or 1.0s fallback
        let duration: Double
        if !segments.isEmpty {
            duration = segments.map(\.duration).reduce(0, +) / Double(segments.count)
        } else {
            duration = 1.0
        }

        let startTimeSec: Double
        let effectiveTimescale = trackTimescales[buffered.trackID] ?? timescale
        if effectiveTimescale > 0 {
            startTimeSec = Double(buffered.decodeTime) / Double(effectiveTimescale)
        } else {
            startTimeSec = Double(segments.count)
        }

        // Compute sourceStartTime using the current mapping
        let sourceStartTimeSec: Double
        if let seekTarget = pendingSeekSourceTime {
            sourceToOutputOffset = startTimeSec - seekTarget
            sourceStartTimeSec = seekTarget
            pendingSeekSourceTime = nil
        } else {
            sourceStartTimeSec = startTimeSec - sourceToOutputOffset
        }

        let segment = Segment(
            index: segments.count,
            byteOffset: buffered.byteOffset,
            byteLength: buffered.byteLength,
            duration: duration,
            startTime: startTimeSec,
            sourceStartTime: sourceStartTimeSec
        )
        segments.append(segment)
        if duration > maxDuration { maxDuration = duration }

        bufferedRawSegment = nil
    }

    // MARK: - tfdt + track_ID Parsing

    /// Parse moof → traf → {tfhd, tfdt} to extract baseMediaDecodeTime AND track_ID.
    ///
    /// Scans the FIRST traf that contains both a tfhd and a tfdt. The track_ID from
    /// tfhd allows the caller to look up the correct per-track timescale for duration
    /// calculations, eliminating the single-timescale assumption.
    private func parseTfdt(handle: FileHandle, moofStart: UInt64, moofSize: Int64) -> MoofTimingInfo? {
        let moofEnd = moofStart + UInt64(moofSize)
        var offset = moofStart + 8  // skip moof header

        while offset + 8 <= moofEnd {
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }
            if box.size < 8 { break }
            let boxEnd = offset + UInt64(box.size)
            if boxEnd > moofEnd { break }

            if box.type == "traf" {
                // Scan traf children for both tfhd (track_ID) and tfdt (decodeTime)
                var trackID: UInt32?
                var decodeTime: UInt64?
                var trafChild = offset + UInt64(box.headerSize)

                while trafChild + 8 <= boxEnd {
                    guard let inner = MP4BoxParser.readBoxHeader(handle: handle, at: trafChild) else { break }
                    if inner.size < 8 { break }
                    let innerEnd = trafChild + UInt64(inner.size)
                    if innerEnd > boxEnd { break }

                    if inner.type == "tfhd" {
                        // tfhd layout: [header][version(1)+flags(3)][track_ID(4)]
                        let idOffset = trafChild + UInt64(inner.headerSize) + 4  // +4 for version+flags
                        if idOffset + 4 <= innerEnd {
                            do { try handle.seek(toOffset: idOffset) } catch { break }
                            let idData = handle.readData(ofLength: 4)
                            if idData.count == 4 {
                                trackID = idData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                            }
                        }
                    } else if inner.type == "tfdt" {
                        // tfdt layout: [header][version(1)+flags(3)][baseMediaDecodeTime]
                        do { try handle.seek(toOffset: trafChild + UInt64(inner.headerSize)) } catch { break }
                        let vfData = handle.readData(ofLength: 4)
                        guard vfData.count == 4 else { break }

                        let version = vfData[0]
                        if version == 1 {
                            let dtData = handle.readData(ofLength: 8)
                            if dtData.count == 8 {
                                decodeTime = dtData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                            }
                        } else {
                            let dtData = handle.readData(ofLength: 4)
                            if dtData.count == 4 {
                                decodeTime = UInt64(dtData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                            }
                        }
                    }

                    trafChild = innerEnd
                }

                // Return if we found both track_ID and decodeTime in this traf
                if let tid = trackID, let dt = decodeTime {
                    return MoofTimingInfo(decodeTime: dt, trackID: tid)
                }
            }

            offset = boxEnd
        }

        return nil
    }

    // MARK: - Public Lookup API

    /// Returns real moof+mdat byte ranges from stream.mp4 that cover the given time range.
    /// The time range is in source time (matching the virtual HLS playlist).
    /// Only returns segments that have actually been transmuxed (scanned from the file).
    /// Returns empty array if those segments haven't been transmuxed yet.
    ///
    /// Each real fragment is assigned to exactly ONE virtual segment based on its START time
    /// (snappedStart >= start && snappedStart < end). This prevents duplicate moof+mdat fragments
    /// across consecutive segments, which causes AVPlayer CMTimebase errors from seeing
    /// the same tfdt decode timestamps twice.
    ///
    /// A small epsilon (0.01s) is added to sourceStartTime before comparison to handle
    /// floating-point boundary cases: keyframe DTS values are often N*period - 1/timescale
    /// (e.g., 11.999s instead of 12.0s), so without the snap they'd be assigned to the
    /// previous virtual segment, causing data loss when that segment has already been served.
    public func realSegments(inTimeRange start: Double, end: Double) -> [RealFragment] {
        return scanQueue.sync {
            var result: [RealFragment] = []
            for seg in segments {
                // Snap forward by 0.01s to correct for DTS rounding:
                // e.g., srcTime=11.999 snaps to 12.009, correctly assigned to seg [12,18)
                let snapped = seg.sourceStartTime + 0.01
                if snapped >= start && snapped < end {
                    result.append(RealFragment(offset: seg.byteOffset, length: seg.byteLength, sourceStartTime: seg.sourceStartTime))
                }
            }
            return result
        }
    }

    /// The latest source time (seconds) that has been transmuxed.
    public func latestTransmuxedTime() -> Double {
        return scanQueue.sync {
            guard let lastSeg = segments.last else { return 0 }
            return lastSeg.sourceStartTime + lastSeg.duration
        }
    }

    /// Force an immediate fMP4 scan for new segments.
    /// Called by TransmuxServer during polling instead of waiting for the 300ms timer.
    public func triggerScan() {
        scanQueue.sync {
            self.scanForNewSegments()
        }
    }

    /// Latest source time based ONLY on completed segments.
    /// Does NOT include estimated duration for buffered segment - this ensures
    /// the fullness gate only passes when segments are 100% complete on disk.
    /// This prevents serving incomplete segments that cause A/V artifacts.
    public func latestBufferedSourceTime() -> Double {
        return scanQueue.sync {
            self.scanForNewSegments()
            guard let last = self.segments.last else { return 0 }
            return last.sourceStartTime + last.duration
        }
    }

    // MARK: - Playlist Generation

    /// Write the complete VOD playlist with all virtual segments declared upfront.
    /// Written ONCE on start() and never changed. All segment durations are 6.0s
    /// except the last which covers the remainder. AVPlayer sees full duration immediately.
    private func writeVODPlaylist() {
        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:7\n"
        m3u8 += "#EXT-X-TARGETDURATION:6\n"
        m3u8 += "#EXT-X-MEDIA-SEQUENCE:0\n"
        m3u8 += "#EXT-X-PLAYLIST-TYPE:VOD\n"
        m3u8 += "#EXT-X-INDEPENDENT-SEGMENTS\n"
        m3u8 += "#EXT-X-MAP:URI=\"init.mp4\"\n"

        for i in 0..<totalSegmentCount {
            let segStart = Double(i) * targetSegmentDuration
            let segDuration: Double
            if i == totalSegmentCount - 1 {
                segDuration = max(totalDuration - segStart, 0.001)
            } else {
                segDuration = targetSegmentDuration
            }
            m3u8 += "\n#EXTINF:\(String(format: "%.3f", segDuration)),\n"
            m3u8 += "seg_\(String(format: "%03d", i)).mp4\n"
        }

        m3u8 += "\n#EXT-X-ENDLIST\n"

        do {
            try m3u8.write(toFile: playlistPath, atomically: true, encoding: .utf8)
            TransmuxLog.segmenter("Created VOD playlist with \(totalSegmentCount) segments, duration \(String(format: "%.1f", totalDuration))s")
        } catch {
            TransmuxLog.segmenter("ERROR: Failed to write VOD playlist: \(error)", level: .error)
        }
    }

    // MARK: - Master Playlist (multivariant with subtitles)

    /// Write a multivariant (master) HLS playlist that references the media playlist
    /// and any subtitle renditions via `#EXT-X-MEDIA:TYPE=SUBTITLES`.
    ///
    /// Only call when `subtitleTracks` is non-empty. When there are no subtitles,
    /// the single `stream.m3u8` media playlist is used directly as the entry point.
    public func writeMasterPlaylist(to path: String) {
        guard !subtitleTracks.isEmpty else { return }

        let playlistDir = (path as NSString).deletingLastPathComponent

        var m3u8 = "#EXTM3U\n"

        // Subtitle renditions
        for (idx, sub) in subtitleTracks.enumerated() {
            let isDefault = idx == 0 && !sub.isForced ? "YES" : "NO"
            let autoSelect = isDefault == "YES" ? "YES" : "NO"
            let forced = sub.isForced ? "YES" : "NO"
            let name = sub.title.isEmpty ? sub.language.uppercased() : sub.title
            let subPlaylistName = "sub_\(sub.language)_\(idx).m3u8"

            m3u8 += "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"\(name)\","
            m3u8 += "DEFAULT=\(isDefault),AUTOSELECT=\(autoSelect),FORCED=\(forced),"
            m3u8 += "LANGUAGE=\"\(sub.language)\",URI=\"\(subPlaylistName)\"\n"

            // Write the per-subtitle m3u8 playlist (single segment covering full duration)
            writeSubtitlePlaylist(
                to: (playlistDir as NSString).appendingPathComponent(subPlaylistName),
                vttFileName: sub.vttFileName
            )
        }

        m3u8 += "\n"
        // Stream variant pointing to the media playlist, referencing subtitle group
        m3u8 += "#EXT-X-STREAM-INF:BANDWIDTH=5000000,SUBTITLES=\"subs\"\n"
        m3u8 += "stream.m3u8\n"

        do {
            try m3u8.write(toFile: path, atomically: true, encoding: .utf8)
            TransmuxLog.segmenter("Wrote master playlist with \(subtitleTracks.count) subtitle tracks")
        } catch {
            TransmuxLog.segmenter("ERROR: Failed to write master playlist: \(error)", level: .error)
        }
    }

    /// Write a simple subtitle m3u8 playlist with a single segment covering the full duration.
    private func writeSubtitlePlaylist(to path: String, vttFileName: String) {
        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:7\n"
        m3u8 += "#EXT-X-TARGETDURATION:\(Int(ceil(totalDuration)))\n"
        m3u8 += "#EXT-X-PLAYLIST-TYPE:VOD\n"
        m3u8 += "\n"
        m3u8 += "#EXTINF:\(String(format: "%.3f", totalDuration)),\n"
        m3u8 += "\(vttFileName)\n"
        m3u8 += "\n"
        m3u8 += "#EXT-X-ENDLIST\n"

        do {
            try m3u8.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            TransmuxLog.segmenter("ERROR: Failed to write subtitle playlist \(path): \(error)", level: .error)
        }
    }

    // MARK: - Helpers

    private static func currentFileSize(_ path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }
}

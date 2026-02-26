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
class HLSSegmenter {

    // MARK: - Types

    struct Segment {
        let index: Int
        let byteOffset: Int64
        let byteLength: Int64
        let duration: Double
        let startTime: Double       // output decode time in seconds (rebased tfdt)
        let sourceStartTime: Double // source time in seconds (for virtual segment lookups)
    }

    // MARK: - Properties

    let fmp4Path: String
    let playlistPath: String
    let initSegmentSize: Int64
    let totalDuration: Double
    let targetSegmentDuration: Double = 6.0
    private(set) var totalSegmentCount: Int

    private var segments: [Segment] = []
    private var scanOffset: Int64 = 0
    private var timescale: UInt32 = 0
    private var pendingMoofOffset: Int64 = -1
    private var pendingMoofSize: Int64 = 0
    private var pendingDecodeTime: UInt64 = 0
    private var isCompleted = false
    private var maxDuration: Double = 0

    /// The previous complete moof+mdat, waiting for the next tfdt to compute
    /// its accurate duration. Emitted when the following segment arrives.
    private var bufferedRawSegment: (byteOffset: Int64, byteLength: Int64, decodeTime: UInt64)?

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

    init(fmp4Path: String, playlistPath: String, initSegmentSize: Int64, duration: Double) {
        self.fmp4Path = fmp4Path
        self.playlistPath = playlistPath
        self.initSegmentSize = initSegmentSize
        self.totalDuration = duration
        self.totalSegmentCount = max(1, Int(ceil(duration / 6.0)))
        self.scanOffset = initSegmentSize
        print("[HLSSegmenter] Created: fmp4=\(fmp4Path), playlist=\(playlistPath), initSize=\(initSegmentSize), duration=\(String(format: "%.1f", duration))s, virtualSegments=\(totalSegmentCount)")
    }

    // MARK: - Public API

    /// Start scanning the fMP4 file for new segments. Call after the fMP4 header
    /// is flushed to disk.
    func start() {
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
        print("[HLSSegmenter] Started scanning (timescale=\(timescale))")
    }

    /// Stop the scanning timer.
    func stop() {
        scanTimer?.cancel()
        scanTimer = nil
        print("[HLSSegmenter] Stopped")
    }

    /// Notify the segmenter that a seek discontinuity is about to occur.
    /// Called by the remux loop just before `av_seek_frame` on the input.
    /// Flushes the AVIO buffer and emits the currently buffered segment
    /// with an estimated duration (since the next tfdt will be from the new position).
    /// - Parameter seekTargetTime: The source time (seconds) that the input will seek to.
    func notifySeekDiscontinuity(seekTargetTime: Double) {
        scanQueue.sync {
            let prevSegCount = self.segments.count
            let prevOffset = self.sourceToOutputOffset
            self.scanForNewSegments()      // pick up any data flushed before seek
            self.flushBufferedSegment()    // emit buffered segment with estimated duration
            // Reset pending moof state — any partially scanned moof is from before seek
            self.pendingMoofOffset = -1
            self.pendingMoofSize = 0
            self.pendingDecodeTime = 0
            // Record the seek target so the first post-seek segment can compute the mapping
            self.pendingSeekSourceTime = seekTargetTime
            TransmuxLog.segmenter("Seek discontinuity: target=\(String(format: "%.1f", seekTargetTime))s, segments=\(prevSegCount)->\(self.segments.count), prevSrcToOutOffset=\(String(format: "%.3f", prevOffset)), buffered=\(self.bufferedRawSegment != nil)")
        }
    }

    /// Mark the transmux as complete. Flushes the last buffered segment and stops the timer.
    /// No playlist rewrite needed — the VOD playlist was written once on start().
    func markComplete() {
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

    /// Parse the moov atom to extract the media timescale.
    /// Path: moov -> trak -> mdia -> mdhd -> timescale
    private func parseTimescaleFromMoov() {
        guard let handle = FileHandle(forReadingAtPath: fmp4Path) else {
            print("[HLSSegmenter] WARNING: Cannot open fMP4 to parse moov, using default timescale 90000")
            timescale = 90000
            return
        }
        defer { try? handle.close() }

        var offset: UInt64 = 0
        let fileSize = Self.currentFileSize(fmp4Path)

        while offset < fileSize {
            guard let (boxSize, boxType) = readBoxHeader(handle: handle, at: offset) else { break }
            if boxSize < 8 { break }

            if boxType == "moov" {
                if let ts = findTimescaleInMoov(handle: handle, containerStart: offset + 8, containerEnd: offset + UInt64(boxSize)) {
                    timescale = ts
                    print("[HLSSegmenter] Parsed timescale from moov/trak/mdia/mdhd: \(ts)")
                    return
                }
            }
            offset += UInt64(boxSize)
        }

        timescale = 90000
        print("[HLSSegmenter] WARNING: Could not parse timescale from moov, using default \(timescale)")
    }

    private func findTimescaleInMoov(handle: FileHandle, containerStart: UInt64, containerEnd: UInt64) -> UInt32? {
        var offset = containerStart
        while offset + 8 <= containerEnd {
            guard let (boxSize, boxType) = readBoxHeader(handle: handle, at: offset) else { break }
            if boxSize < 8 { break }
            let boxEnd = offset + UInt64(boxSize)
            if boxEnd > containerEnd { break }

            switch boxType {
            case "trak", "mdia":
                if let ts = findTimescaleInMoov(handle: handle, containerStart: offset + 8, containerEnd: boxEnd) {
                    return ts
                }
            case "mdhd":
                return parseMdhd(handle: handle, boxStart: offset, boxSize: Int64(boxSize))
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
    private func scanForNewSegments() {
        let fileSize = Self.currentFileSize(fmp4Path)
        guard fileSize > scanOffset else { return }

        guard let handle = FileHandle(forReadingAtPath: fmp4Path) else { return }
        defer { try? handle.close() }

        var offset = UInt64(scanOffset)
        var newSegmentsFound = false

        while offset + 8 <= fileSize {
            guard let (boxSize, boxType) = readBoxHeader(handle: handle, at: offset) else { break }
            if boxSize < 8 { break }

            let boxEnd = offset + UInt64(boxSize)
            guard boxEnd <= fileSize else { break }

            switch boxType {
            case "moof":
                let decodeTime = parseTfdt(handle: handle, moofStart: offset, moofSize: Int64(boxSize))
                pendingMoofOffset = Int64(offset)
                pendingMoofSize = Int64(boxSize)
                pendingDecodeTime = decodeTime

            case "mdat":
                if pendingMoofOffset >= 0 {
                    let rawOffset = pendingMoofOffset
                    let rawSize = pendingMoofSize + Int64(boxSize)
                    let rawDecodeTime = pendingDecodeTime

                    // Emit the previously buffered segment using current tfdt for duration.
                    // With timestamp rebasing, output tfdt values should be monotonically
                    // increasing. Keep discontinuity detection as a safety net.
                    if let buffered = bufferedRawSegment {
                        let duration: Double
                        let startTimeSec: Double
                        if timescale > 0 {
                            let maxDeltaTicks = UInt64(2.0 * targetSegmentDuration * Double(timescale))
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
                                duration = dtDelta > 0 ? Double(dtDelta) / Double(timescale) : 0.1
                            }
                            startTimeSec = Double(buffered.decodeTime) / Double(timescale)
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
                            TransmuxLog.segmenter("SEEK MAPPING: source \(String(format: "%.1f", seekTarget))s -> output \(String(format: "%.3f", startTimeSec))s (srcToOutOffset=\(String(format: "%.3f", sourceToOutputOffset)))")
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

                        TransmuxLog.segmenter("Segment[\(segment.index)]: bytes=\(buffered.byteOffset)+\(buffered.byteLength) dur=\(String(format: "%.3f", duration))s srcTime=\(String(format: "%.3f", sourceStartTimeSec))s outTime=\(String(format: "%.3f", startTimeSec))s decodeTicks=\(buffered.decodeTime)")
                        newSegmentsFound = true
                    }

                    // Buffer the current raw segment for next iteration
                    bufferedRawSegment = (byteOffset: rawOffset, byteLength: rawSize, decodeTime: rawDecodeTime)

                    pendingMoofOffset = -1
                    pendingMoofSize = 0
                }

            default:
                break
            }

            offset = boxEnd
        }

        scanOffset = Int64(offset)

        // No playlist rewrite needed — VOD playlist was written once on start().
        // We only track real segments for byte-range lookups by TransmuxServer.
        if newSegmentsFound {
            TransmuxLog.segmenter("\(segments.count) real segments tracked so far (scanOffset=\(scanOffset))")
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
        if timescale > 0 {
            startTimeSec = Double(buffered.decodeTime) / Double(timescale)
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

        TransmuxLog.segmenter("Segment[\(segment.index)] (FLUSH): bytes=\(buffered.byteOffset)+\(buffered.byteLength) dur=\(String(format: "%.3f", duration))s srcTime=\(String(format: "%.3f", sourceStartTimeSec))s outTime=\(String(format: "%.3f", startTimeSec))s")
        bufferedRawSegment = nil
    }

    // MARK: - tfdt Parsing

    /// Parse moof -> traf -> tfdt to extract baseMediaDecodeTime.
    private func parseTfdt(handle: FileHandle, moofStart: UInt64, moofSize: Int64) -> UInt64 {
        let moofEnd = moofStart + UInt64(moofSize)
        var offset = moofStart + 8

        while offset + 8 <= moofEnd {
            guard let (boxSize, boxType) = readBoxHeader(handle: handle, at: offset) else { break }
            if boxSize < 8 { break }
            let boxEnd = offset + UInt64(boxSize)
            if boxEnd > moofEnd { break }

            if boxType == "traf" {
                var trafOffset = offset + 8
                while trafOffset + 8 <= boxEnd {
                    guard let (innerSize, innerType) = readBoxHeader(handle: handle, at: trafOffset) else { break }
                    if innerSize < 8 { break }
                    let innerEnd = trafOffset + UInt64(innerSize)
                    if innerEnd > boxEnd { break }

                    if innerType == "tfdt" {
                        do { try handle.seek(toOffset: trafOffset + 8) } catch { break }
                        let vfData = handle.readData(ofLength: 4)
                        guard vfData.count == 4 else { break }

                        let version = vfData[0]
                        if version == 1 {
                            let dtData = handle.readData(ofLength: 8)
                            guard dtData.count == 8 else { break }
                            return dtData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
                        } else {
                            let dtData = handle.readData(ofLength: 4)
                            guard dtData.count == 4 else { break }
                            return UInt64(dtData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                        }
                    }

                    trafOffset = innerEnd
                }
            }

            offset = boxEnd
        }

        return 0
    }

    // MARK: - Public Lookup API

    /// Returns real moof+mdat byte ranges from stream.mp4 that cover the given time range.
    /// The time range is in source time (matching the virtual HLS playlist).
    /// Only returns segments that have actually been transmuxed (scanned from the file).
    /// Returns empty array if those segments haven't been transmuxed yet.
    func realSegments(inTimeRange start: Double, end: Double) -> [(offset: Int64, length: Int64)] {
        return scanQueue.sync {
            var result: [(offset: Int64, length: Int64)] = []
            var matchDetails: [String] = []
            for seg in segments {
                let segEnd = seg.sourceStartTime + seg.duration
                // Segment overlaps with requested source time range
                if segEnd > start && seg.sourceStartTime < end {
                    result.append((offset: seg.byteOffset, length: seg.byteLength))
                    matchDetails.append("idx\(seg.index):[src=\(String(format: "%.1f-%.1f", seg.sourceStartTime, segEnd))s out=\(String(format: "%.1f", seg.startTime))s off=\(seg.byteOffset) len=\(seg.byteLength)]")
                }
            }
            if !result.isEmpty {
                TransmuxLog.segmenter("realSegments(\(String(format: "%.1f-%.1f", start, end))s): \(result.count) matches: \(matchDetails.joined(separator: ", "))", level: .debug)
            }
            return result
        }
    }

    /// The latest source time (seconds) that has been transmuxed.
    func latestTransmuxedTime() -> Double {
        return scanQueue.sync {
            guard let lastSeg = segments.last else { return 0 }
            return lastSeg.sourceStartTime + lastSeg.duration
        }
    }

    /// Force an immediate fMP4 scan for new segments.
    /// Called by TransmuxServer during polling instead of waiting for the 300ms timer.
    func triggerScan() {
        scanQueue.sync {
            self.scanForNewSegments()
        }
    }

    /// Latest source time with visibility into the buffered (not-yet-emitted) segment.
    /// This is always >= latestTransmuxedTime() and reflects actual data on disk,
    /// including the current moof+mdat pair waiting for the next tfdt to compute duration.
    func latestBufferedSourceTime() -> Double {
        return scanQueue.sync {
            self.scanForNewSegments()
            if let buf = self.bufferedRawSegment, self.timescale > 0 {
                let outTime = Double(buf.decodeTime) / Double(self.timescale)
                let srcTime = outTime - self.sourceToOutputOffset
                // Add estimated 1s duration for the buffered segment
                return srcTime + 1.0
            }
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
        m3u8 += "#EXT-X-MAP:URI=\"init.mp4\"\n"

        for i in 0..<totalSegmentCount {
            let segStart = Double(i) * targetSegmentDuration
            let segDuration: Double
            if i == totalSegmentCount - 1 {
                // Last segment covers the remainder
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
            print("[HLSSegmenter] Created VOD playlist with \(totalSegmentCount) segments, duration \(String(format: "%.1f", totalDuration))s")
        } catch {
            print("[HLSSegmenter] ERROR: Failed to write VOD playlist: \(error)")
        }
    }

    // MARK: - MP4 Box Helpers

    /// Read an 8-byte MP4 box header (size + type) at the given offset.
    private func readBoxHeader(handle: FileHandle, at offset: UInt64) -> (Int64, String)? {
        do { try handle.seek(toOffset: offset) } catch { return nil }
        let data = handle.readData(ofLength: 8)
        guard data.count == 8 else { return nil }

        let size32 = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 0, as: UInt32.self).bigEndian
        }
        let typeBytes = data.subdata(in: 4..<8)
        let type = String(data: typeBytes, encoding: .ascii) ?? "????"

        if size32 == 1 {
            let extData = handle.readData(ofLength: 8)
            guard extData.count == 8 else { return nil }
            let size64 = extData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return (Int64(size64), type)
        }

        return (Int64(size32), type)
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

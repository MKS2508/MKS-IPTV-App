import Foundation

// MARK: - HLSSegmenter

/// Monitors a growing fMP4 file produced by TransmuxingService and generates
/// a byte-range HLS playlist (m3u8) that AVPlayer can consume natively.
///
/// ## How it works
/// The segmenter scans the fMP4 file for moof+mdat box pairs (media segments),
/// extracts timing from tfdt atoms, and writes a byte-range HLS v7 playlist.
/// AVPlayer polls the EVENT playlist for new segments and fetches them via
/// Range requests from TransmuxServer.
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
    }

    // MARK: - Properties

    let fmp4Path: String
    let playlistPath: String
    let initSegmentSize: Int64

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

    private var scanTimer: DispatchSourceTimer?
    private let scanQueue = DispatchQueue(label: "HLSSegmenter.scan", qos: .userInitiated)

    // MARK: - Init

    init(fmp4Path: String, playlistPath: String, initSegmentSize: Int64) {
        self.fmp4Path = fmp4Path
        self.playlistPath = playlistPath
        self.initSegmentSize = initSegmentSize
        self.scanOffset = initSegmentSize
        print("[HLSSegmenter] Created: fmp4=\(fmp4Path), playlist=\(playlistPath), initSize=\(initSegmentSize)")
    }

    // MARK: - Public API

    /// Start scanning the fMP4 file for new segments. Call after the fMP4 header
    /// is flushed to disk.
    func start() {
        // Parse timescale from the moov atom before starting the scan loop
        parseTimescaleFromMoov()

        // Write initial playlist with just the init segment (no media segments yet).
        // TransmuxServer will wait for #EXTINF entries before serving to AVPlayer.
        writePlaylist()

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

    /// Mark the transmux as complete. Flushes the last buffered segment,
    /// writes the final playlist with #EXT-X-ENDLIST, and stops the timer.
    func markComplete() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            self.isCompleted = true

            // Final scan to detect any remaining boxes on disk
            self.scanForNewSegments()

            // Flush the last buffered segment (no next tfdt, use average duration)
            self.flushBufferedSegment()

            // Write final playlist with ENDLIST
            self.writeFinalPlaylist()

            self.scanTimer?.cancel()
            self.scanTimer = nil

            print("[HLSSegmenter] Marked complete, \(self.segments.count) segments total")
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

                    // Emit the previously buffered segment using current tfdt for duration
                    if let buffered = bufferedRawSegment {
                        let duration: Double
                        if timescale > 0 {
                            let dtDelta = rawDecodeTime - buffered.decodeTime
                            duration = dtDelta > 0 ? Double(dtDelta) / Double(timescale) : 0.1
                        } else {
                            duration = 1.0
                        }

                        let segment = Segment(
                            index: segments.count,
                            byteOffset: buffered.byteOffset,
                            byteLength: buffered.byteLength,
                            duration: duration
                        )
                        segments.append(segment)
                        if duration > maxDuration { maxDuration = duration }

                        print("[HLSSegmenter] Segment \(segment.index): offset=\(buffered.byteOffset), size=\(buffered.byteLength), duration=\(String(format: "%.3f", duration))s")
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

        if newSegmentsFound {
            writePlaylist()
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

        let segment = Segment(
            index: segments.count,
            byteOffset: buffered.byteOffset,
            byteLength: buffered.byteLength,
            duration: duration
        )
        segments.append(segment)
        if duration > maxDuration { maxDuration = duration }

        print("[HLSSegmenter] Segment \(segment.index) (final): offset=\(buffered.byteOffset), size=\(buffered.byteLength), duration=\(String(format: "%.3f", duration))s")
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

    // MARK: - Playlist Generation

    /// Write the byte-range HLS playlist to disk.
    private func writePlaylist() {
        let targetDuration = max(Int(ceil(maxDuration)), 6)

        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:7\n"
        m3u8 += "#EXT-X-TARGETDURATION:\(targetDuration)\n"
        m3u8 += "#EXT-X-PLAYLIST-TYPE:EVENT\n"
        m3u8 += "#EXT-X-MAP:URI=\"stream.mp4\",BYTERANGE=\"\(initSegmentSize)@0\"\n"

        for segment in segments {
            m3u8 += "\n#EXTINF:\(String(format: "%.3f", segment.duration)),\n"
            m3u8 += "#EXT-X-BYTERANGE:\(segment.byteLength)@\(segment.byteOffset)\n"
            m3u8 += "stream.mp4\n"
        }

        do {
            try m3u8.write(toFile: playlistPath, atomically: true, encoding: .utf8)
        } catch {
            print("[HLSSegmenter] ERROR: Failed to write playlist: \(error)")
        }
    }

    /// Write the final playlist with #EXT-X-ENDLIST.
    private func writeFinalPlaylist() {
        let targetDuration = max(Int(ceil(maxDuration)), 6)

        var m3u8 = "#EXTM3U\n"
        m3u8 += "#EXT-X-VERSION:7\n"
        m3u8 += "#EXT-X-TARGETDURATION:\(targetDuration)\n"
        m3u8 += "#EXT-X-PLAYLIST-TYPE:VOD\n"
        m3u8 += "#EXT-X-MAP:URI=\"stream.mp4\",BYTERANGE=\"\(initSegmentSize)@0\"\n"

        for segment in segments {
            m3u8 += "\n#EXTINF:\(String(format: "%.3f", segment.duration)),\n"
            m3u8 += "#EXT-X-BYTERANGE:\(segment.byteLength)@\(segment.byteOffset)\n"
            m3u8 += "stream.mp4\n"
        }

        m3u8 += "\n#EXT-X-ENDLIST\n"

        do {
            try m3u8.write(toFile: playlistPath, atomically: true, encoding: .utf8)
            print("[HLSSegmenter] Final playlist written with \(segments.count) segments and ENDLIST")
        } catch {
            print("[HLSSegmenter] ERROR: Failed to write final playlist: \(error)")
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

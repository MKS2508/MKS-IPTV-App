import Foundation
import Network

// MARK: - TransmuxServer

/// Native NWListener-based HTTP server that serves a VOD HLS playlist and
/// virtual segments from a growing fMP4 file produced by TransmuxingService.
/// The playlist is VOD+ENDLIST from the start, enabling full seeking immediately.
///
/// Architecture:
/// ```
/// FFmpeg C API writes fMP4 → /tmp/.../stream.mp4 (growing file)
/// HLSSegmenter:
///   - Writes static VOD playlist (all segments declared upfront)
///   - Scans fMP4 for real moof+mdat byte ranges (time-based lookup)
///
/// TransmuxServer (NWListener:8100-8199)
///   GET /stream.m3u8    → 200 (static VOD playlist)
///   GET /init.mp4       → 200 (ftyp+moov from stream.mp4)
///   GET /seg_NNN.mp4    → 200 (moof+mdat for time range)
///     ├─ Available from sequential transmux → read byte ranges
///     └─ Not yet available → seek-redirect (signal remux loop to seek input, wait ~8s)
///
/// AVPlayer (http://localhost:81XX/stream.m3u8)
/// ```
public actor TransmuxServer {

    public static let shared = TransmuxServer()

    // MARK: - Types

    public struct Session {
        public let localURL: URL
        public let port: UInt16
    }

    public enum ServerError: LocalizedError {
        case portExhausted
        case invalidFilePath
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .portExhausted:
                return "Could not find available port in range 8100-8199"
            case .invalidFilePath:
                return "Invalid file path for transmux output"
            case .alreadyRunning:
                return "TransmuxServer is already serving a file"
            }
        }
    }

    // MARK: - Properties

    private var listener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var filePath: String?
    private var playlistPath: String?
    private var expectedSize: Int64 = 0
    private var isComplete = false
    private var currentPort: UInt16 = 0

    /// HLS segmenter for time-based segment lookups
    private var segmenter: HLSSegmenter?
    /// Size of the init segment (ftyp+moov) in stream.mp4
    private var initSegmentSize: Int64 = 0
    /// Seek handle for redirecting the sequential transmux to a new input position
    private var seekHandle: ActiveTransmux?

    private let networkQueue = DispatchQueue(label: "TransmuxServer.network", qos: .userInitiated)
    private let portRange: Range<UInt16> = 8100..<8200

    private init() {}

    // MARK: - Public API

    /// Start serving a growing fMP4 file and its HLS playlist.
    /// Called after avformat_write_header succeeds and HLSSegmenter has written
    /// the VOD playlist. Waits for the NWListener to reach `.ready` state
    /// before returning, so AVPlayer can connect immediately.
    public func start(
        filePath: String,
        playlistPath: String,
        expectedSize: Int64,
        segmenter: HLSSegmenter,
        initSegmentSize: Int64,
        seekHandle: ActiveTransmux? = nil
    ) async throws -> Session {
        if listener != nil {
            stop()
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ServerError.invalidFilePath
        }

        self.filePath = filePath
        self.playlistPath = playlistPath
        self.expectedSize = expectedSize
        self.segmenter = segmenter
        self.initSegmentSize = initSegmentSize
        self.seekHandle = seekHandle
        self.isComplete = false

        let port = try findAvailablePort()
        self.currentPort = port

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = nwListener

        nwListener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleConnection(connection)
            }
        }

        // Wait for the listener to become ready before returning.
        // This prevents the race where AVPlayer connects before the listener
        // is accepting connections.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[TransmuxServer] Listening on port \(port)")
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    print("[TransmuxServer] Listener failed: \(error)")
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    print("[TransmuxServer] Listener cancelled")
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: ServerError.portExhausted)
                    }
                default:
                    break
                }
            }

            nwListener.start(queue: self.networkQueue)
        }

        guard let url = URL(string: "http://localhost:\(port)/stream.m3u8") else {
            throw ServerError.invalidFilePath
        }

        print("[TransmuxServer] Serving HLS at \(url) (mp4: \(filePath))")
        return Session(localURL: url, port: port)
    }

    /// Mark the transmux as complete. After this, empty reads mean real EOF.
    public func setComplete() {
        isComplete = true
        print("[TransmuxServer] Transmux complete — EOF on empty reads")
    }

    /// Stop serving and clean up all connections.
    public func stop() {
        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()

        listener?.cancel()
        listener = nil
        filePath = nil
        playlistPath = nil
        expectedSize = 0
        isComplete = false
        currentPort = 0
        segmenter = nil
        initSegmentSize = 0
        seekHandle = nil

        print("[TransmuxServer] Stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { [weak self] in
                    await self?.removeConnection(connection)
                }
            } else if case .failed = state {
                Task { [weak self] in
                    await self?.removeConnection(connection)
                }
            }
        }

        connection.start(queue: networkQueue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let data = data, !data.isEmpty else {
                if let error = error {
                    print("[TransmuxServer] Read error: \(error)")
                }
                connection.cancel()
                return
            }

            guard let request = HTTPRequestParser.parse(data) else {
                print("[TransmuxServer] Failed to parse HTTP request")
                let response = Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            Task { [weak self] in
                await self?.dispatchRequest(request, connection: connection)
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }

    private func dispatchRequest(_ request: HTTPRequestParser.Request, connection: NWConnection) {
        guard let filePath = self.filePath else {
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let expectedSize = self.expectedSize
        let complete = self.isComplete
        let playlist = self.playlistPath
        let seg = self.segmenter
        let initSize = self.initSegmentSize
        let handle = self.seekHandle

        let path = request.path

        // Route based on request path
        if path.hasSuffix(".m3u8") {
            // HLS playlist
            if let playlistPath = playlist {
                switch request.method {
                case .head:
                    handleHeadPlaylist(connection: connection, playlistPath: playlistPath)
                case .get:
                    handleGetPlaylist(connection: connection, playlistPath: playlistPath)
                }
            }
        } else if path == "/init.mp4" || path.hasSuffix("/init.mp4") {
            // Init segment (ftyp+moov)
            handleGetInit(connection: connection, filePath: filePath, initSize: initSize)
        } else if path.contains("/seg_") && path.hasSuffix(".mp4"), let seg = seg {
            // Virtual segment (moof+mdat for time range)
            handleGetSegment(
                connection: connection,
                path: path,
                filePath: filePath,
                segmenter: seg,
                seekHandle: handle,
                isComplete: complete
            )
        } else {
            // Fallback: existing byte-range handler for direct mp4 access
            switch request.method {
            case .head:
                handleHead(connection: connection, filePath: filePath, expectedSize: expectedSize)
            case .get:
                handleGet(connection: connection, filePath: filePath, expectedSize: expectedSize, isComplete: complete, rangeHeader: request.rangeHeader)
            }
        }
    }

    // MARK: - HLS Playlist Handlers

    /// Serve the static VOD HLS playlist file.
    /// The playlist is written once by HLSSegmenter with all virtual segments
    /// and #EXT-X-ENDLIST, so no polling or waiting is needed.
    private nonisolated func handleGetPlaylist(connection: NWConnection, playlistPath: String) {
        guard let playlistData = FileManager.default.contents(atPath: playlistPath) else {
            print("[TransmuxServer] GET /stream.m3u8 -> 404 (file not found)")
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/vnd.apple.mpegurl\r\n"
        header += "Content-Length: \(playlistData.count)\r\n"
        header += "Cache-Control: no-cache, no-store\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        print("[TransmuxServer] GET /stream.m3u8 -> 200 (\(playlistData.count) bytes, VOD+ENDLIST)")

        var responseData = Data(header.utf8)
        responseData.append(playlistData)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private nonisolated func handleHeadPlaylist(connection: NWConnection, playlistPath: String) {
        let fileSize = Self.currentFileSize(playlistPath)

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: application/vnd.apple.mpegurl\r\n"
        header += "Content-Length: \(fileSize)\r\n"
        header += "Cache-Control: no-cache, no-store\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        print("[TransmuxServer] HEAD /stream.m3u8 -> 200 Content-Length: \(fileSize)")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Init Segment Handler

    /// Serve the init segment (ftyp+moov) from bytes [0, initSize) of stream.mp4.
    private nonisolated func handleGetInit(connection: NWConnection, filePath: String, initSize: Int64) {
        guard initSize > 0,
              let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            print("[TransmuxServer] GET /init.mp4 -> 404 (cannot read init segment)")
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        defer { try? fileHandle.close() }

        let data = fileHandle.readData(ofLength: Int(initSize))

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: video/mp4\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        print("[TransmuxServer] GET /init.mp4 -> 200 (\(data.count) bytes)")

        var responseData = Data(header.utf8)
        responseData.append(data)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Segment Handler

    /// Serve a virtual segment (seg_NNN.mp4) by reading the corresponding moof+mdat
    /// byte ranges from the growing stream.mp4 file.
    ///
    /// Strategy with fullness gate to prevent serving incomplete segments:
    /// 1. Immediate check: if latestBufferedSourceTime >= endTime AND realSegments exist → serve
    /// 2. Decide: "nearby" (sequential transmux covers this) vs "far" (need seek)
    /// 3. Polling loop with FULLNESS GATE: triggerScan + wait for latestBufferedSourceTime >= endTime
    /// 4. Fallback seek at Phase 2 if sequential stalled
    /// 5. Timeout after ~11.5s → 404
    private nonisolated func handleGetSegment(
        connection: NWConnection,
        path: String,
        filePath: String,
        segmenter: HLSSegmenter,
        seekHandle: ActiveTransmux?,
        isComplete: Bool
    ) {
        // Parse segment index from URL: /seg_042.mp4 → 42
        guard let segIndexStr = path.components(separatedBy: "/").last?
                .replacingOccurrences(of: "seg_", with: "")
                .replacingOccurrences(of: ".mp4", with: ""),
              let segIndex = Int(segIndexStr) else {
            TransmuxLog.log("GET \(path) -> 400 (cannot parse segment index)", tag: "Server", level: .error)
            let response = Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let targetDuration = segmenter.targetSegmentDuration
        let totalDuration = segmenter.totalDuration
        let startTime = Double(segIndex) * targetDuration
        let endTime = min(Double(segIndex + 1) * targetDuration, totalDuration)
        let latestBuffered = segmenter.latestBufferedSourceTime()
        let latestTime = segmenter.latestTransmuxedTime()
        let lastSeek = seekHandle?.lastSeekTarget

        // Segment request logged only when seek is needed (below)

        // Step 1: Immediate fullness check — serve if transmux has produced
        // enough data to cover the full segment time range. We require
        // latestBuffered >= endTime (with epsilon) to ensure the fMP4 scanner
        // has processed ALL moof boxes whose start time falls within [startTime, endTime).
        // Epsilon tolerance (0.05s) handles DTS floating-point rounding:
        // e.g., latestBuffered=35.999 should pass for endTime=36.0.
        let fullnessEpsilon = 0.05
        if latestBuffered >= endTime - fullnessEpsilon {
            let byteRanges = segmenter.realSegments(inTimeRange: startTime, end: endTime)
            if !byteRanges.isEmpty {
                let segData = Self.readByteRanges(filePath: filePath, ranges: byteRanges)
                if !segData.isEmpty {
                    TransmuxLog.segment("SERVE", segIndex: segIndex, startTime: startTime, endTime: endTime, source: "immediate", extra: "bytes=\(segData.count) ranges=\(byteRanges.count) latestBuffered=\(String(format: "%.1f", latestBuffered))s")
                    Self.sendSegmentResponse(connection: connection, data: segData, segIndex: segIndex, source: "immediate")
                    return
                }
            }
        }

        // No seek handle or transmux is complete with no data — respond 404
        guard let handle = seekHandle, !isComplete else {
            TransmuxLog.segment("404 no-seek-handle", segIndex: segIndex, startTime: startTime, endTime: endTime, source: "none", extra: "complete=\(isComplete)")
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        // Step 2: Decide strategy — "nearby" (wait for sequential) vs "far" (seek first)
        //
        // "Nearby" means the sequential transmux is producing data that will cover
        // this segment soon, so we should NOT seek (which would interrupt production).
        //
        // Nearby if:
        //   - startTime < latestBuffered + 3 * targetDuration (sequential will catch up), OR
        //   - lastSeekTarget exists AND startTime is within the seek's production window
        //     (startTime >= lastSeekTarget AND startTime < lastSeekTarget + 8 * targetDuration)
        let isNearby: Bool
        let nearbyThreshold = latestBuffered + targetDuration * 3
        let seekWindowEnd = (lastSeek ?? -1) + targetDuration * 8

        if startTime < nearbyThreshold {
            isNearby = true
        } else if let lst = lastSeek, startTime >= lst, startTime < seekWindowEnd {
            isNearby = true
        } else {
            isNearby = false
        }

        // Step 3: If far, trigger seek immediately
        var seekTriggered = false
        if !isNearby {
            TransmuxLog.seekEvent(
                "SEEK-REDIRECT trigger",
                seekTime: startTime,
                latestTime: latestTime,
                lastSeekTarget: lastSeek,
                extra: "seg_\(String(format: "%03d", segIndex)) strategy=far"
            )
            handle.requestSeek(to: startTime)
            seekTriggered = true
        }

        // Step 4: Polling loop with FULLNESS GATE
        DispatchQueue.global(qos: .userInitiated).async {
            // Phase 1: 30 × 100ms = 3s   (fast — sequential catch-up)
            // Phase 2: 20 × 200ms = 4s   (medium — wait for seek data)
            // Phase 3: 15 × 300ms = 4.5s (slow — last chance)
            // Total: ~11.5s timeout
            let pollPhases: [(count: Int, interval: TimeInterval)] = [
                (30, 0.1),
                (20, 0.2),
                (15, 0.3),
            ]
            var totalPolls = 0
            let pollStart = Date()
            var currentPhaseIdx = 0

            for (phaseIdx, (pollCount, interval)) in pollPhases.enumerated() {
                currentPhaseIdx = phaseIdx

                // Fallback seek: at start of Phase 2, if no seek was triggered yet
                // and sequential transmux hasn't made meaningful progress, trigger seek.
                if phaseIdx == 1 && !seekTriggered {
                    let currentBuffered = segmenter.latestBufferedSourceTime()
                    if currentBuffered < startTime + 1.0 {
                        TransmuxLog.seekEvent(
                            "FALLBACK SEEK trigger",
                            seekTime: startTime,
                            latestTime: segmenter.latestTransmuxedTime(),
                            lastSeekTarget: handle.lastSeekTarget,
                            extra: "seg_\(String(format: "%03d", segIndex)) latestBuffered=\(String(format: "%.1f", currentBuffered))s stalled"
                        )
                        handle.requestSeek(to: startTime)
                        seekTriggered = true
                    }
                }

                for _ in 0..<pollCount {
                    Thread.sleep(forTimeInterval: interval)
                    totalPolls += 1

                    // Force HLSSegmenter to scan disk NOW instead of waiting for 300ms timer
                    segmenter.triggerScan()

                    // FULLNESS GATE: only check realSegments when latestBufferedSourceTime
                    // confirms enough data has been produced to cover the entire segment.
                    // Epsilon tolerance (0.05s) handles DTS floating-point rounding:
                    // e.g., bufferedTime=35.999 should pass for endTime=36.0.
                    let bufferedTime = segmenter.latestBufferedSourceTime()
                    guard bufferedTime >= endTime - fullnessEpsilon else {
                        // Log only when truly stalled (phase 2+)
                        if totalPolls % 40 == 0 {
                            TransmuxLog.log(
                                "seg_\(String(format: "%03d", segIndex)): waiting \(String(format: "%.1f", endTime - bufferedTime))s gap",
                                tag: "Server"
                            )
                        }
                        continue
                    }

                    // Fullness gate passed — check for actual segment byte ranges
                    let ranges = segmenter.realSegments(inTimeRange: startTime, end: endTime)
                    if !ranges.isEmpty {
                        let segData = Self.readByteRanges(filePath: filePath, ranges: ranges)
                        if !segData.isEmpty {
                            let elapsed = Date().timeIntervalSince(pollStart)
                            let source = seekTriggered ? "seek-redirect" : "sequential-wait"
                            TransmuxLog.segment(
                                "SERVE",
                                segIndex: segIndex,
                                startTime: startTime,
                                endTime: endTime,
                                source: source,
                                extra: "bytes=\(segData.count) polls=\(totalPolls) elapsed=\(String(format: "%.2f", elapsed))s phase=\(phaseIdx+1) latestBuffered=\(String(format: "%.1f", bufferedTime))s"
                            )
                            Self.sendSegmentResponse(connection: connection, data: segData, segIndex: segIndex, source: source)
                            return
                        }
                    }
                }
            }

            // Timeout — did not produce full segment data in ~11.5s
            let elapsed = Date().timeIntervalSince(pollStart)
            let finalBuffered = segmenter.latestBufferedSourceTime()
            let finalLatest = segmenter.latestTransmuxedTime()
            TransmuxLog.segment(
                "TIMEOUT 404",
                segIndex: segIndex,
                startTime: startTime,
                endTime: endTime,
                source: seekTriggered ? "seek-redirect" : "sequential-wait",
                extra: "polls=\(totalPolls) elapsed=\(String(format: "%.2f", elapsed))s latestBuffered=\(String(format: "%.1f", finalBuffered))s latestTransmuxed=\(String(format: "%.1f", finalLatest))s phase=\(currentPhaseIdx+1)"
            )
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// Read multiple byte ranges from a file and concatenate them into a single Data.
    private nonisolated static func readByteRanges(filePath: String, ranges: [(offset: Int64, length: Int64)]) -> Data {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            TransmuxLog.log("readByteRanges: cannot open file", tag: "Server", level: .error)
            return Data()
        }
        defer { try? fileHandle.close() }

        var result = Data()
        for (_, range) in ranges.enumerated() {
            do {
                try fileHandle.seek(toOffset: UInt64(range.offset))
                let chunk = fileHandle.readData(ofLength: Int(range.length))
                result.append(chunk)
            } catch {
                TransmuxLog.log("readByteRanges: seek/read failed at offset \(range.offset): \(error)", tag: "Server", level: .error)
            }
        }
        return result
    }

    /// Send a 200 OK response with segment data.
    private nonisolated static func sendSegmentResponse(connection: NWConnection, data: Data, segIndex: Int, source: String) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: video/mp4\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        var responseData = Data(header.utf8)
        responseData.append(data)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - HEAD Handler (MP4)

    private nonisolated func handleHead(connection: NWConnection, filePath: String, expectedSize: Int64) {
        let fileSize: Int64 = expectedSize > 0 ? expectedSize : Self.currentFileSize(filePath)

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: video/mp4\r\n"
        header += "Content-Length: \(fileSize)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        print("[TransmuxServer] HEAD -> 200 Content-Length: \(fileSize)")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - GET Handler

    /// Handles GET requests with proper 206 Partial Content responses.
    ///
    /// Apple's FigHTTP strictly validates that the response Content-Length
    /// matches the requested Range — even for 200 OK responses. Therefore
    /// we MUST respond with 206 and a Content-Range that exactly covers the
    /// requested byte range.
    ///
    /// Three cases:
    /// 1. Requested range fits entirely within available data → serve immediately
    /// 2. Range starts within available data but extends beyond → serve with
    ///    full requested Content-Range and stream the growing file (polling)
    /// 3. Range starts beyond available data → wait up to 5s, then 416
    private nonisolated func handleGet(
        connection: NWConnection,
        filePath: String,
        expectedSize: Int64,
        isComplete: Bool,
        rangeHeader: String?
    ) {
        let totalSize: Int64 = expectedSize > 0 ? expectedSize : max(Self.currentFileSize(filePath), 1)

        // Parse Range header
        let rangeStart: Int64
        let rangeEnd: Int64

        if let rangeHeader = rangeHeader, rangeHeader.hasPrefix("bytes=") {
            let rangeSpec = String(rangeHeader.dropFirst("bytes=".count))
            let parts = rangeSpec.split(separator: "-", maxSplits: 1)
            rangeStart = Int64(parts[0]) ?? 0
            if parts.count > 1, let end = Int64(parts[1]) {
                rangeEnd = end
            } else {
                rangeEnd = totalSize - 1
            }
        } else {
            // No Range header → 200 OK with full file streaming
            handleGetNoRange(
                connection: connection,
                filePath: filePath,
                totalSize: totalSize,
                isComplete: isComplete
            )
            return
        }

        let currentFileSize = Self.currentFileSize(filePath)
        let contentLength = rangeEnd - rangeStart + 1

        // Case 3: Range starts beyond available data
        if rangeStart >= currentFileSize && !isComplete {
            // Wait up to 5s for transmux to catch up
            var waitedFileSize = currentFileSize
            for _ in 0..<50 {
                Thread.sleep(forTimeInterval: 0.1)
                waitedFileSize = Self.currentFileSize(filePath)
                if waitedFileSize > rangeStart { break }
                let sentinelPath = (filePath as NSString).deletingLastPathComponent + "/.transmux_complete"
                if FileManager.default.fileExists(atPath: sentinelPath) { break }
            }
            if waitedFileSize <= rangeStart {
                let resp = "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(totalSize)\r\nConnection: close\r\n\r\n"
                print("[TransmuxServer] GET 416 — rangeStart \(rangeStart) >= fileSize \(waitedFileSize)")
                connection.send(content: Data(resp.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
        }

        // Cases 1 & 2: respond with 206 and the FULL requested Content-Range.
        // FigHTTP requires Content-Length to match the requested range exactly.
        var header = "HTTP/1.1 206 Partial Content\r\n"
        header += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "Content-Type: video/mp4\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        print("[TransmuxServer] GET 206 bytes=\(rangeStart)-\(rangeEnd)/\(totalSize) CL=\(contentLength) (file: \(currentFileSize), complete=\(isComplete))")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error = error {
                print("[TransmuxServer] Failed to send headers: \(error)")
                connection.cancel()
                return
            }

            // Stream from rangeStart for exactly contentLength bytes,
            // polling for new data when we catch up to the write position.
            Self.streamGrowingFile(
                connection: connection,
                filePath: filePath,
                offset: rangeStart,
                bytesToServe: contentLength,
                isCompleteAtStart: isComplete
            )
        })
    }

    /// Handle GET without Range header — 200 OK, stream full file.
    private nonisolated func handleGetNoRange(
        connection: NWConnection,
        filePath: String,
        totalSize: Int64,
        isComplete: Bool
    ) {
        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: video/mp4\r\n"
        header += "Content-Length: \(totalSize)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        let currentSize = Self.currentFileSize(filePath)
        print("[TransmuxServer] GET 200 OK CL=\(totalSize) (file: \(currentSize), complete=\(isComplete))")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error = error {
                print("[TransmuxServer] Failed to send headers: \(error)")
                connection.cancel()
                return
            }

            Self.streamGrowingFile(
                connection: connection,
                filePath: filePath,
                offset: 0,
                bytesToServe: totalSize,
                isCompleteAtStart: isComplete
            )
        })
    }

    // MARK: - File Streaming

    /// Stream `bytesToServe` bytes from the file starting at `offset`.
    /// When the read position catches up to the current EOF but the transmux
    /// is still running, polls every 100ms for new data (up to 60s).
    /// Once the transmux completes (sentinel file), empty reads mean real EOF.
    private nonisolated static func streamGrowingFile(
        connection: NWConnection,
        filePath: String,
        offset: Int64,
        bytesToServe: Int64,
        isCompleteAtStart: Bool
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
                print("[TransmuxServer] Cannot open file: \(filePath)")
                connection.cancel()
                return
            }
            defer { try? fileHandle.close() }

            if offset > 0 {
                do {
                    try fileHandle.seek(toOffset: UInt64(offset))
                } catch {
                    print("[TransmuxServer] Seek to \(offset) failed: \(error)")
                    connection.cancel()
                    return
                }
            }

            let chunkSize = 65536 // 64KB
            var currentOffset: Int64 = offset
            var remaining: Int64 = bytesToServe
            var emptyReadCount = 0
            let maxEmptyReads = 600 // 60 seconds at 100ms
            var lastKnownComplete = isCompleteAtStart

            while remaining > 0 {
                let toRead = min(Int(remaining), chunkSize)
                let data = fileHandle.readData(ofLength: toRead)

                if data.isEmpty {
                    if lastKnownComplete {
                        print("[TransmuxServer] EOF at \(currentOffset) after serving \(bytesToServe - remaining) bytes (transmux complete)")
                        break
                    }

                    emptyReadCount += 1
                    if emptyReadCount >= maxEmptyReads {
                        print("[TransmuxServer] Timeout at offset \(currentOffset) after \(bytesToServe - remaining) bytes served")
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.1)

                    // Re-check if file has grown past our position
                    let fileSize = currentFileSize(filePath)
                    if fileSize > currentOffset {
                        do {
                            try fileHandle.seek(toOffset: UInt64(currentOffset))
                        } catch {
                            print("[TransmuxServer] Re-seek failed at \(currentOffset)")
                            break
                        }
                    }

                    // Check completion sentinel every 5 seconds
                    if emptyReadCount % 50 == 0 {
                        let sentinelPath = (filePath as NSString).deletingLastPathComponent + "/.transmux_complete"
                        if FileManager.default.fileExists(atPath: sentinelPath) {
                            lastKnownComplete = true
                            let fileSize = currentFileSize(filePath)
                            if fileSize > currentOffset {
                                do { try fileHandle.seek(toOffset: UInt64(currentOffset)) } catch { break }
                            }
                        }
                    }

                    continue
                }

                emptyReadCount = 0
                currentOffset += Int64(data.count)
                remaining -= Int64(data.count)

                let semaphore = DispatchSemaphore(value: 0)
                var sendError: NWError?

                connection.send(content: data, completion: .contentProcessed { error in
                    sendError = error
                    semaphore.signal()
                })

                semaphore.wait()

                if sendError != nil {
                    print("[TransmuxServer] Client disconnected at offset \(currentOffset) (\(bytesToServe - remaining) bytes served)")
                    break
                }
            }

            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    // MARK: - Helpers

    private nonisolated static func currentFileSize(_ path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    private func findAvailablePort() throws -> UInt16 {
        for port in portRange {
            if port != currentPort {
                // Try binding to check availability
                return port
            }
        }
        throw ServerError.portExhausted
    }
}

// MARK: - HTTP Request Parser (shared with StreamProxy)

/// Minimal HTTP request parser for extracting method, path, and Range header.
/// Used by both StreamProxy and TransmuxServer.
public struct HTTPRequestParser {

    public enum Method: String {
        case get = "GET"
        case head = "HEAD"
    }

    public struct Request {
        public let method: Method
        public let path: String
        public let rangeHeader: String?
    }

    /// Parse a raw HTTP request from bytes.
    public static func parse(_ data: Data) -> Request? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }

        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let methodStr = String(parts[0])
        guard let method = Method(rawValue: methodStr) else { return nil }
        let path = String(parts[1])

        var rangeHeader: String?
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("range:") {
                let value = line.dropFirst("range:".count).trimmingCharacters(in: .whitespaces)
                rangeHeader = value
                break
            }
        }

        return Request(method: method, path: path, rangeHeader: rangeHeader)
    }
}

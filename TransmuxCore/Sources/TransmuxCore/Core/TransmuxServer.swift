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
    /// Always points to stream.m3u8 (the media playlist with segments).
    private var mediaPlaylistPath: String?
    /// Points to master.m3u8 when multi-audio or subtitles exist, nil otherwise.
    private var masterPlaylistPath: String?
    private var expectedSize: Int64 = 0
    private var isComplete = false
    private var currentPort: UInt16 = 0

    /// HLS segmenter for time-based segment lookups
    private var segmenter: HLSSegmenter?
    /// Size of the init segment (ftyp+moov) in stream.mp4
    private var initSegmentSize: Int64 = 0
    /// Seek handle for redirecting the sequential transmux to a new input position
    private var seekHandle: ActiveTransmux?
    /// LRU cache for served segment data (post-tfdt rewrite).
    /// Cache hits serve instantly without pipeline involvement.
    private var segmentCache: SegmentCache?
    /// Set to true when stop() is called; prevents polling loops from logging errors on deleted files
    private var stopped = false
    /// Cast mode: directory containing .ts segments and .m3u8 playlist for simple file serving
    private var castDirectory: String?
    /// DLNA mode: when true, adds DLNA-specific response headers (transferMode, contentFeatures, keep-alive)
    /// to all served responses. Set via `setDLNAMode(_:)`. Works with the normal transmux pipeline.
    private var dlnaMode = false
    /// DLNA direct file serving: path to the original file (not transmuxed).
    /// DLNA TVs need standard MP4/MKV with full moov — not fMP4 fragments.
    private var dlnaFilePath: String?

    private let networkQueue = DispatchQueue(label: "TransmuxServer.network", qos: .userInitiated)
    private let portRange: Range<UInt16> = 8100..<8200

    private init() {}

    // MARK: - Public API

    /// Start serving a growing fMP4 file and its HLS playlist.
    /// Called after avformat_write_header succeeds and HLSSegmenter has written
    /// the VOD playlist. Waits for the NWListener to reach `.ready` state
    /// before returning, so AVPlayer can connect immediately.
    ///
    /// - Parameters:
    ///   - filePath: Path to the growing fMP4 file (stream.mp4).
    ///   - playlistPath: Entry playlist — master.m3u8 when multi-audio/subtitles exist, stream.m3u8 otherwise.
    ///   - mediaPlaylistPath: Always stream.m3u8. When nil, defaults to `playlistPath` (single-variant case).
    ///   - expectedSize: Expected final file size for Content-Length headers.
    ///   - segmenter: HLS segmenter for time-based segment lookups.
    ///   - initSegmentSize: Size of the init segment (ftyp+moov) in stream.mp4.
    ///   - seekHandle: Handle for redirecting the sequential transmux to a new input position.
    public func start(
        filePath: String,
        playlistPath: String,
        mediaPlaylistPath: String? = nil,
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

        self.stopped = false
        self.filePath = filePath
        // mediaPlaylistPath is ALWAYS stream.m3u8
        self.mediaPlaylistPath = mediaPlaylistPath ?? playlistPath
        // masterPlaylistPath is set only when playlistPath differs from media (multi-audio/subs)
        if let media = mediaPlaylistPath, media != playlistPath {
            self.masterPlaylistPath = playlistPath
        } else {
            self.masterPlaylistPath = nil
        }
        self.expectedSize = expectedSize
        self.segmenter = segmenter
        self.initSegmentSize = initSegmentSize
        self.seekHandle = seekHandle
        self.isComplete = false
        self.segmentCache = SegmentCache()

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
                    TransmuxLog.log("LISTEN :\(port)", tag: "Server")
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    TransmuxLog.log("Listener failed: \(error)", tag: "Server", level: .error)
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
                    TransmuxLog.log("Listener cancelled", tag: "Server", level: .warn)
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

        // Use LAN IP for AirPlay compatibility: Apple TV resolves localhost to itself.
        let host = Self.getLANIPAddress() ?? "localhost"
        if host == "localhost" {
            TransmuxLog.log("WARNING: Could not determine LAN IP, AirPlay may not work", tag: "Server", level: .warn)
        }

        // Entry URL: master.m3u8 when multi-variant, stream.m3u8 when single-variant
        let entryFile = self.masterPlaylistPath != nil ? "master.m3u8" : "stream.m3u8"
        guard let url = URL(string: "http://\(host):\(port)/\(entryFile)") else {
            throw ServerError.invalidFilePath
        }

        TransmuxLog.log("SERVING \(url) (mp4: \(filePath))", tag: "Server")
        return Session(localURL: url, port: port)
    }

    /// Start serving Cast MPEG-TS content from a directory.
    /// Much simpler than the fMP4 progressive serving mode — just serves
    /// .m3u8 and .ts files directly from disk. No segmenter, no init segment,
    /// no tfdt rewriting. Used for Cast devices whose MPL only supports MPEG-TS.
    ///
    /// - Parameter directory: Path to the directory containing .ts segments and stream.m3u8
    public func startCast(directory: String) async throws -> Session {
        if listener != nil {
            stop()
        }

        guard FileManager.default.fileExists(atPath: directory) else {
            throw ServerError.invalidFilePath
        }

        self.stopped = false
        self.castDirectory = directory
        self.filePath = nil
        self.mediaPlaylistPath = nil
        self.masterPlaylistPath = nil
        self.expectedSize = 0
        self.segmenter = nil
        self.initSegmentSize = 0
        self.seekHandle = nil
        self.isComplete = false
        self.segmentCache = nil

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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    TransmuxLog.log("CAST LISTEN :\(port)", tag: "Server")
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    TransmuxLog.log("Cast listener failed: \(error)", tag: "Server", level: .error)
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
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

        let host = Self.getLANIPAddress() ?? "localhost"
        if host == "localhost" {
            TransmuxLog.log("WARNING: Could not determine LAN IP, Cast may not work", tag: "Server", level: .warn)
        }

        guard let url = URL(string: "http://\(host):\(port)/stream.m3u8") else {
            throw ServerError.invalidFilePath
        }

        TransmuxLog.log("CAST SERVING \(url) (dir: \(directory))", tag: "Server")
        return Session(localURL: url, port: port)
    }

    /// Enable or disable DLNA mode. When enabled, adds DLNA-specific response headers
    /// (transferMode.dlna.org, contentFeatures.dlna.org, Connection: keep-alive)
    /// to all served responses. Can be used with startDLNA() or start() (transmux pipeline).
    public func setDLNAMode(_ enabled: Bool) {
        dlnaMode = enabled
        TransmuxLog.log("DLNA mode \(enabled ? "ENABLED" : "DISABLED")", tag: "Server")
    }

    /// Start serving a growing MPEG-TS file for DLNA playback.
    /// The remux loop writes to the file in the background while this server
    /// serves it via HTTP range requests with DLNA headers.
    ///
    /// - Parameters:
    ///   - filePath: Path to the growing .ts file
    ///   - expectedSize: Estimated final file size (from input bitrate)
    /// - Returns: Session with the LAN-accessible URL
    public func startDLNA(filePath: String, expectedSize: Int64) async throws -> Session {
        if listener != nil {
            stop()
        }

        self.stopped = false
        self.dlnaFilePath = filePath
        self.dlnaMode = true
        self.filePath = filePath
        self.mediaPlaylistPath = nil
        self.masterPlaylistPath = nil
        self.expectedSize = expectedSize
        self.isComplete = false  // File is growing — remux in progress
        self.segmenter = nil
        self.initSegmentSize = 0
        self.seekHandle = nil
        self.segmentCache = nil
        self.castDirectory = nil

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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            nwListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    TransmuxLog.log("DLNA LISTEN :\(port)", tag: "Server")
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    TransmuxLog.log("DLNA listener failed: \(error)", tag: "Server", level: .error)
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: error)
                    }
                case .cancelled:
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

        let host = Self.getLANIPAddress() ?? "localhost"
        if host == "localhost" {
            TransmuxLog.log("WARNING: Could not determine LAN IP, DLNA may not work", tag: "Server", level: .warn)
        }

        // Serve at /stream.ts — the fallback handler in dispatchRequest() will serve it
        // with DLNA headers since dlnaMode=true
        guard let url = URL(string: "http://\(host):\(port)/stream.ts") else {
            throw ServerError.invalidFilePath
        }

        TransmuxLog.log("DLNA SERVING \(url) (est \(expectedSize / 1_048_576)MB)", tag: "Server")
        return Session(localURL: url, port: port)
    }

    /// Mark the transmux as complete. After this, empty reads mean real EOF.
    public func setComplete() {
        isComplete = true
        TransmuxLog.log("Transmux complete \u{2014} EOF on empty reads", tag: "Server")
    }

    /// Update expected size to the actual final file size.
    /// Called when DLNA transmux completes and the real size is known.
    public func setExpectedSize(_ size: Int64) {
        expectedSize = size
        TransmuxLog.log("Expected size updated to \(size) (\(size / 1_048_576)MB)", tag: "Server")
    }

    /// Stop serving and clean up all connections.
    public func stop() {
        stopped = true

        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()

        listener?.cancel()
        listener = nil
        filePath = nil
        mediaPlaylistPath = nil
        masterPlaylistPath = nil
        expectedSize = 0
        isComplete = false
        currentPort = 0
        segmenter = nil
        initSegmentSize = 0
        seekHandle = nil
        segmentCache?.clear()
        segmentCache = nil
        castDirectory = nil
        dlnaMode = false
        dlnaFilePath = nil

        TransmuxLog.log("STOPPED", tag: "Server")
        TransmuxLog.flush()
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
                    TransmuxLog.log("Read error: \(error)", tag: "Server", level: .error)
                }
                connection.cancel()
                return
            }

            guard let request = HTTPRequestParser.parse(data) else {
                TransmuxLog.log("Failed to parse HTTP request", tag: "Server", level: .warn)
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
        // Cast mode: serve files directly from the output directory
        if let castDir = self.castDirectory {
            dispatchCastRequest(request, connection: connection, directory: castDir)
            return
        }

        guard let filePath = self.filePath else {
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let expectedSize = self.expectedSize
        let complete = self.isComplete
        let mediaPlaylist = self.mediaPlaylistPath
        let masterPlaylist = self.masterPlaylistPath
        let seg = self.segmenter
        let initSize = self.initSegmentSize
        let handle = self.seekHandle
        let cache = self.segmentCache
        let isDLNA = self.dlnaMode

        let path = request.path

        // Route based on request path
        if path.hasSuffix(".m3u8") {
            // HLS playlist routing — disambiguate master, media, and subtitle playlists.
            // CRITICAL: /stream.m3u8 MUST always resolve to the media playlist (with segments),
            // and /master.m3u8 MUST resolve to the master playlist (with renditions).
            // Previously both resolved to the same file, causing an infinite redirect loop.
            let resolvedPlaylistPath: String?
            if path.contains("sub_"), let media = mediaPlaylist {
                // Subtitle playlist: resolve from the same directory as the media playlist
                let dir = (media as NSString).deletingLastPathComponent
                let fileName = (path as NSString).lastPathComponent
                resolvedPlaylistPath = (dir as NSString).appendingPathComponent(fileName)
            } else if path.contains("stream") {
                // Media playlist (segments): ALWAYS stream.m3u8
                resolvedPlaylistPath = mediaPlaylist
            } else if path.contains("master") {
                // Master playlist (renditions): master.m3u8 when it exists, fallback to media
                resolvedPlaylistPath = masterPlaylist ?? mediaPlaylist
            } else {
                // Unknown .m3u8 — try media playlist as fallback
                resolvedPlaylistPath = mediaPlaylist
            }

            if let resolvedPath = resolvedPlaylistPath {
                switch request.method {
                case .head:
                    handleHeadPlaylist(connection: connection, playlistPath: resolvedPath)
                case .get:
                    handleGetPlaylist(connection: connection, playlistPath: resolvedPath)
                }
            }
        } else if path.hasSuffix(".vtt") {
            // WebVTT subtitle file — resolve from the same directory as the media playlist
            if let media = mediaPlaylist {
                let dir = (media as NSString).deletingLastPathComponent
                let fileName = (path as NSString).lastPathComponent
                let vttPath = (dir as NSString).appendingPathComponent(fileName)
                handleGetVTT(connection: connection, vttPath: vttPath)
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
                isComplete: complete,
                cache: cache
            )
        } else {
            // Fallback: existing byte-range handler for direct mp4 access
            // DLNA TVs use this path to pull the fMP4 via HTTP range requests.
            switch request.method {
            case .head:
                handleHead(connection: connection, filePath: filePath, expectedSize: expectedSize, dlnaMode: isDLNA)
            case .get:
                handleGet(connection: connection, filePath: filePath, expectedSize: expectedSize, isComplete: complete, rangeHeader: request.rangeHeader, dlnaMode: isDLNA)
            }
        }
    }

    // MARK: - HLS Playlist Handlers

    /// Serve the static VOD HLS playlist file.
    /// The playlist is written once by HLSSegmenter with all virtual segments
    /// and #EXT-X-ENDLIST, so no polling or waiting is needed.
    private nonisolated func handleGetPlaylist(connection: NWConnection, playlistPath: String) {
        guard let playlistData = FileManager.default.contents(atPath: playlistPath) else {
            TransmuxLog.log("GET m3u8 404", tag: "Server", level: .warn)
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

        TransmuxLog.log("GET m3u8 200 \(playlistData.count)B", tag: "Server")

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

        TransmuxLog.log("HEAD m3u8 200 CL=\(fileSize)", tag: "Server")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - WebVTT Handler

    /// Serve a WebVTT subtitle file.
    private nonisolated func handleGetVTT(connection: NWConnection, vttPath: String) {
        guard let vttData = FileManager.default.contents(atPath: vttPath) else {
            TransmuxLog.log("GET vtt 404: \(vttPath)", tag: "Server", level: .warn)
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: text/vtt\r\n"
        header += "Content-Length: \(vttData.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        TransmuxLog.log("GET vtt 200 \(vttData.count)B \((vttPath as NSString).lastPathComponent)", tag: "Server")

        var responseData = Data(header.utf8)
        responseData.append(vttData)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Init Segment Handler

    /// Serve the init segment (ftyp+moov) from bytes [0, initSize) of stream.mp4.
    private nonisolated func handleGetInit(connection: NWConnection, filePath: String, initSize: Int64) {
        guard initSize > 0,
              let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            TransmuxLog.log("GET init.mp4 404", tag: "Server", level: .warn)
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

        TransmuxLog.log("GET init.mp4 200 \(data.count)B", tag: "Server")

        var responseData = Data(header.utf8)
        responseData.append(data)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Next-Segment Prefetch

    /// Trigger an immediate HLSSegmenter scan after serving a segment.
    /// This eliminates the 300ms scan timer delay for the next segment: when
    /// AVPlayer requests segment N+1 moments later, the data is already discovered.
    /// Deterministic prefetch (no prediction) — same approach as production CDNs.
    private nonisolated static func prefetchNextSegment(
        segIndex: Int,
        segmenter: HLSSegmenter
    ) {
        let targetDuration = segmenter.targetSegmentDuration
        let totalDuration = segmenter.totalDuration
        let nextStartTime = Double(segIndex + 1) * targetDuration
        guard nextStartTime < totalDuration else { return }
        segmenter.triggerScan()
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
        isComplete: Bool,
        cache: SegmentCache?
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

        // Step 0: Cache check — serve instantly from LRU cache if available.
        // The cache stores post-tfdt-rewritten segment data from previous serves.
        // Backward seeks to previously-visited positions hit the cache and avoid
        // the entire pipeline (no av_seek_frame, no polling, no disk read).
        if let cached = cache?.get(segmentIndex: segIndex) {
            TransmuxLog.segmentServed(segIndex: segIndex, startTime: startTime, endTime: endTime, bytes: cached.count, fragments: 0, source: "cache-hit", latestBuffered: latestBuffered)
            Self.sendSegmentResponse(connection: connection, data: cached, segIndex: segIndex, source: "cache-hit")
            return
        }

        // Step 1: Immediate fullness check — serve if transmux has produced
        // enough data to cover the full segment time range. We require
        // latestBuffered >= endTime (with epsilon) to ensure the fMP4 scanner
        // has processed ALL moof boxes whose start time falls within [startTime, endTime).
        // Epsilon tolerance (0.05s) handles DTS floating-point rounding:
        // e.g., latestBuffered=35.999 should pass for endTime=36.0.
        let fullnessEpsilon = 0.05
        if latestBuffered >= endTime - fullnessEpsilon {
            let fragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
            if !fragments.isEmpty {
                let segData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: fragments, trackTimescales: segmenter.trackTimescales)
                if !segData.isEmpty {
                    TransmuxLog.segmentServed(segIndex: segIndex, startTime: startTime, endTime: endTime, bytes: segData.count, fragments: fragments.count, source: "immediate", latestBuffered: latestBuffered)
                    cache?.put(segmentIndex: segIndex, data: segData)
                    Self.sendSegmentResponse(connection: connection, data: segData, segIndex: segIndex, source: "immediate")
                    Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                    return
                }
            }
        }

        // No seek handle — can't produce data. Respond 404.
        guard let handle = seekHandle else {
            TransmuxLog.segmentEvent("404 no-seek-handle", segIndex: segIndex, startTime: startTime, endTime: endTime, source: "none", extra: "complete=\(isComplete)")
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        // Transmux already complete but immediate fullness check above didn't find data.
        // Try serving partial fragments for this time range (common for the last segment
        // where declared duration exceeds actual remaining data).
        if isComplete {
            segmenter.triggerScan()
            let partialFragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
            if !partialFragments.isEmpty {
                let partialData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: partialFragments, trackTimescales: segmenter.trackTimescales)
                if !partialData.isEmpty {
                    TransmuxLog.segmentServed(segIndex: segIndex, startTime: startTime, endTime: endTime, bytes: partialData.count, fragments: partialFragments.count, source: "eof-partial", latestBuffered: latestBuffered)
                    cache?.put(segmentIndex: segIndex, data: partialData)
                    Self.sendSegmentResponse(connection: connection, data: partialData, segIndex: segIndex, source: "eof-partial")
                    Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                    return
                }
            }
            // Truly no data for this range — segment is beyond actual content
            TransmuxLog.segmentEvent("EOF-EMPTY", segIndex: segIndex, startTime: startTime, endTime: endTime, source: "eof", extra: "transmux complete, no fragments for range")
            let response = Data("HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n".utf8)
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

        // Capture seek generation at dispatch time. If a new seek arrives while
        // this polling loop runs, seekGeneration advances → we detect staleness
        // and abort with 404 instead of serving wrong-position data to AVPlayer.
        let seekGenAtDispatch = handle.seekGeneration

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
            let initialBuffered = latestBuffered  // snapshot at poll start

            for (phaseIdx, (pollCount, interval)) in pollPhases.enumerated() {
                currentPhaseIdx = phaseIdx

                // Fallback seek: at start of Phase 2, if no seek was triggered yet
                // and sequential transmux hasn't made meaningful progress, trigger seek.
                // "Meaningful progress" = advanced >= 2s since polling started.
                // Without this, a seek from 2082→2096 triggers fallback for seg_350
                // (startTime=2100) even though the sequential transmux is actively producing.
                if phaseIdx == 1 && !seekTriggered {
                    let currentBuffered = segmenter.latestBufferedSourceTime()
                    let progress = currentBuffered - initialBuffered
                    if currentBuffered < startTime + 1.0 && progress < 2.0 {
                        TransmuxLog.seekEvent(
                            "FALLBACK SEEK trigger",
                            seekTime: startTime,
                            latestTime: segmenter.latestTransmuxedTime(),
                            lastSeekTarget: handle.lastSeekTarget,
                            extra: "seg_\(String(format: "%03d", segIndex)) latestBuffered=\(String(format: "%.1f", currentBuffered))s progress=\(String(format: "%.1f", progress))s stalled"
                        )
                        handle.requestSeek(to: startTime)
                        seekTriggered = true
                    }
                }

                for _ in 0..<pollCount {
                    // Event-driven wait: when a seek was triggered, use the semaphore
                    // to wake up immediately when post-seek data is ready, instead of
                    // sleeping the full interval. Falls back to Thread.sleep for
                    // sequential catch-up (no seek triggered).
                    if seekTriggered {
                        let _ = handle.waitForSeekData(timeout: interval)
                    } else {
                        Thread.sleep(forTimeInterval: interval)
                    }
                    totalPolls += 1

                    // STALE CHECK: abort if a newer seek has arrived since dispatch.
                    // Serving old-position data after a seek causes visible "jump to old content".
                    if handle.seekGeneration > seekGenAtDispatch {
                        TransmuxLog.log("seg_\(String(format: "%03d", segIndex)): STALE (gen \(seekGenAtDispatch)\u{2192}\(handle.seekGeneration))", tag: "Server")
                        let staleResp = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
                        connection.send(content: staleResp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                        return
                    }

                    // Force HLSSegmenter to scan disk NOW instead of waiting for 300ms timer
                    segmenter.triggerScan()

                    // FULLNESS GATE: only check realSegments when latestBufferedSourceTime
                    // confirms enough data has been produced to cover the entire segment.
                    // Epsilon tolerance (0.05s) handles DTS floating-point rounding:
                    // e.g., bufferedTime=35.999 should pass for endTime=36.0.
                    let bufferedTime = segmenter.latestBufferedSourceTime()
                    guard bufferedTime >= endTime - fullnessEpsilon else {
                        // LIVE COMPLETION CHECK: Transmux may have finished during polling.
                        // The stale `isComplete` snapshot won't reflect this — check the
                        // live flag on the handle instead. Serve partial data if available.
                        if handle.isTransmuxComplete {
                            segmenter.triggerScan()
                            let eofFragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
                            if !eofFragments.isEmpty {
                                let eofData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: eofFragments, trackTimescales: segmenter.trackTimescales)
                                if !eofData.isEmpty {
                                    let elapsed = Date().timeIntervalSince(pollStart)
                                    TransmuxLog.segmentServed(segIndex: segIndex, startTime: startTime, endTime: endTime, bytes: eofData.count, fragments: eofFragments.count, source: "eof-during-poll", latestBuffered: bufferedTime, extra: "polls=\(totalPolls) elapsed=\(String(format: "%.2f", elapsed))s")
                                    cache?.put(segmentIndex: segIndex, data: eofData)
                                    Self.sendSegmentResponse(connection: connection, data: eofData, segIndex: segIndex, source: "eof-during-poll")
                                    Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                                    return
                                }
                            }
                            // Transmux complete but no data for this range — empty 200
                            TransmuxLog.segmentEvent("EOF-EMPTY-POLL", segIndex: segIndex, startTime: startTime, endTime: endTime, source: "eof", extra: "transmux completed during poll, no fragments")
                            let emptyResp = Data("HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n".utf8)
                            connection.send(content: emptyResp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                                connection.cancel()
                            })
                            return
                        }

                        // Log only when truly stalled (phase 2+)
                        if totalPolls % 80 == 0 {
                            TransmuxLog.log(
                                "seg_\(String(format: "%03d", segIndex)): waiting \(String(format: "%.1f", endTime - bufferedTime))s gap",
                                tag: "Server"
                            )
                        }
                        continue
                    }

                    // Fullness gate passed — check for actual segment byte ranges
                    let fragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
                    if !fragments.isEmpty {
                        let segData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: fragments, trackTimescales: segmenter.trackTimescales)
                        if !segData.isEmpty {
                            let elapsed = Date().timeIntervalSince(pollStart)
                            let source = seekTriggered ? "seek-redirect" : "sequential-wait"
                            TransmuxLog.segmentServed(
                                segIndex: segIndex,
                                startTime: startTime,
                                endTime: endTime,
                                bytes: segData.count,
                                fragments: fragments.count,
                                source: source,
                                latestBuffered: bufferedTime,
                                extra: "polls=\(totalPolls) elapsed=\(String(format: "%.2f", elapsed))s phase=\(phaseIdx+1)"
                            )
                            cache?.put(segmentIndex: segIndex, data: segData)
                            Self.sendSegmentResponse(connection: connection, data: segData, segIndex: segIndex, source: source)
                            Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                            return
                        }
                    }

                    // GAP DETECTION: Fullness gate passed (enough total time produced)
                    // but no real segments exist for this time range. This means we
                    // seeked PAST this region — there's a hole in coverage.
                    // Trigger a seek to produce the missing data.
                    if !seekTriggered {
                        TransmuxLog.seekEvent(
                            "GAP SEEK trigger",
                            seekTime: startTime,
                            latestTime: segmenter.latestTransmuxedTime(),
                            lastSeekTarget: handle.lastSeekTarget,
                            extra: "seg_\(String(format: "%03d", segIndex)) [\(String(format: "%.1f-%.1f", startTime, endTime))s] buffered=\(String(format: "%.1f", bufferedTime))s but no segments \u{2014} data gap"
                        )
                        handle.requestSeek(to: startTime)
                        seekTriggered = true
                    }
                }
            }

            // Timeout — did not produce full segment data in ~11.5s
            let elapsed = Date().timeIntervalSince(pollStart)
            var finalBuffered = segmenter.latestBufferedSourceTime()
            let finalLatest = segmenter.latestTransmuxedTime()

            // STALE CHECK before timeout fallback
            if handle.seekGeneration > seekGenAtDispatch {
                TransmuxLog.log("seg_\(String(format: "%03d", segIndex)): STALE at timeout (gen \(seekGenAtDispatch)\u{2192}\(handle.seekGeneration))", tag: "Server")
                let staleResp = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: staleResp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            // Tier 1: Retry seek if no seek was triggered during the main polling loop.
            // The sequential transmux may have stalled. Give it one more chance with a
            // fresh seek and 3 seconds of fast polling.
            if !seekTriggered && !handle.isTransmuxComplete {
                TransmuxLog.seekEvent(
                    "RETRY SEEK trigger",
                    seekTime: startTime,
                    latestTime: finalLatest,
                    lastSeekTarget: handle.lastSeekTarget,
                    extra: "seg_\(String(format: "%03d", segIndex)) timeout-retry"
                )
                handle.requestSeek(to: startTime)
                for _ in 0..<30 {
                    Thread.sleep(forTimeInterval: 0.1)
                    segmenter.triggerScan()
                    let retryBuffered = segmenter.latestBufferedSourceTime()
                    if retryBuffered >= endTime - fullnessEpsilon {
                        let retryFragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
                        if !retryFragments.isEmpty {
                            let retryData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: retryFragments, trackTimescales: segmenter.trackTimescales)
                            if !retryData.isEmpty {
                                let totalElapsed = Date().timeIntervalSince(pollStart)
                                TransmuxLog.segmentServed(
                                    segIndex: segIndex, startTime: startTime, endTime: endTime,
                                    bytes: retryData.count, fragments: retryFragments.count,
                                    source: "retry-seek", latestBuffered: retryBuffered,
                                    extra: "elapsed=\(String(format: "%.2f", totalElapsed))s"
                                )
                                cache?.put(segmentIndex: segIndex, data: retryData)
                                Self.sendSegmentResponse(connection: connection, data: retryData, segIndex: segIndex, source: "retry-seek")
                                Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                                return
                            }
                        }
                    }
                    // Check if transmux completed during retry
                    if handle.isTransmuxComplete { break }
                }
                finalBuffered = segmenter.latestBufferedSourceTime()
            }

            // Tier 2: Serve partial fragments if any exist for this range
            segmenter.triggerScan()
            let timeoutFragments = segmenter.realSegments(inTimeRange: startTime, end: endTime)
            if !timeoutFragments.isEmpty {
                let timeoutData = Self.readAndRewriteFragmentsMmap(filePath: filePath, fragments: timeoutFragments, trackTimescales: segmenter.trackTimescales)
                if !timeoutData.isEmpty {
                    TransmuxLog.segmentServed(
                        segIndex: segIndex, startTime: startTime, endTime: endTime,
                        bytes: timeoutData.count, fragments: timeoutFragments.count,
                        source: "timeout-partial", latestBuffered: finalBuffered,
                        extra: "polls=\(totalPolls) elapsed=\(String(format: "%.2f", elapsed))s phase=\(currentPhaseIdx+1)"
                    )
                    cache?.put(segmentIndex: segIndex, data: timeoutData)
                    Self.sendSegmentResponse(connection: connection, data: timeoutData, segIndex: segIndex, source: "timeout-partial")
                    Self.prefetchNextSegment(segIndex: segIndex, segmenter: segmenter)
                    return
                }
            }

            TransmuxLog.segmentEvent(
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

    /// Read fragment byte ranges from a file, rewriting each fragment's tfdt
    /// values to match the source timeline. The internal fMP4 keeps monotonic
    /// DTS (required by FFmpeg), but AVPlayer expects tfdt = sourceStartTime * timescale.
    /// This patches each moof's tfdt in-place before concatenating.
    private nonisolated static func readAndRewriteFragments(
        filePath: String,
        fragments: [HLSSegmenter.RealFragment],
        trackTimescales: [UInt32: UInt32]
    ) -> Data {
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            // File gone = session cleanup happened before polling loop exited; not a real error
            TransmuxLog.log("readAndRewriteFragments: file gone (session cleanup)", tag: "Server", level: .debug)
            return Data()
        }
        defer { try? fileHandle.close() }

        // If no timescales parsed, skip rewriting (safe fallback)
        let shouldRewrite = !trackTimescales.isEmpty

        var result = Data()
        for fragment in fragments {
            do {
                try fileHandle.seek(toOffset: UInt64(fragment.offset))
                var chunk = fileHandle.readData(ofLength: Int(fragment.length))
                if shouldRewrite && !chunk.isEmpty {
                    rewriteTfdtInPlace(&chunk, sourceTime: fragment.sourceStartTime, trackTimescales: trackTimescales)
                }
                result.append(chunk)
            } catch {
                TransmuxLog.log("readAndRewriteFragments: seek/read failed at offset \(fragment.offset): \(error)", tag: "Server", level: .error)
            }
        }
        return result
    }

    /// mmap-based variant of readAndRewriteFragments for faster I/O.
    /// Uses memory-mapped file access instead of FileHandle seek+read,
    /// eliminating per-fragment kernel syscall overhead. Falls back to
    /// FileHandle on mmap failure (e.g., file too new or OS limit).
    ///
    /// Safe for growing files: maps with current fstat size, reads only
    /// within bounds, and unmaps immediately after use (short-lived mapping).
    private nonisolated static func readAndRewriteFragmentsMmap(
        filePath: String,
        fragments: [HLSSegmenter.RealFragment],
        trackTimescales: [UInt32: UInt32]
    ) -> Data {
        let fd = open(filePath, O_RDONLY)
        guard fd >= 0 else {
            return readAndRewriteFragments(filePath: filePath, fragments: fragments, trackTimescales: trackTimescales)
        }
        defer { close(fd) }

        var stat_buf = stat()
        guard fstat(fd, &stat_buf) == 0 else {
            return readAndRewriteFragments(filePath: filePath, fragments: fragments, trackTimescales: trackTimescales)
        }
        let fileSize = Int(stat_buf.st_size)
        guard fileSize > 0 else { return Data() }

        guard let mapped = mmap(nil, fileSize, PROT_READ, MAP_SHARED, fd, 0),
              mapped != MAP_FAILED else {
            return readAndRewriteFragments(filePath: filePath, fragments: fragments, trackTimescales: trackTimescales)
        }
        defer { munmap(mapped, fileSize) }

        let shouldRewrite = !trackTimescales.isEmpty
        var result = Data()

        for (idx, fragment) in fragments.enumerated() {
            let offset = Int(fragment.offset)
            let length = Int(fragment.length)
            guard offset >= 0 && length > 0 && offset + length <= fileSize else {
                TransmuxLog.log("FRAG[\(idx)] SKIP: offset=\(offset) len=\(length) fileSize=\(fileSize)", tag: "Server", level: .warn)
                continue
            }

            // Copy from mapped region (copy required since rewriteTfdtInPlace mutates)
            var chunk = Data(bytes: mapped.advanced(by: offset), count: length)
            if shouldRewrite && !chunk.isEmpty {
                rewriteTfdtInPlace(&chunk, sourceTime: fragment.sourceStartTime, trackTimescales: trackTimescales)
            }
            result.append(chunk)
        }
        return result
    }

    /// Scan a moof+mdat chunk and rewrite tfdt baseMediaDecodeTime values in-place.
    /// For each traf inside a moof:
    /// 1. Parse tfhd → extract track_ID
    /// 2. Find tfdt → read version byte
    /// 3. Compute newTfdt = UInt64(sourceTime * Double(timescale))
    /// 4. Write newTfdt (big-endian) over the existing baseMediaDecodeTime field
    private nonisolated static func rewriteTfdtInPlace(
        _ data: inout Data,
        sourceTime: Double,
        trackTimescales: [UInt32: UInt32]
    ) {
        let dataLen = data.count
        var pos = 0

        // Iterate top-level boxes in this chunk
        while pos + 8 <= dataLen {
            guard let box = MP4BoxParser.readBoxHeader(data: data, at: pos) else { break }
            let boxSize = Int(box.size)
            if boxSize < 8 { break }
            let boxEnd = pos + boxSize
            if boxEnd > dataLen { break }

            if box.type == "moof" {
                // Iterate children of moof
                var moofChild = pos + 8
                while moofChild + 8 <= boxEnd {
                    guard let child = MP4BoxParser.readBoxHeader(data: data, at: moofChild) else { break }
                    let childSize = Int(child.size)
                    if childSize < 8 { break }
                    let childEnd = moofChild + childSize
                    if childEnd > boxEnd { break }

                    if child.type == "traf" {
                        rewriteTfdtInTraf(&data, trafStart: moofChild, trafEnd: childEnd, sourceTime: sourceTime, trackTimescales: trackTimescales)
                    }

                    moofChild = childEnd
                }
            }

            pos = boxEnd
        }
    }

    /// Rewrite tfdt inside a single traf box.
    /// Extracts track_ID from tfhd, then finds tfdt and overwrites baseMediaDecodeTime.
    private nonisolated static func rewriteTfdtInTraf(
        _ data: inout Data,
        trafStart: Int,
        trafEnd: Int,
        sourceTime: Double,
        trackTimescales: [UInt32: UInt32]
    ) {
        var trackID: UInt32?
        var tfdtPos: Int?
        var tfdtVersion: UInt8?

        // Scan traf children for tfhd and tfdt
        var offset = trafStart + 8
        while offset + 8 <= trafEnd {
            guard let box = MP4BoxParser.readBoxHeader(data: data, at: offset) else { break }
            let boxSize = Int(box.size)
            if boxSize < 8 { break }
            let boxEnd = offset + boxSize
            if boxEnd > trafEnd { break }

            if box.type == "tfhd" {
                // tfhd layout: [header][version(1)+flags(3)][track_ID(4)]
                let idOffset = offset + 8 + 4 // skip header + version/flags
                if idOffset + 4 <= boxEnd {
                    trackID = data.withUnsafeBytes { ptr in
                        ptr.loadUnaligned(fromByteOffset: idOffset, as: UInt32.self).bigEndian
                    }
                }
            } else if box.type == "tfdt" {
                // tfdt layout: [header][version(1)+flags(3)][baseMediaDecodeTime]
                let versionOffset = offset + 8
                if versionOffset + 4 <= boxEnd {
                    tfdtPos = offset
                    tfdtVersion = data[versionOffset]
                }
            }

            offset = boxEnd
        }

        // Rewrite tfdt if we found both track_ID and tfdt
        guard let tid = trackID, let pos = tfdtPos, let version = tfdtVersion else { return }
        guard let timescale = trackTimescales[tid] else {
            TransmuxLog.log("rewriteTfdt: unknown track_ID \(tid), skipping", tag: "Server", level: .warn)
            return
        }

        let newTfdt = UInt64(sourceTime * Double(timescale))
        let valueOffset = pos + 8 + 4 // header + version/flags

        if version == 1 {
            // 64-bit baseMediaDecodeTime
            guard valueOffset + 8 <= trafEnd else { return }
            let oldTfdt = data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: valueOffset, as: UInt64.self).bigEndian
            }
            TransmuxLog.log("tfdt track=\(tid) ts=\(timescale) old=\(oldTfdt)(\(String(format: "%.3f", Double(oldTfdt) / Double(timescale)))s) new=\(newTfdt)(\(String(format: "%.3f", sourceTime))s)", tag: "Server", level: .debug)
            // Skip rewrite when old and new are close — preserves original per-track
            // timing for pre-seek segments where the video-derived sourceStartTime
            // differs slightly from the audio's actual DTS (~72ms typical).
            let diffTicks = newTfdt > oldTfdt ? newTfdt - oldTfdt : oldTfdt - newTfdt
            if diffTicks < UInt64(timescale / 2) {
                return  // Within 0.5s tolerance — keep original tfdt
            }
            var bigEndian = newTfdt.bigEndian
            withUnsafeBytes(of: &bigEndian) { src in
                data.replaceSubrange(valueOffset..<(valueOffset + 8), with: src)
            }
        } else {
            // 32-bit baseMediaDecodeTime (v0)
            guard valueOffset + 4 <= trafEnd else { return }
            if newTfdt > UInt64(UInt32.max) {
                TransmuxLog.log("rewriteTfdt: newTfdt \(newTfdt) overflows UInt32 for track \(tid), skipping", tag: "Server", level: .warn)
                return
            }
            let oldTfdt = UInt64(data.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: valueOffset, as: UInt32.self).bigEndian
            })
            TransmuxLog.log("tfdt track=\(tid) ts=\(timescale) old=\(oldTfdt)(\(String(format: "%.3f", Double(oldTfdt) / Double(timescale)))s) new=\(UInt32(newTfdt))(\(String(format: "%.3f", sourceTime))s)", tag: "Server", level: .debug)
            // Skip rewrite when old and new are close (same tolerance as v1 branch)
            let diffTicks = newTfdt > oldTfdt ? newTfdt - oldTfdt : oldTfdt - newTfdt
            if diffTicks < UInt64(timescale / 2) {
                return  // Within 0.5s tolerance — keep original tfdt
            }
            var bigEndian = UInt32(newTfdt).bigEndian
            withUnsafeBytes(of: &bigEndian) { src in
                data.replaceSubrange(valueOffset..<(valueOffset + 4), with: src)
            }
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

    private nonisolated func handleHead(connection: NWConnection, filePath: String, expectedSize: Int64, dlnaMode: Bool = false) {
        let fileSize: Int64 = expectedSize > 0 ? expectedSize : Self.currentFileSize(filePath)
        let contentType = Self.mimeType(for: filePath)

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(fileSize)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        if dlnaMode {
            header += Self.dlnaHeaders()
            header += "Connection: keep-alive\r\n"
        } else {
            header += "Connection: close\r\n"
        }
        header += "\r\n"

        TransmuxLog.log("HEAD 200 CL=\(fileSize)\(dlnaMode ? " [DLNA]" : "")", tag: "Server")

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
        rangeHeader: String?,
        dlnaMode: Bool = false
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
                TransmuxLog.log("GET 416 rangeStart=\(rangeStart) fileSize=\(waitedFileSize)", tag: "Server", level: .warn)
                connection.send(content: Data(resp.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
        }

        // Cases 1 & 2: respond with 206 and the FULL requested Content-Range.
        // FigHTTP requires Content-Length to match the requested range exactly.
        let contentType = Self.mimeType(for: filePath)
        var header = "HTTP/1.1 206 Partial Content\r\n"
        header += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        if dlnaMode {
            header += Self.dlnaHeaders()
            header += "Connection: keep-alive\r\n"
        } else {
            header += "Connection: close\r\n"
        }
        header += "\r\n"

        TransmuxLog.log("GET 206 bytes=\(rangeStart)-\(rangeEnd)/\(totalSize) CL=\(contentLength)\(dlnaMode ? " [DLNA]" : "")", tag: "Server")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error = error {
                TransmuxLog.log("Send headers failed: \(error)", tag: "Server", level: .error)
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

        TransmuxLog.log("GET 200 CL=\(totalSize)", tag: "Server")

        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { error in
            if let error = error {
                TransmuxLog.log("Send headers failed: \(error)", tag: "Server", level: .error)
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
                TransmuxLog.log("Cannot open file: \(filePath)", tag: "Server", level: .error)
                connection.cancel()
                return
            }
            defer { try? fileHandle.close() }

            if offset > 0 {
                do {
                    try fileHandle.seek(toOffset: UInt64(offset))
                } catch {
                    TransmuxLog.log("Seek to \(offset) failed: \(error)", tag: "Server", level: .error)
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
                        TransmuxLog.log("EOF at \(currentOffset) served=\(bytesToServe - remaining)B", tag: "Server")
                        break
                    }

                    emptyReadCount += 1
                    if emptyReadCount >= maxEmptyReads {
                        TransmuxLog.log("Timeout at offset \(currentOffset) served=\(bytesToServe - remaining)B", tag: "Server", level: .warn)
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.1)

                    // Re-check if file has grown past our position
                    let fileSize = currentFileSize(filePath)
                    if fileSize > currentOffset {
                        do {
                            try fileHandle.seek(toOffset: UInt64(currentOffset))
                        } catch {
                            TransmuxLog.log("Re-seek failed at \(currentOffset)", tag: "Server", level: .error)
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
                    TransmuxLog.log("Client disconnected at \(currentOffset) served=\(bytesToServe - remaining)B", tag: "Server")
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

    // MARK: - LAN IP Address

    /// Determine the device's LAN IP address for AirPlay compatibility.
    /// Apple TV resolves `localhost` to itself, so we need the actual LAN IP
    // MARK: - DLNA Headers

    /// DLNA-specific HTTP headers added when dlnaMode is enabled.
    /// These headers tell DLNA TVs how to handle the content:
    /// - transferMode.dlna.org: Streaming (allows seeking)
    /// - contentFeatures.dlna.org: OP=01 (range supported), CI=0 (not transcoded)
    /// - Accept-Ranges: bytes (explicit range support)
    /// Determine MIME type from file path extension.
    private nonisolated static func mimeType(for filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "video/mp4"
        case "ts", "m2ts": return "video/mp2t"
        case "mkv": return "video/x-matroska"
        case "avi": return "video/x-msvideo"
        case "mov": return "video/quicktime"
        case "m3u8": return "application/x-mpegURL"
        default: return "video/mp4"
        }
    }

    private nonisolated static func dlnaHeaders() -> String {
        var h = ""
        h += "transferMode.dlna.org: Streaming\r\n"
        h += "contentFeatures.dlna.org: DLNA.ORG_PN=*;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\r\n"
        return h
    }

    /// so AirPlay Video can fetch segments from this device over the network.
    ///
    /// Scans IPv4 interfaces, preferring en0 (WiFi). Filters out loopback (127.x.x.x)
    /// and link-local (169.254.x.x) addresses. Works on iOS, macOS, and tvOS.
    private nonisolated static func getLANIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var bestIP: String?
        var fallbackIP: String?

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            defer { current = addr.pointee.ifa_next }

            // Only IPv4 (AF_INET)
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            // Extract interface name and IP
            let name = String(cString: addr.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)

            // Skip loopback and link-local
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }

            // Prefer en0 (WiFi on Apple devices)
            if name == "en0" {
                bestIP = ip
            } else if fallbackIP == nil {
                fallbackIP = ip
            }
        }

        return bestIP ?? fallbackIP
    }

    // MARK: - Cast Mode Handlers

    /// Dispatch requests in Cast mode — serve files directly from the output directory.
    /// Supports .m3u8 playlists and .ts segment files. CORS headers are included for Cast.
    private func dispatchCastRequest(_ request: HTTPRequestParser.Request, connection: NWConnection, directory: String) {
        let path = request.path
        let fileName = (path as NSString).lastPathComponent

        // Security: only serve .m3u8 and .ts files
        guard fileName.hasSuffix(".m3u8") || fileName.hasSuffix(".ts") else {
            TransmuxLog.log("CAST 404 unsupported: \(path)", tag: "Server", level: .warn)
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let filePath = (directory as NSString).appendingPathComponent(fileName)

        // For .ts segments that don't exist yet, poll briefly (transmux in progress)
        if fileName.hasSuffix(".ts") && !FileManager.default.fileExists(atPath: filePath) {
            handleCastSegmentWait(connection: connection, filePath: filePath, fileName: fileName)
            return
        }

        // Serve the file
        handleCastServeFile(connection: connection, filePath: filePath, fileName: fileName)
    }

    /// Serve a static file (.m3u8 or .ts) from the Cast output directory.
    private nonisolated func handleCastServeFile(connection: NWConnection, filePath: String, fileName: String) {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            TransmuxLog.log("CAST 404 \(fileName)", tag: "Server", level: .warn)
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let contentType: String
        if fileName.hasSuffix(".m3u8") {
            contentType = "application/vnd.apple.mpegurl"
        } else {
            contentType = "video/mp2t"
        }

        var header = "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(data.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        if fileName.hasSuffix(".m3u8") {
            header += "Cache-Control: no-cache, no-store\r\n"
        } else {
            header += "Cache-Control: public, max-age=3600\r\n"
        }
        header += "Connection: close\r\n"
        header += "\r\n"

        TransmuxLog.log("CAST 200 \(fileName) \(data.count)B", tag: "Server")

        var responseData = Data(header.utf8)
        responseData.append(data)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Wait for a .ts segment file to appear on disk (transmux in progress).
    /// Polls for up to 15 seconds, then returns 404 if the segment never appeared.
    private nonisolated func handleCastSegmentWait(connection: NWConnection, filePath: String, fileName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Poll for the segment file: 150 × 100ms = 15s timeout
            for i in 0..<150 {
                if FileManager.default.fileExists(atPath: filePath) {
                    // File exists — but wait a tiny bit for it to be fully written
                    Thread.sleep(forTimeInterval: 0.05)
                    self.handleCastServeFile(connection: connection, filePath: filePath, fileName: fileName)
                    return
                }
                Thread.sleep(forTimeInterval: 0.1)

                if i > 0 && i % 50 == 0 {
                    TransmuxLog.log("CAST waiting for \(fileName) (\(i / 10)s)", tag: "Server")
                }
            }

            // Timeout
            TransmuxLog.log("CAST 404 timeout \(fileName)", tag: "Server", level: .warn)
            let response = Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
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

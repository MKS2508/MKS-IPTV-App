import Foundation
import Network

// MARK: - TransmuxServer

/// Native NWListener-based HTTP server that serves a growing fMP4 file and its
/// byte-range HLS playlist, produced by TransmuxingService + HLSSegmenter.
/// Supports HEAD, GET, and Range requests so AVPlayer can stream HLS while the
/// transmux is still in progress.
///
/// Architecture:
/// ```
/// FFmpeg C API writes fMP4 → /tmp/.../stream.mp4 (growing file)
/// HLSSegmenter scans fMP4  → /tmp/.../stream.m3u8 (growing playlist)
///                                 ↑ serves both files
/// TransmuxServer (NWListener:8100-8199)
///   GET /stream.m3u8 → 200 (playlist, no-cache)
///   GET /stream.mp4  → 206 (byte ranges)
///                                 ↑ HTTP GET/HEAD
/// AVPlayer (http://localhost:81XX/stream.m3u8)
/// ```
actor TransmuxServer {

    static let shared = TransmuxServer()

    // MARK: - Types

    struct Session {
        let localURL: URL
        let port: UInt16
    }

    enum ServerError: LocalizedError {
        case portExhausted
        case invalidFilePath
        case alreadyRunning

        var errorDescription: String? {
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

    private let networkQueue = DispatchQueue(label: "TransmuxServer.network", qos: .userInitiated)
    private let portRange: Range<UInt16> = 8100..<8200

    private init() {}

    // MARK: - Public API

    /// Start serving a growing fMP4 file and its HLS playlist.
    /// Called after avformat_write_header succeeds and HLSSegmenter has written
    /// the initial playlist. Waits for the NWListener to reach `.ready` state
    /// before returning, so AVPlayer can connect immediately.
    func start(filePath: String, playlistPath: String, expectedSize: Int64) async throws -> Session {
        if listener != nil {
            stop()
        }

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ServerError.invalidFilePath
        }

        self.filePath = filePath
        self.playlistPath = playlistPath
        self.expectedSize = expectedSize
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
    func setComplete() {
        isComplete = true
        print("[TransmuxServer] Transmux complete — EOF on empty reads")
    }

    /// Stop serving and clean up all connections.
    func stop() {
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

        // Route based on request path
        let isPlaylistRequest = request.path.hasSuffix(".m3u8")

        if isPlaylistRequest, let playlistPath = playlist {
            switch request.method {
            case .head:
                handleHeadPlaylist(connection: connection, playlistPath: playlistPath)
            case .get:
                handleGetPlaylist(connection: connection, playlistPath: playlistPath)
            }
        } else {
            switch request.method {
            case .head:
                handleHead(connection: connection, filePath: filePath, expectedSize: expectedSize)
            case .get:
                handleGet(connection: connection, filePath: filePath, expectedSize: expectedSize, isComplete: complete, rangeHeader: request.rangeHeader)
            }
        }
    }

    // MARK: - HLS Playlist Handlers

    /// Serve the HLS playlist file. No caching — AVPlayer must get fresh content
    /// each poll cycle to discover new segments.
    ///
    /// **Important:** An EVENT playlist with 0 media segments causes AVPlayer to
    /// give up with error -12888 ("Playlist File unchanged for longer than 1.5 *
    /// target duration"). To prevent this, we wait for the playlist to contain at
    /// least one `#EXTINF` entry before serving. The HLSSegmenter writes segments
    /// within ~1 second of the remux loop producing data.
    private nonisolated func handleGetPlaylist(connection: NWConnection, playlistPath: String) {
        // Poll until the playlist has at least one media segment.
        // 75 iterations * 200ms = 15 seconds max wait.
        var data: Data?
        for attempt in 0..<75 {
            if let contents = FileManager.default.contents(atPath: playlistPath),
               let str = String(data: contents, encoding: .utf8),
               str.contains("#EXTINF") {
                data = contents
                if attempt > 0 {
                    print("[TransmuxServer] Playlist ready after \(attempt) polls (\(contents.count) bytes)")
                }
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Fallback: serve whatever we have (even if 0 segments)
        if data == nil {
            data = FileManager.default.contents(atPath: playlistPath)
            print("[TransmuxServer] WARNING: Serving playlist without segments (timeout)")
        }

        guard let playlistData = data else {
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

        print("[TransmuxServer] GET /stream.m3u8 -> 200 (\(playlistData.count) bytes)")

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
struct HTTPRequestParser {

    enum Method: String {
        case get = "GET"
        case head = "HEAD"
    }

    struct Request {
        let method: Method
        let path: String
        let rangeHeader: String?
    }

    /// Parse a raw HTTP request from bytes.
    static func parse(_ data: Data) -> Request? {
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

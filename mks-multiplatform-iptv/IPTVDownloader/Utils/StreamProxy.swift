import Foundation

#if canImport(FlyingFox)
import FlyingFox
#endif

/// An HTTP proxy that forwards requests to a backend URL with streaming support.
///
/// ## Purpose
/// KSPlayer's bundled FFmpeg (n6.1) has a buffer overflow when parsing HTTP URLs
/// longer than ~500 characters. IPTV servers behind Cloudflare use 302 redirects
/// to tokenized URLs that can exceed 900 characters, causing `EXC_BAD_ACCESS`.
///
/// This proxy solves the problem by:
/// 1. Listening on localhost with a short URL (e.g., `http://localhost:9100/0`)
/// 2. Receiving HTTP requests from KSPlayer
/// 3. Forwarding requests to the real backend URL (with the long token)
/// 4. Streaming the response back to KSPlayer in chunks
///
/// ## Architecture
/// ```
/// KSPlayer (FFmpeg)
///     ↓ HTTP GET http://localhost:9100/0
/// [StreamProxy HTTPServer :9100]
///     ↓ HTTP GET http://backend:8080/...900chars...
/// [Backend: 89.34.226.233:8080]
///     ↓ HTTP 206 Partial Content (streaming)
/// [StreamProxy]
///     ↓ Stream chunks to KSPlayer
/// ```
actor StreamProxy {

    // MARK: - Types

    /// Error thrown by StreamProxy operations.
    enum ProxyError: LocalizedError {
        case portExhausted(tried: Range<UInt16>)
        case proxyNotRunning
        case invalidBackendURL

        var errorDescription: String? {
            switch self {
            case .portExhausted(let tried):
                return "Could not find available port in range \(tried.lowerBound)-\(tried.upperBound)"
            case .proxyNotRunning:
                return "Proxy is not running"
            case .invalidBackendURL:
                return "Invalid backend URL"
            }
        }
    }

    /// Information about an active proxy session.
    struct ProxySession {
        /// The localhost URL that players should connect to.
        let localURL: URL
        /// The backend URL being proxied.
        let backendURL: URL
        /// The port number allocated for this session.
        let port: UInt16
        /// Unique identifier for this session.
        let id: Int
    }

    // MARK: - Properties

    /// Shared instance for convenience.
    static let shared = StreamProxy()

    /// Active proxy sessions indexed by session ID.
    private(set) var sessions: [Int: ProxySession] = [:]

    #if canImport(FlyingFox)
    private var servers: [UInt16: HTTPServer] = [:]
    private var serverTasks: [UInt16: Task<Void, Never>] = [:]
    #endif

    /// Next session ID.
    private var nextSessionID = 0

    /// Port range to try when allocating.
    private let portRange: Range<UInt16>

    // MARK: - Initialization

    /// Creates a new StreamProxy instance.
    /// - Parameter portRange: Range of ports to try when allocating (default 9100-9199).
    init(portRange: Range<UInt16> = 9100..<9200) {
        self.portRange = portRange
    }

    // MARK: - Public API

    /// Starts a proxy session for the given backend URL.
    func startProxy(for backendURL: URL, preferredPort: UInt16? = nil) async throws -> ProxySession {
        #if canImport(FlyingFox)
        let port = try findAvailablePort(preferred: preferredPort)

        let sessionID = nextSessionID
        nextSessionID += 1

        guard let localURL = URL(string: "http://localhost:\(port)/\(sessionID)") else {
            throw ProxyError.invalidBackendURL
        }

        let session = ProxySession(
            localURL: localURL,
            backendURL: backendURL,
            port: port,
            id: sessionID
        )
        sessions[sessionID] = session

        let server = HTTPServer(port: port)
        let backend = backendURL

        // Handle GET requests with streaming
        await server.appendRoute("GET /*") { request in
            await Self.forwardRequestStreaming(request, to: backend)
        }

        await server.appendRoute("HEAD /*") { request in
            await Self.forwardHeadRequest(request, to: backend)
        }

        servers[port] = server

        let serverTask = Task.detached { [server] in
            do {
                try await server.run()
            } catch {
                print("[StreamProxy] Server on port \(port) stopped: \(error)")
            }
        }
        serverTasks[port] = serverTask

        print("[StreamProxy] Started HTTP proxy session #\(sessionID) on port \(port)")
        print("[StreamProxy]   Local:   \(localURL.absoluteString)")
        print("[StreamProxy]   Backend: \(backendURL.absoluteString.prefix(80))...")

        return session
        #else
        print("[StreamProxy] FlyingFox not available, returning backend URL directly")
        let sessionID = nextSessionID
        nextSessionID += 1
        return ProxySession(
            localURL: backendURL,
            backendURL: backendURL,
            port: 0,
            id: sessionID
        )
        #endif
    }

    func stop(sessionID: Int) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }

        #if canImport(FlyingFox)
        serverTasks[session.port]?.cancel()
        serverTasks.removeValue(forKey: session.port)
        servers.removeValue(forKey: session.port)
        #endif

        print("[StreamProxy] Stopped proxy session #\(sessionID)")
    }

    func stopAll() {
        #if canImport(FlyingFox)
        for (port, task) in serverTasks {
            task.cancel()
            print("[StreamProxy] Stopped server on port \(port)")
        }
        serverTasks.removeAll()
        servers.removeAll()
        #endif
        sessions.removeAll()
        print("[StreamProxy] All proxy sessions stopped")
    }

    func session(for url: URL) -> ProxySession? {
        guard url.host == "localhost",
              let port = url.port,
              let session = sessions.values.first(where: { $0.port == port }) else {
            return nil
        }
        return session
    }

    // MARK: - Private

    private func findAvailablePort(preferred: UInt16?) throws -> UInt16 {
        #if canImport(FlyingFox)
        if let preferred = preferred, !servers.keys.contains(preferred) {
            return preferred
        }
        for port in portRange {
            if !servers.keys.contains(port) {
                return port
            }
        }
        throw ProxyError.portExhausted(tried: portRange)
        #else
        return 0
        #endif
    }

    #if canImport(FlyingFox)
    /// Forwards a HEAD request (just headers, no body)
    private static func forwardHeadRequest(_ clientRequest: HTTPRequest, to backendURL: URL) async -> HTTPResponse {
        do {
            var backendRequest = URLRequest(url: backendURL)
            backendRequest.httpMethod = "HEAD"
            backendRequest.timeoutInterval = 30

            backendRequest.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")

            let (_, response) = try await URLSession.shared.data(for: backendRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(statusCode: .badGateway)
            }

            var headers: [HTTPHeader: String] = [:]
            headers[HTTPHeader("Content-Type")] = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            headers[HTTPHeader("Accept-Ranges")] = "bytes"
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                headers[HTTPHeader("Content-Length")] = contentLength
            }
            headers[HTTPHeader("Access-Control-Allow-Origin")] = "*"

            print("[StreamProxy] HEAD → HTTP \(httpResponse.statusCode)")

            return HTTPResponse(
                statusCode: mapStatusCode(httpResponse.statusCode),
                headers: headers,
                body: Data()
            )
        } catch {
            print("[StreamProxy] HEAD failed: \(error.localizedDescription)")
            return HTTPResponse(statusCode: .badGateway)
        }
    }

    /// Forwards a GET request with streaming support for large files
    private static func forwardRequestStreaming(_ clientRequest: HTTPRequest, to backendURL: URL) async -> HTTPResponse {
        do {
            var backendRequest = URLRequest(url: backendURL)
            backendRequest.httpMethod = "GET"
            backendRequest.timeoutInterval = 120

            // Forward Range header if present (crucial for seeking and initial probe)
            if let rangeValues = clientRequest.headers[HTTPHeader("Range")], !rangeValues.isEmpty {
                backendRequest.setValue(rangeValues, forHTTPHeaderField: "Range")
                print("[StreamProxy] Forwarding Range: \(rangeValues)")
            }

            backendRequest.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
            backendRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

            // Use bytes(for:) for streaming - returns AsyncSequence
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: backendRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(statusCode: .badGateway)
            }

            print("[StreamProxy] GET → HTTP \(httpResponse.statusCode), Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")

            // Read data in chunks (limit to prevent memory issues)
            // For the initial probe, KSPlayer only needs the first ~1MB
            // For seeking, it requests specific ranges which are small
            var data = Data()
            var totalRead = 0
            let maxBytes = 10_000_000 // 10 MB max per request

            for try await byte in asyncBytes {
                data.append(byte)
                totalRead += 1

                if totalRead >= maxBytes {
                    print("[StreamProxy] Reached max bytes limit (\(maxBytes))")
                    break
                }
            }

            var headers: [HTTPHeader: String] = [:]
            headers[HTTPHeader("Content-Type")] = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "video/x-matroska"
            headers[HTTPHeader("Content-Length")] = String(data.count)
            headers[HTTPHeader("Accept-Ranges")] = "bytes"

            // Forward Content-Range if present
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                headers[HTTPHeader("Content-Range")] = contentRange
            }

            headers[HTTPHeader("Access-Control-Allow-Origin")] = "*"

            print("[StreamProxy] Response: \(data.count) bytes")

            return HTTPResponse(
                statusCode: mapStatusCode(httpResponse.statusCode),
                headers: headers,
                body: data
            )

        } catch {
            print("[StreamProxy] GET failed: \(error.localizedDescription)")
            return HTTPResponse(
                statusCode: .badGateway,
                headers: [HTTPHeader("Content-Type"): "text/plain"],
                body: Data("Proxy error: \(error.localizedDescription)".utf8)
            )
        }
    }

    private static func mapStatusCode(_ code: Int) -> HTTPStatusCode {
        switch code {
        case 200: return .ok
        case 206: return .partialContent
        case 301: return .movedPermanently
        case 302: return .found
        case 304: return .notModified
        case 400: return .badRequest
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 416: return .rangeNotSatisfiable
        case 500: return .internalServerError
        case 502: return .badGateway
        case 503: return .serviceUnavailable
        default: return .ok
        }
    }
    #endif
}

// MARK: - Convenience Extensions

extension StreamProxy {
    func proxyURL(for backendURL: URL) async throws -> URL {
        let session = try await startProxy(for: backendURL)
        return session.localURL
    }
}

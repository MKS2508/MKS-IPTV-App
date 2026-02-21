import Foundation

#if canImport(FlyingFox)
import FlyingFox
#endif

/// An HTTP proxy that forwards requests to a backend URL.
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
/// 4. Streaming the response back to KSPlayer
///
/// ## Architecture
/// ```
/// KSPlayer (FFmpeg)
///     ↓ HTTP GET http://localhost:9100/0
/// [StreamProxy HTTPServer :9100]
///     ↓ HTTP GET http://backend:8080/...900chars...
/// [Backend: 89.34.226.233:8080]
///     ↓ HTTP 206 Partial Content (video data)
/// [StreamProxy]
///     ↓ Forward response to KSPlayer
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
    ///
    /// - Parameters:
    ///   - backendURL: The real URL to proxy to (the long tokenized URL).
    ///   - preferredPort: Optional preferred port number.
    /// - Returns: A `ProxySession` with the localhost URL to use.
    /// - Throws: `ProxyError` if the proxy cannot be started.
    func startProxy(for backendURL: URL, preferredPort: UInt16? = nil) async throws -> ProxySession {
        #if canImport(FlyingFox)
        // Find an available port
        let port = try findAvailablePort(preferred: preferredPort)

        // Session ID
        let sessionID = nextSessionID
        nextSessionID += 1

        // Build local URL
        guard let localURL = URL(string: "http://localhost:\(port)/\(sessionID)") else {
            throw ProxyError.invalidBackendURL
        }

        // Store the session
        let session = ProxySession(
            localURL: localURL,
            backendURL: backendURL,
            port: port,
            id: sessionID
        )
        sessions[sessionID] = session

        // Create HTTP server
        let server = HTTPServer(port: port)

        // Store backend URL for the route handler
        let backend = backendURL

        // Route: handle all requests and forward to backend
        await server.appendRoute("GET /*") { request in
            await Self.forwardRequest(request, to: backend)
        }

        await server.appendRoute("HEAD /*") { request in
            await Self.forwardRequest(request, to: backend)
        }

        servers[port] = server

        // Start server in background
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
        print("[StreamProxy]   Backend: \(backendURL.absoluteString.prefix(100))...")

        return session
        #else
        // FlyingFox not available — return backend URL directly
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

    /// Stops a specific proxy session.
    /// - Parameter sessionID: The session ID to stop.
    func stop(sessionID: Int) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }

        #if canImport(FlyingFox)
        serverTasks[session.port]?.cancel()
        serverTasks.removeValue(forKey: session.port)
        servers.removeValue(forKey: session.port)
        #endif

        print("[StreamProxy] Stopped proxy session #\(sessionID)")
    }

    /// Stops all active proxy sessions.
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

    /// Gets the proxy session for a given localhost URL.
    /// - Parameter url: The localhost URL.
    /// - Returns: The associated session, or nil if not found.
    func session(for url: URL) -> ProxySession? {
        guard url.host == "localhost",
              let port = url.port,
              let session = sessions.values.first(where: { $0.port == port }) else {
            return nil
        }
        return session
    }

    // MARK: - Private

    /// Finds an available port in the configured range.
    private func findAvailablePort(preferred: UInt16?) throws -> UInt16 {
        #if canImport(FlyingFox)
        // Try preferred port first
        if let preferred = preferred, !servers.keys.contains(preferred) {
            return preferred
        }

        // Find first available port in range
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
    /// Forwards an HTTP request to the backend URL and returns the response.
    private static func forwardRequest(_ clientRequest: HTTPRequest, to backendURL: URL) async -> HTTPResponse {
        do {
            // Build the request to backend
            var backendRequest = URLRequest(url: backendURL)
            backendRequest.httpMethod = "GET"
            backendRequest.timeoutInterval = 60

            // Copy relevant headers from client request (especially Range for seeking)
            if let rangeValues = clientRequest.headers[HTTPHeader("Range")], !rangeValues.isEmpty {
                backendRequest.setValue(rangeValues, forHTTPHeaderField: "Range")
            }

            // Add standard headers
            backendRequest.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
            backendRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            backendRequest.setValue("Keep-Alive", forHTTPHeaderField: "Connection")

            // Make the request
            let (data, response) = try await URLSession.shared.data(for: backendRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                return HTTPResponse(statusCode: .badGateway)
            }

            // Build response headers
            var headers: [HTTPHeader: String] = [:]

            // Forward important headers from backend
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                headers[HTTPHeader("Content-Type")] = contentType
            }
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                headers[HTTPHeader("Content-Length")] = contentLength
            }
            if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                headers[HTTPHeader("Content-Range")] = contentRange
            }
            if let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges") {
                headers[HTTPHeader("Accept-Ranges")] = acceptRanges
            }

            // CORS headers for cross-origin requests
            headers[HTTPHeader("Access-Control-Allow-Origin")] = "*"

            // Map HTTP status code
            let statusCode = Self.mapStatusCode(httpResponse.statusCode)

            print("[StreamProxy] Forwarded request → HTTP \(httpResponse.statusCode), \(data.count) bytes")

            return HTTPResponse(
                statusCode: statusCode,
                headers: headers,
                body: data
            )

        } catch {
            print("[StreamProxy] Forward request failed: \(error.localizedDescription)")
            return HTTPResponse(
                statusCode: .badGateway,
                headers: [HTTPHeader("Content-Type"): "text/plain"],
                body: Data("Proxy error: \(error.localizedDescription)".utf8)
            )
        }
    }

    /// Maps an Int to HTTPStatusCode
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

    /// Starts a proxy and returns just the localhost URL.
    ///
    /// Convenience method for when you don't need the full session info.
    ///
    /// - Parameter backendURL: The URL to proxy.
    /// - Returns: The localhost URL to use for playback.
    /// - Throws: `ProxyError` if the proxy cannot be started.
    func proxyURL(for backendURL: URL) async throws -> URL {
        let session = try await startProxy(for: backendURL)
        return session.localURL
    }
}

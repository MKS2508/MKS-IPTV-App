import Foundation
import Network

// MARK: - Stream Forwarder (URLSession → NWConnection bridge)

/// Bridges URLSession data delivery to an NWConnection, forwarding bytes as they arrive.
/// Uses a semaphore for backpressure so the NWConnection send buffer doesn't grow unbounded.
///
/// When the client (FFmpeg) closes the connection to seek, the forwarder detects the broken
/// pipe immediately and cancels the backend URLSession — freeing the IPTV server connection
/// for FFmpeg's next range request.
private final class StreamForwarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let connection: NWConnection
    private let backpressure = DispatchSemaphore(value: 4)
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var totalBytesSent: Int64 = 0

    /// Thread-safe cancellation flag. Once set, all delegate callbacks bail out immediately
    /// and no further data is sent to the NWConnection.
    private var _cancelled = false
    private let cancelLock = NSLock()

    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return _cancelled
    }

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// Start forwarding the backend URL response to the NWConnection.
    func start(backendURL: URL, rangeHeader: String?) {
        // Monitor client connection state — when FFmpeg closes the connection to seek,
        // we detect it here and immediately cancel the backend download.
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                print("[StreamProxy] Client connection failed: \(error.localizedDescription)")
                self?.cancelBackend()
            case .cancelled:
                self?.cancelBackend()
            default:
                break
            }
        }

        var request = URLRequest(url: backendURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        if let range = rangeHeader {
            request.setValue(range, forHTTPHeaderField: "Range")
            print("[StreamProxy] GET forwarding Range: \(range)")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "StreamForwarder"

        session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func cancel() {
        cancelBackend()
        connection.cancel()
    }

    /// Idempotent cancellation of the backend URLSession. Called on first send error,
    /// NWConnection failure, or explicit cancel. Protected by cancelLock so it only
    /// runs once — prevents the cascade of "Broken pipe" errors.
    private func cancelBackend() {
        cancelLock.lock()
        guard !_cancelled else {
            cancelLock.unlock()
            return
        }
        _cancelled = true
        cancelLock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
        print("[StreamProxy] Backend cancelled (\(totalBytesSent) bytes sent to client)")
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !isCancelled else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            sendErrorAndClose(status: 502, message: "Bad Gateway")
            return
        }

        let statusCode = httpResponse.statusCode
        print("[StreamProxy] Backend responded: HTTP \(statusCode)")

        // Build raw HTTP response header with standard reason phrases
        // (not localized — FFmpeg's parser expects ASCII)
        let statusText = Self.httpReasonPhrase(for: statusCode)
        var header = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        header += "Connection: close\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Accept-Ranges: bytes\r\n"

        // Forward relevant headers from backend
        let forwardHeaders = ["Content-Type", "Content-Length", "Content-Range"]
        for key in forwardHeaders {
            if let value = httpResponse.value(forHTTPHeaderField: key) {
                header += "\(key): \(value)\r\n"
                print("[StreamProxy]   \(key): \(value)")
            }
        }

        // If no Content-Type from backend, default to octet-stream
        if httpResponse.value(forHTTPHeaderField: "Content-Type") == nil {
            header += "Content-Type: application/octet-stream\r\n"
        }

        header += "\r\n"

        let headerData = Data(header.utf8)
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("[StreamProxy] Failed to send headers: \(error)")
                self?.cancelBackend()
            }
        })

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }

        // Backpressure: block this delegate queue thread until NWConnection has capacity
        backpressure.wait()

        guard !isCancelled else {
            backpressure.signal()
            return
        }

        totalBytesSent += Int64(data.count)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            self?.backpressure.signal()
            if error != nil {
                // First send error triggers immediate backend cancellation
                self?.cancelBackend()
            }
        })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Don't log cancellation as errors — it's normal when FFmpeg seeks
            if nsError.code != NSURLErrorCancelled {
                print("[StreamProxy] Backend transfer error: \(error.localizedDescription) (\(totalBytesSent) bytes sent)")
            }
        } else {
            print("[StreamProxy] Backend transfer completed (\(totalBytesSent) bytes sent)")
        }

        guard !isCancelled else {
            session.finishTasksAndInvalidate()
            return
        }

        // Send EOF by closing the write side
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })

        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard !isCancelled else {
            completionHandler(nil)
            return
        }

        // Follow redirects but preserve our User-Agent
        var redirected = request
        redirected.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
        redirected.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        print("[StreamProxy] Following redirect -> \(request.url?.host ?? "?")")
        completionHandler(redirected)
    }

    // MARK: - Helpers

    private func sendErrorAndClose(status: Int, message: String) {
        let body = message
        let header = "HTTP/1.1 \(status) \(message)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        let data = Data((header + body).utf8)
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    /// Standard HTTP reason phrases — not localized, safe for FFmpeg's ASCII parser.
    private static func httpReasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 416: return "Range Not Satisfiable"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }
}

// MARK: - StreamProxy Actor

/// An HTTP proxy that forwards requests to a backend URL with true byte streaming.
///
/// ## Purpose
/// FFmpeg 8.0.1 (TransmuxCore) may have issues with very long HTTP URLs (>~500 chars).
/// IPTV servers behind Cloudflare use 302 redirects to tokenized URLs that can
/// exceed 900 characters.
///
/// This proxy solves the problem by:
/// 1. Listening on localhost with a short URL (e.g., `http://localhost:9100/0`)
/// 2. Receiving HTTP requests from FFmpeg
/// 3. Forwarding requests to the real backend URL (with the long token)
/// 4. Streaming the response bytes directly as they arrive (no buffering)
///
/// ## Architecture
/// ```
/// FFmpeg 8.0.1 (TransmuxCore)
///     | TCP connect localhost:9100
/// [NWListener] accept NWConnection
///     | parse raw HTTP request (GET/HEAD + Range)
/// [StreamForwarder: URLSessionDataDelegate]
///     | didReceive response -> send HTTP headers to NWConnection
///     | didReceive data (chunks) -> send directly to NWConnection
///     | didComplete -> close connection
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

    /// Active NWListeners indexed by port.
    private var listeners: [UInt16: NWListener] = [:]

    /// Active forwarders for cleanup on stop.
    private var activeForwarders: [UInt16: [StreamForwarder]] = [:]

    /// Next session ID.
    private var nextSessionID = 0

    /// Port range to try when allocating.
    private let portRange: Range<UInt16>

    /// Dedicated dispatch queue for NWListener/NWConnection callbacks.
    private let networkQueue = DispatchQueue(label: "StreamProxy.network", qos: .userInitiated)

    // MARK: - Initialization

    /// Creates a new StreamProxy instance.
    /// - Parameter portRange: Range of ports to try when allocating (default 9100-9199).
    init(portRange: Range<UInt16> = 9100..<9200) {
        self.portRange = portRange
    }

    // MARK: - Public API

    /// Starts a proxy session for the given backend URL.
    func startProxy(for backendURL: URL, preferredPort: UInt16? = nil) async throws -> ProxySession {
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

        // Create NWListener on the allocated port
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listeners[port] = listener
        activeForwarders[port] = []

        let backend = backendURL

        listener.newConnectionHandler = { [weak self] connection in
            Task { [weak self] in
                await self?.handleConnection(connection, backendURL: backend, port: port)
            }
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[StreamProxy] NWListener ready on port \(port)")
            case .failed(let error):
                print("[StreamProxy] NWListener failed on port \(port): \(error)")
            case .cancelled:
                print("[StreamProxy] NWListener cancelled on port \(port)")
            default:
                break
            }
        }

        listener.start(queue: networkQueue)

        print("[StreamProxy] Started streaming proxy session #\(sessionID) on port \(port)")
        print("[StreamProxy]   Local:   \(localURL.absoluteString)")
        print("[StreamProxy]   Backend: \(backendURL.absoluteString.prefix(80))...")

        return session
    }

    func stop(sessionID: Int) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }

        // Cancel all active forwarders for this port
        if let forwarders = activeForwarders[session.port] {
            for forwarder in forwarders {
                forwarder.cancel()
            }
        }
        activeForwarders.removeValue(forKey: session.port)

        listeners[session.port]?.cancel()
        listeners.removeValue(forKey: session.port)

        print("[StreamProxy] Stopped proxy session #\(sessionID)")
    }

    func stopAll() {
        for (port, listener) in listeners {
            if let forwarders = activeForwarders[port] {
                for forwarder in forwarders {
                    forwarder.cancel()
                }
            }
            listener.cancel()
            print("[StreamProxy] Stopped listener on port \(port)")
        }
        listeners.removeAll()
        activeForwarders.removeAll()
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

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection, backendURL: URL, port: UInt16) {
        // Minimal state handler for connection setup logging.
        // StreamForwarder.start() overrides this with a handler that also cancels
        // the backend on failure (for GET requests). HEAD requests are short-lived
        // so the logging-only handler is sufficient.
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                print("[StreamProxy] Connection accepted")
            }
        }

        connection.start(queue: networkQueue)

        // Read the HTTP request from the client
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let data = data, !data.isEmpty else {
                if let error = error {
                    print("[StreamProxy] Read error: \(error)")
                }
                connection.cancel()
                return
            }

            guard let request = HTTPRequestParser.parse(data) else {
                print("[StreamProxy] Failed to parse HTTP request")
                let response = Data("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: response, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            print("[StreamProxy] \(request.method.rawValue) \(request.path) Range: \(request.rangeHeader ?? "none")")

            Task { [weak self] in
                await self?.dispatchRequest(request, connection: connection, backendURL: backendURL, port: port)
            }
        }
    }

    private func dispatchRequest(
        _ request: HTTPRequestParser.Request,
        connection: NWConnection,
        backendURL: URL,
        port: UInt16
    ) {
        switch request.method {
        case .head:
            handleHeadRequest(connection: connection, backendURL: backendURL)
        case .get:
            handleGetRequest(connection: connection, backendURL: backendURL, rangeHeader: request.rangeHeader, port: port)
        }
    }

    // MARK: - HEAD Handler

    private nonisolated func handleHeadRequest(connection: NWConnection, backendURL: URL) {
        Task {
            do {
                var request = URLRequest(url: backendURL)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 30
                request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    let errorResp = Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n".utf8)
                    connection.send(content: errorResp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }

                print("[StreamProxy] HEAD -> HTTP \(httpResponse.statusCode)")

                let statusText = Self.headReasonPhrase(for: httpResponse.statusCode)
                var header = "HTTP/1.1 \(httpResponse.statusCode) \(statusText)\r\n"
                header += "Connection: close\r\n"
                header += "Accept-Ranges: bytes\r\n"
                header += "Access-Control-Allow-Origin: *\r\n"

                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    header += "Content-Type: \(contentType)\r\n"
                } else {
                    header += "Content-Type: application/octet-stream\r\n"
                }

                if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                    header += "Content-Length: \(contentLength)\r\n"
                }

                header += "\r\n"

                let headerData = Data(header.utf8)
                connection.send(content: headerData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } catch {
                print("[StreamProxy] HEAD failed: \(error.localizedDescription)")
                let errorResp = Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n".utf8)
                connection.send(content: errorResp, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    // MARK: - GET Handler (Streaming)

    private func handleGetRequest(
        connection: NWConnection,
        backendURL: URL,
        rangeHeader: String?,
        port: UInt16
    ) {
        let forwarder = StreamForwarder(connection: connection)
        activeForwarders[port, default: []].append(forwarder)
        forwarder.start(backendURL: backendURL, rangeHeader: rangeHeader)
    }

    // MARK: - HTTP Helpers

    /// Standard HTTP reason phrases for HEAD responses (not localized).
    private nonisolated static func headReasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 502: return "Bad Gateway"
        default: return "OK"
        }
    }

    // MARK: - Port Allocation

    private func findAvailablePort(preferred: UInt16?) throws -> UInt16 {
        if let preferred = preferred, !listeners.keys.contains(preferred) {
            return preferred
        }
        for port in portRange {
            if !listeners.keys.contains(port) {
                return port
            }
        }
        throw ProxyError.portExhausted(tried: portRange)
    }
}

// MARK: - Convenience Extensions

extension StreamProxy {
    func proxyURL(for backendURL: URL) async throws -> URL {
        let session = try await startProxy(for: backendURL)
        return session.localURL
    }
}

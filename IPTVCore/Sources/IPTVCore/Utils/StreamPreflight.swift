import Foundation

// MARK: - Preflight Result

/// Result of a stream preflight validation check.
/// Contains HTTP metadata and reachability info without consuming a full stream connection.
public struct PreflightResult {
    /// Whether the stream URL is reachable (HTTP 2xx/3xx)
    public let isReachable: Bool
    /// HTTP status code returned by the server (nil if connection failed entirely)
    public let httpStatus: Int?
    /// Content-Type header value (e.g. "video/mp4", "application/octet-stream")
    public let contentType: String?
    /// Content-Length in bytes (nil if chunked/unknown/zero)
    public let contentLength: Int64?
    /// Server header value (useful for identifying IPTV server software)
    public let serverHeader: String?
    /// Human-readable error description if the check failed
    public let error: String?
    /// Round-trip latency in milliseconds
    public let latencyMs: Double
    /// Final URL after redirects (nil if no redirect occurred)
    public let finalURL: URL?
    /// Whether the request was redirected (302, 301, etc.)
    public let wasRedirected: Bool

    /// Whether the content-type suggests a video/audio stream
    public var isMediaContent: Bool {
        guard let ct = contentType?.lowercased() else { return false }
        return ct.contains("video") || ct.contains("audio")
            || ct.contains("mpegurl") || ct.contains("octet-stream")
            || ct.contains("mpeg")
    }

    /// Short human-readable summary for logging
    public var summary: String {
        if isReachable {
            let status = httpStatus.map { String($0) } ?? "?"
            let ct = contentType ?? "unknown"
            let size: String
            if let cl = contentLength, cl > 0 {
                size = ByteCountFormatter.string(fromByteCount: cl, countStyle: .file)
            } else {
                size = "unknown"
            }
            let redirect = wasRedirected ? " | redirected" : ""
            return "HTTP \(status) | \(ct) | \(size) | \(String(format: "%.0f", latencyMs))ms\(redirect)"
        } else {
            return "Unreachable: \(error ?? "unknown error")"
        }
    }
}

// MARK: - Stream Preflight

/// Lightweight HTTP validation utility that checks stream reachability
/// **before** any player touches the URL.
///
/// Strategy:
/// 1. Sends HTTP HEAD first (no body, minimal cost)
/// 2. If HEAD returns `Content-Length: 0` or is rejected (405/501), falls back
///    to a ranged GET with `Range: bytes=0-1023` to get real metadata
/// 3. Detects redirects and reports the final URL
///
/// Uses an IPTV-compatible User-Agent by default.
///
/// This prevents crashes from unreachable/invalid streams and avoids wasting
/// IPTV server connections on URLs that will fail immediately.
public final class StreamPreflight {

    /// Default User-Agent that IPTV servers recognize and allow
    private static let defaultUserAgent = "VLC/3.0.18 LibVLC/3.0.18"

    /// Perform a quick HTTP preflight check on a stream URL.
    ///
    /// - Parameters:
    ///   - url: The stream URL to validate.
    ///   - headers: Additional HTTP headers to include (merged with defaults).
    ///   - timeoutSeconds: Maximum time to wait for a response (default 10s).
    /// - Returns: A `PreflightResult` describing reachability and HTTP metadata.
    ///            Never throws — all errors are captured in the result.
    public static func check(
        url: URL,
        headers: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10
    ) async -> PreflightResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build default headers
        var allHeaders: [String: String] = [
            "User-Agent": defaultUserAgent,
            "Accept": "*/*",
            "Connection": "close"
        ]
        for (key, value) in headers {
            allHeaders[key] = value
        }

        // Try HEAD first (no body download)
        let headResult = await performRequest(
            url: url,
            method: "HEAD",
            headers: allHeaders,
            timeoutSeconds: timeoutSeconds,
            startTime: startTime
        )

        // HEAD succeeded but many IPTV/Cloudflare servers return Content-Length: 0
        // on HEAD (broken behavior). If we got 200 but zero/nil content-length,
        // fall through to ranged GET for real metadata.
        let headHasValidContent = headResult.isReachable
            && headResult.contentLength != nil
            && headResult.contentLength! > 0

        // If HEAD gave us good data OR a definitive client error, use it
        if headHasValidContent || (!headResult.isReachable && headResult.httpStatus != nil
            && headResult.httpStatus != 405 && headResult.httpStatus != 501) {
            return headResult
        }

        // HEAD was rejected (405/501) or returned bogus Content-Length: 0
        // Retry with ranged GET to get real metadata from final server
        var rangeHeaders = allHeaders
        rangeHeaders["Range"] = "bytes=0-1023"

        let getResult = await performRequest(
            url: url,
            method: "GET",
            headers: rangeHeaders,
            timeoutSeconds: timeoutSeconds,
            startTime: startTime
        )

        return getResult
    }

    // MARK: - URL Resolution

    /// Resolve redirects for a stream URL without consuming the connection.
    ///
    /// Sends a GET request that intercepts the first redirect (302/301), captures
    /// the `Location` header, and cancels the request immediately — so the
    /// backend token is NOT consumed. Returns the final direct URL that players
    /// can open without needing to handle HTTP redirects themselves.
    ///
    /// - Parameters:
    ///   - url: The original stream URL (may redirect).
    ///   - headers: Additional HTTP headers.
    ///   - timeoutSeconds: Maximum time to wait.
    /// - Returns: The resolved direct URL, or the original URL if no redirect occurred.
    public static func resolveRedirects(
        url: URL,
        headers: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10
    ) async -> URL {
        var allHeaders: [String: String] = [
            "User-Agent": defaultUserAgent,
            "Accept": "*/*",
            "Connection": "close"
        ]
        for (key, value) in headers {
            allHeaders[key] = value
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Use a delegate that captures the redirect Location and cancels
        let interceptor = RedirectInterceptor()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        let session = URLSession(configuration: config, delegate: interceptor, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // We expect a cancellation error because we cancel after intercepting the redirect
        _ = try? await session.data(for: request)

        return interceptor.redirectURL ?? url
    }

    // MARK: - Private

    /// URLSession delegate that intercepts redirects and cancels the request.
    /// Captures the Location URL without following the redirect (preserves token).
    private class RedirectInterceptor: NSObject, URLSessionTaskDelegate {
        var redirectURL: URL?

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            redirectURL = request.url
            // Return nil to NOT follow the redirect — preserves the backend token
            completionHandler(nil)
        }
    }

    /// URLSession delegate that tracks redirects without blocking them
    private class RedirectTracker: NSObject, URLSessionTaskDelegate {
        var finalURL: URL?
        var wasRedirected = false

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            wasRedirected = true
            finalURL = request.url
            completionHandler(request) // Follow the redirect
        }
    }

    private static func performRequest(
        url: URL,
        method: String,
        headers: [String: String],
        timeoutSeconds: TimeInterval,
        startTime: CFAbsoluteTime
    ) async -> PreflightResult {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.cachePolicy = .reloadIgnoringLocalCacheData

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Use a delegate to track redirects
        let redirectTracker = RedirectTracker()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSeconds
        let session = URLSession(configuration: config, delegate: redirectTracker, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            guard let httpResponse = response as? HTTPURLResponse else {
                return PreflightResult(
                    isReachable: false,
                    httpStatus: nil,
                    contentType: nil,
                    contentLength: nil,
                    serverHeader: nil,
                    error: "Response is not HTTP",
                    latencyMs: elapsed,
                    finalURL: nil,
                    wasRedirected: false
                )
            }

            let status = httpResponse.statusCode
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            let serverHeader = httpResponse.value(forHTTPHeaderField: "Server")

            // Parse Content-Length — prefer explicit header, fall back to expectedContentLength
            var contentLength: Int64?
            if let clString = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let cl = Int64(clString), cl > 0 {
                contentLength = cl
            } else if httpResponse.expectedContentLength > 0 {
                contentLength = httpResponse.expectedContentLength
            }

            // For 206 Partial Content, check Content-Range for the total size
            if status == 206, contentLength == nil || contentLength == 1024 {
                if let rangeHeader = httpResponse.value(forHTTPHeaderField: "Content-Range") {
                    // Format: "bytes 0-1023/8800277128"
                    if let slashIndex = rangeHeader.lastIndex(of: "/") {
                        let totalStr = String(rangeHeader[rangeHeader.index(after: slashIndex)...])
                        if let total = Int64(totalStr), total > 0 {
                            contentLength = total
                        }
                    }
                }
            }

            let isReachable = (200...399).contains(status)

            return PreflightResult(
                isReachable: isReachable,
                httpStatus: status,
                contentType: contentType,
                contentLength: contentLength,
                serverHeader: serverHeader,
                error: isReachable ? nil : "HTTP \(status)",
                latencyMs: elapsed,
                finalURL: redirectTracker.finalURL,
                wasRedirected: redirectTracker.wasRedirected
            )
        } catch let error as URLError {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let message: String
            switch error.code {
            case .timedOut:
                message = "Connection timed out (\(Int(timeoutSeconds))s)"
            case .cannotFindHost:
                message = "Cannot resolve host: \(url.host ?? "unknown")"
            case .cannotConnectToHost:
                message = "Cannot connect to host: \(url.host ?? "unknown")"
            case .networkConnectionLost:
                message = "Network connection lost"
            case .notConnectedToInternet:
                message = "No internet connection"
            case .secureConnectionFailed:
                message = "SSL/TLS handshake failed"
            default:
                message = error.localizedDescription
            }

            return PreflightResult(
                isReachable: false,
                httpStatus: nil,
                contentType: nil,
                contentLength: nil,
                serverHeader: nil,
                error: message,
                latencyMs: elapsed,
                finalURL: nil,
                wasRedirected: false
            )
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return PreflightResult(
                isReachable: false,
                httpStatus: nil,
                contentType: nil,
                contentLength: nil,
                serverHeader: nil,
                error: error.localizedDescription,
                latencyMs: elapsed,
                finalURL: nil,
                wasRedirected: false
            )
        }
    }
}

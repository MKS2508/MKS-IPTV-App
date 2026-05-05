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
    /// Uses `RawHTTPClient` (NWConnection) instead of URLSession so it is not
    /// subject to App Transport Security on tvOS 26 — IPTV servers use plain HTTP.
    ///
    /// Strategy:
    /// 1. HEAD via RawHTTPClient (no body download)
    /// 2. If HEAD returns 405/501 or Content-Length: 0, fall back to ranged GET
    ///    via RawHTTPClient (reads only first 1 KB of body, enough for headers)
    ///
    /// Never throws — all errors are captured in the result.
    public static func check(
        url: URL,
        headers: [String: String] = [:],
        timeoutSeconds: TimeInterval = 10
    ) async -> PreflightResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Try HEAD first (no body, ATS-safe via RawHTTPClient)
        let headResult = await rawHeadCheck(url: url, timeoutSeconds: timeoutSeconds, startTime: startTime)

        let headHasValidContent = headResult.isReachable
            && headResult.contentLength != nil
            && headResult.contentLength! > 0

        if headHasValidContent || (!headResult.isReachable && headResult.httpStatus != nil
            && headResult.httpStatus != 405 && headResult.httpStatus != 501) {
            return headResult
        }

        // HEAD rejected or bogus Content-Length — fall back to ranged GET
        return await rawRangedGetCheck(url: url, timeoutSeconds: timeoutSeconds, startTime: startTime)
    }

    // MARK: - RawHTTPClient-based checks (ATS-safe)

    private static func rawHeadCheck(url: URL, timeoutSeconds: TimeInterval, startTime: CFAbsoluteTime) async -> PreflightResult {
        do {
            let response = try await RawHTTPClient.shared.head(url, timeout: timeoutSeconds)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return preflightResult(from: response, elapsed: elapsed)
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return PreflightResult(
                isReachable: false, httpStatus: nil, contentType: nil,
                contentLength: nil, serverHeader: nil,
                error: rawErrorMessage(error), latencyMs: elapsed,
                finalURL: nil, wasRedirected: false
            )
        }
    }

    private static func rawRangedGetCheck(url: URL, timeoutSeconds: TimeInterval, startTime: CFAbsoluteTime) async -> PreflightResult {
        // We only need the response headers — RawHTTPClient will read the full
        // body up to its 64 MB cap, but for a range request the body is ≤1 KB.
        // This is acceptable: it provides accurate Content-Length from Content-Range.
        do {
            let (_, response) = try await RawHTTPClient.shared.get(url, timeout: timeoutSeconds)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return preflightResult(from: response, elapsed: elapsed)
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            return PreflightResult(
                isReachable: false, httpStatus: nil, contentType: nil,
                contentLength: nil, serverHeader: nil,
                error: rawErrorMessage(error), latencyMs: elapsed,
                finalURL: nil, wasRedirected: false
            )
        }
    }

    private static func preflightResult(from response: RawHTTPResponse, elapsed: Double) -> PreflightResult {
        let status = response.statusCode
        let contentType = response.header("content-type")
        let serverHeader = response.header("server")

        var contentLength: Int64?
        if let clStr = response.header("content-length"), let cl = Int64(clStr), cl > 0 {
            contentLength = cl
        }
        // For 206 Partial Content parse Content-Range for total size
        if status == 206, let rangeHeader = response.header("content-range") {
            if let slashIndex = rangeHeader.lastIndex(of: "/") {
                let totalStr = String(rangeHeader[rangeHeader.index(after: slashIndex)...])
                if let total = Int64(totalStr), total > 0 {
                    contentLength = total
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
            finalURL: nil,
            wasRedirected: false
        )
    }

    private static func rawErrorMessage(_ error: Error) -> String {
        if let raw = error as? RawHTTPError { return raw.description }
        return error.localizedDescription
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
        // Use RawHTTPClient HEAD — ATS-safe. If the server redirects, the
        // Location header is in the response headers (status 301/302/307/308).
        do {
            let response = try await RawHTTPClient.shared.head(url, timeout: timeoutSeconds)
            let status = response.statusCode
            if (301...308).contains(status), let location = response.header("location"),
               let redirectURL = URL(string: location) {
                return redirectURL
            }
        } catch {
            // Fall through — return original URL
        }
        return url
    }

}

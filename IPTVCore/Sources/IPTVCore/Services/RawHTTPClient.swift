//
//  RawHTTPClient.swift
//  IPTVCore
//
//  Minimal HTTP/1.1 client built on Network.framework (NWConnection).
//  Bypasses URLSession entirely so App Transport Security cannot block
//  requests to user-supplied IPTV servers.
//
//  Why this exists
//  ---------------
//  tvOS 26 silently ignores `NSAllowsArbitraryLoads = true` for arbitrary
//  HTTP hosts. Only per-domain `NSExceptionAllowsInsecureHTTPLoads` is
//  honored. Since the IPTV server URL is supplied by the user at runtime,
//  the host can't be enumerated in Info.plist. NWConnection talks raw TCP
//  and is not subject to ATS.
//
//  Scope
//  -----
//  GET-only API for now. Body up to 64 MB. Designed for the Xtream Codes
//  player_api.php endpoints and image fetches. Not for video streaming —
//  TransmuxCore handles that with libavformat's own networking.
//

import Foundation
import Network

public enum RawHTTPError: Error, Sendable, CustomStringConvertible {
    case invalidURL
    case connectionFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case malformedResponse(String)
    case timeout
    case cancelled

    public var description: String {
        switch self {
        case .invalidURL: return "invalid URL"
        case .connectionFailed(let m): return "connection failed: \(m)"
        case .writeFailed(let m): return "write failed: \(m)"
        case .readFailed(let m): return "read failed: \(m)"
        case .malformedResponse(let m): return "malformed response: \(m)"
        case .timeout: return "timeout"
        case .cancelled: return "cancelled"
        }
    }
}

public struct RawHTTPResponse: Sendable {
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]   // lowercased keys

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public actor RawHTTPClient {
    public static let shared = RawHTTPClient()

    public init() {}

    public func get(_ url: URL, timeout: TimeInterval = 30) async throws -> (Data, RawHTTPResponse) {
        try await perform(url: url, timeout: timeout)
    }

    /// Send a HEAD request and return only the response headers (no body downloaded).
    /// ATS-safe — uses NWConnection, not URLSession.
    public func head(_ url: URL, timeout: TimeInterval = 10) async throws -> RawHTTPResponse {
        try await performHead(url: url, timeout: timeout)
    }

    // MARK: - Core

    private func perform(url: URL, timeout: TimeInterval) async throws -> (Data, RawHTTPResponse) {
        guard let host = url.host, let scheme = url.scheme?.lowercased() else {
            throw RawHTTPError.invalidURL
        }
        let isTLS = (scheme == "https")
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(url.port ?? (isTLS ? 443 : 80))) else {
            throw RawHTTPError.invalidURL
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue)
        let connection = NWConnection(to: endpoint, using: isTLS ? .tls : .tcp)

        return try await withTaskCancellationHandler {
            try await withDeadline(timeout) {
                try Task.checkCancellation()
                try await self.open(connection)
                try Task.checkCancellation()
                try await self.send(self.buildRequest(url: url), on: connection)
                try Task.checkCancellation()
                let bytes = try await self.readUntilClose(on: connection)
                connection.cancel()
                return try self.parse(bytes, url: url)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    /// HEAD request: sends a HEAD and reads only until the blank line (no body).
    /// The server may keep the connection open after headers; we close immediately
    /// after parsing the status + headers — no body download.
    private func performHead(url: URL, timeout: TimeInterval) async throws -> RawHTTPResponse {
        guard let host = url.host, let scheme = url.scheme?.lowercased() else {
            throw RawHTTPError.invalidURL
        }
        let isTLS = (scheme == "https")
        guard let portValue = NWEndpoint.Port(rawValue: UInt16(url.port ?? (isTLS ? 443 : 80))) else {
            throw RawHTTPError.invalidURL
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: portValue)
        let connection = NWConnection(to: endpoint, using: isTLS ? .tls : .tcp)

        return try await withTaskCancellationHandler {
            try await withDeadline(timeout) {
                try Task.checkCancellation()
                try await self.open(connection)
                try Task.checkCancellation()
                try await self.send(self.buildHeadRequest(url: url), on: connection)
                try Task.checkCancellation()
                // Read until we see \r\n\r\n (end of headers) or connection closes
                let headerBytes = try await self.readUntilHeadersEnd(on: connection)
                connection.cancel()
                return try self.parseHeadersOnly(headerBytes, url: url)
            }
        } onCancel: {
            connection.cancel()
        }
    }

    // MARK: - Connection lifecycle

    private nonisolated func open(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = LockedFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.set() { cont.resume() }
                case .failed(let error):
                    if resumed.set() {
                        cont.resume(throwing: RawHTTPError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    if resumed.set() {
                        cont.resume(throwing: RawHTTPError.cancelled)
                    }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private nonisolated func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: RawHTTPError.writeFailed(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    /// Reads until the connection closes (we sent `Connection: close`).
    /// Caps at 64 MB to refuse runaway responses.
    private nonisolated func readUntilClose(on connection: NWConnection) async throws -> Data {
        var buffer = Data()
        let cap = 64 * 1024 * 1024

        while true {
            let (chunk, isComplete) = try await receive(on: connection, max: 64 * 1024)
            buffer.append(chunk)
            if isComplete { return buffer }
            if buffer.count > cap {
                throw RawHTTPError.readFailed("response exceeds 64 MB cap")
            }
        }
    }

    /// Reads one chunk. Returns the bytes plus whether this was the final delivery.
    /// NWConnection can return `data + isComplete=true` in one callback — calling
    /// `receive` again after that fails ("already delivered final read"), so the
    /// caller MUST stop based on `isComplete`.
    private nonisolated func receive(
        on connection: NWConnection,
        max: Int
    ) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { content, _, isComplete, error in
                if let error {
                    cont.resume(throwing: RawHTTPError.readFailed(error.localizedDescription))
                    return
                }
                cont.resume(returning: (content ?? Data(), isComplete))
            }
        }
    }

    // MARK: - Request / Response

    private nonisolated func buildHeadRequest(url: URL) -> Data {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = (comps?.path).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        if let q = comps?.percentEncodedQuery, !q.isEmpty { path += "?" + q }

        var hostHeader = url.host ?? ""
        if let port = url.port { hostHeader += ":\(port)" }

        let lines = [
            "HEAD \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "User-Agent: VLC/3.0.18 LibVLC/3.0.18",
            "Accept: */*",
            "Accept-Encoding: identity",
            "Connection: close"
        ]
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// Read from a connection until we see the HTTP header terminator \r\n\r\n.
    /// Stops immediately after headers — does not read body (suitable for HEAD responses).
    private nonisolated func readUntilHeadersEnd(on connection: NWConnection) async throws -> Data {
        let terminator = Data([0x0d, 0x0a, 0x0d, 0x0a])
        var buffer = Data()
        let cap = 64 * 1024   // 64 KB is more than enough for any HTTP header block

        while true {
            let (chunk, isComplete) = try await receive(on: connection, max: 4096)
            buffer.append(chunk)
            if buffer.range(of: terminator) != nil { return buffer }
            if isComplete { return buffer }   // Connection closed — parse what we have
            if buffer.count > cap { throw RawHTTPError.malformedResponse("headers exceed 64 KB") }
        }
    }

    /// Parse only the HTTP status line + headers from raw bytes (no body required).
    private nonisolated func parseHeadersOnly(_ bytes: Data, url: URL) throws -> RawHTTPResponse {
        // Allow parsing even if terminator is absent (server closed without it)
        let terminator = Data([0x0d, 0x0a, 0x0d, 0x0a])
        let headerBytes: Data
        if let range = bytes.range(of: terminator) {
            headerBytes = bytes.subdata(in: 0..<range.lowerBound)
        } else {
            headerBytes = bytes
        }

        guard let headerString = String(data: headerBytes, encoding: .utf8),
              !headerString.isEmpty else {
            throw RawHTTPError.malformedResponse("empty response")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first, !statusLine.isEmpty else {
            throw RawHTTPError.malformedResponse("no status line")
        }
        lines.removeFirst()

        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        let status = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0

        var headerDict: [String: String] = [:]
        for line in lines where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headerDict[key.lowercased()] = value
            }
        }

        return RawHTTPResponse(url: url, statusCode: status, headers: headerDict)
    }

    private nonisolated func buildRequest(url: URL) -> Data {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = (comps?.path).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        if let q = comps?.percentEncodedQuery, !q.isEmpty { path += "?" + q }

        var hostHeader = url.host ?? ""
        if let port = url.port { hostHeader += ":\(port)" }

        let lines = [
            "GET \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "User-Agent: MKS-IPTV/1.0",
            "Accept: */*",
            "Accept-Encoding: identity",      // refuse gzip — keeps parser simple
            "Connection: close"
        ]
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private nonisolated func parse(_ bytes: Data, url: URL) throws -> (Data, RawHTTPResponse) {
        guard let separator = bytes.range(of: Data([0x0d, 0x0a, 0x0d, 0x0a])) else {
            throw RawHTTPError.malformedResponse("no header terminator")
        }

        let headerBytes = bytes.subdata(in: 0..<separator.lowerBound)
        let body = bytes.subdata(in: separator.upperBound..<bytes.count)

        guard let headerString = String(data: headerBytes, encoding: .utf8) else {
            throw RawHTTPError.malformedResponse("non-utf8 headers")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let statusLine = lines.first, !statusLine.isEmpty else {
            throw RawHTTPError.malformedResponse("no status line")
        }
        lines.removeFirst()

        // Parse status line: "HTTP/1.1 200 OK"
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        let status = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0

        // Parse headers
        var headerDict: [String: String] = [:]
        for line in lines where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headerDict[key.lowercased()] = value
            }
        }

        let response = RawHTTPResponse(url: url, statusCode: status, headers: headerDict)

        // Decode body if chunked (we asked identity but server may still chunk)
        let isChunked = (headerDict["transfer-encoding"] ?? "").lowercased().contains("chunked")
        let finalBody = isChunked ? try Self.decodeChunked(body) : body

        return (finalBody, response)
    }

    // MARK: - Chunked decoder

    private static func decodeChunked(_ data: Data) throws -> Data {
        var result = Data()
        var index = 0

        while index < data.count {
            guard let lineEnd = data.range(of: Data([0x0d, 0x0a]), in: index..<data.count) else {
                throw RawHTTPError.malformedResponse("chunk size missing CRLF")
            }
            let sizeLine = String(data: data.subdata(in: index..<lineEnd.lowerBound), encoding: .utf8) ?? ""
            let sizeHex = sizeLine.split(separator: ";").first.map(String.init) ?? sizeLine
            guard let size = Int(sizeHex.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw RawHTTPError.malformedResponse("bad chunk size: \(sizeLine)")
            }
            index = lineEnd.upperBound
            if size == 0 { break }
            guard index + size <= data.count else {
                throw RawHTTPError.malformedResponse("chunk body truncated")
            }
            result.append(data.subdata(in: index..<(index + size)))
            index += size
            if index + 2 <= data.count { index += 2 }   // skip CRLF after chunk body
        }

        return result
    }
}

// MARK: - Helpers

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func set() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Race a body against a timeout.
private func withDeadline<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw RawHTTPError.timeout
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

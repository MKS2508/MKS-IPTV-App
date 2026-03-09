//
//  CastLog.swift
//  mks-multiplatform-iptv
//
//  Structured logger for Cast V2 protocol events.
//  Mirrors PlayerLog design — writes to file + console.
//  Output file: <temporaryDirectory>/mks-iptv-cast.log
//

import Foundation

/// Thread-safe structured logger for Google Cast protocol events.
/// Mirrors PlayerLog design for consistency across the codebase.
enum CastLog {

    // MARK: - Configuration

    public static let filePath: String = {
        let dir = FileManager.default.temporaryDirectory.path
        return (dir as NSString).appendingPathComponent("mks-iptv-cast.log")
    }()

    private static let queue = DispatchQueue(label: "CastLog.write", qos: .utility)
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Session Management

    /// Session ID for correlating events.
    public private(set) static var sessionID: String = UUID().uuidString.prefix(8).lowercased()

    /// Start a new Cast session and write header.
    public static func startSession(host: String, port: UInt16) {
        sessionID = UUID().uuidString.prefix(8).lowercased()
        writeSessionHeader(
            action: "CAST_SESSION_START",
            fields: ["host": host, "port": port]
        )
    }

    /// End the current session.
    public static func endSession() {
        writeSessionHeader(action: "CAST_SESSION_END", fields: [:])
    }

    // MARK: - Core Logging

    /// Log a structured Cast event.
    public static func log(
        _ action: String,
        category: String = "cast",
        level: String = "INF",
        fields: [String: Any] = [:]
    ) {
        let entry = formatEntry(action: action, category: category, level: level, fields: fields)
        queue.async {
            writeEntry(entry)
        }
    }

    // MARK: - Convenience — Socket

    public static func socketConnecting(host: String, port: UInt16) {
        log("SOCKET_CONNECTING", category: "socket", fields: ["host": host, "port": port])
    }

    public static func socketConnected(host: String) {
        log("SOCKET_CONNECTED", category: "socket", fields: ["host": host])
    }

    public static func socketDisconnected(reason: String? = nil) {
        log("SOCKET_DISCONNECTED", category: "socket", fields: ["reason": reason ?? "normal"])
    }

    public static func socketError(_ error: String) {
        log("SOCKET_ERROR", category: "socket", level: "ERR", fields: ["error": error])
    }

    public static func socketSend(namespace: String, destination: String, payloadSize: Int) {
        log("SEND", category: "socket", fields: [
            "ns": namespace.replacingOccurrences(of: "urn:x-cast:", with: ""),
            "dst": destination,
            "bytes": payloadSize
        ])
    }

    public static func socketRecv(namespace: String, source: String, payloadSize: Int) {
        log("RECV", category: "socket", fields: [
            "ns": namespace.replacingOccurrences(of: "urn:x-cast:", with: ""),
            "src": source,
            "bytes": payloadSize
        ])
    }

    // MARK: - Convenience — Channel

    public static func handshakeStep(_ step: String, detail: String? = nil) {
        var fields: [String: Any] = ["step": step]
        if let detail { fields["detail"] = detail }
        log("HANDSHAKE", category: "channel", fields: fields)
    }

    public static func requestSend(requestId: Int, type: String, namespace: String, destination: String) {
        log("REQUEST_SEND", category: "channel", fields: [
            "reqId": requestId,
            "type": type,
            "ns": namespace.replacingOccurrences(of: "urn:x-cast:", with: ""),
            "dst": destination
        ])
    }

    public static func requestResponse(requestId: Int, type: String?) {
        log("REQUEST_RESPONSE", category: "channel", fields: [
            "reqId": requestId,
            "type": type ?? "unknown"
        ])
    }

    public static func requestTimeout(requestId: Int) {
        log("REQUEST_TIMEOUT", category: "channel", level: "WRN", fields: ["reqId": requestId])
    }

    public static func sessionEstablished(sessionId: String, transportId: String) {
        log("SESSION_ESTABLISHED", category: "channel", fields: [
            "sessionId": sessionId,
            "transportId": transportId
        ])
    }

    public static func heartbeat(_ type: String) {
        log("HEARTBEAT", category: "channel", fields: ["type": type])
    }

    public static func messageRouted(namespace: String, type: String?, hasRequestId: Bool) {
        log("MSG_ROUTED", category: "channel", fields: [
            "ns": namespace.replacingOccurrences(of: "urn:x-cast:", with: ""),
            "type": type ?? "unknown",
            "hasReqId": hasRequestId
        ])
    }

    // MARK: - Convenience — Controller

    public static func controllerAction(_ action: String, fields: [String: Any] = [:]) {
        log(action, category: "controller", fields: fields)
    }

    public static func mediaLoad(url: String, contentType: String, startPosition: Double) {
        log("MEDIA_LOAD", category: "controller", fields: [
            "url": url,
            "contentType": contentType,
            "startPos": String(format: "%.1f", startPosition)
        ])
    }

    public static func mediaStatus(state: String, currentTime: Double, duration: Double) {
        log("MEDIA_STATUS", category: "controller", fields: [
            "state": state,
            "time": String(format: "%.1f", currentTime),
            "duration": String(format: "%.1f", duration)
        ])
    }

    public static func error(_ action: String, error: String) {
        log(action, category: "cast", level: "ERR", fields: ["error": error])
    }

    // MARK: - Format Helpers

    private static func formatEntry(
        action: String,
        category: String,
        level: String,
        fields: [String: Any]
    ) -> String {
        let ts = dateFormatter.string(from: Date())
        let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return "[\(ts)] [\(level)] [\(category)] \(action) session=\(sessionID) \(fieldsStr)"
    }

    private static func writeSessionHeader(action: String, fields: [String: Any]) {
        let ts = dateFormatter.string(from: Date())
        let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] \(action) session=\(sessionID) \(fieldsStr)\n\(separator)\n"
        queue.async {
            writeEntry(entry)
        }
    }

    private static func writeEntry(_ entry: String) {
        let line = entry + "\n"
        print(line, terminator: "")

        guard let data = line.data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: filePath) {
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            FileManager.default.createFile(atPath: filePath, contents: data)
        }
    }
}

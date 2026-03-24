import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Thread-safe WebSocket log transport. Sends structured log entries as JSON
/// to the remote transmux-log-viewer. Buffers entries when disconnected and
/// flushes on reconnect.
///
/// Uses `URLSessionWebSocketTask` — zero external dependencies.
actor RemoteLogTransport {

    // MARK: - Types

    struct LogEntry: Codable, Sendable {
        let type: String // always "log"
        let timestamp: String
        let level: String
        let category: String
        let tag: String
        let message: String
        let fields: [String: String]?
        let sessionId: String?
    }

    struct DeviceHandshake: Codable, Sendable {
        let type: String // "handshake"
        let deviceName: String
        let appVersion: String
        let systemVersion: String
        let playerState: String
    }

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var buffer: [LogEntry] = []
    private let maxBuffer = 1000
    private var isConnected = false
    private var reconnectTask: Task<Void, Never>?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Public API

    /// Connect to the remote debug viewer WebSocket.
    func connect(to url: URL) {
        disconnect()
        let ws = session.webSocketTask(with: url)
        webSocketTask = ws
        ws.resume()
        isConnected = true

        // Send handshake
        Task { await sendHandshake() }

        // Flush buffered entries
        Task { await flushBuffer() }

        // Start receive loop (for commands — handled by RemoteDebugService)
        Task { await receiveLoop() }
    }

    /// Disconnect and stop reconnection attempts.
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    /// Send a log entry. If disconnected, buffers it (ring buffer).
    func send(
        level: String,
        category: String,
        tag: String,
        message: String,
        fields: [String: String]? = nil,
        sessionId: String? = nil
    ) {
        let entry = LogEntry(
            type: "log",
            timestamp: isoFormatter.string(from: Date()),
            level: level,
            category: category,
            tag: tag,
            message: message,
            fields: fields,
            sessionId: sessionId
        )

        guard isConnected, webSocketTask != nil else {
            bufferEntry(entry)
            return
        }

        Task { await sendEntry(entry) }
    }

    /// Whether currently connected to a viewer.
    var connected: Bool { isConnected }

    /// Callback for incoming messages (commands from viewer).
    /// Set by RemoteDebugService.
    var onMessage: ((Data) -> Void)?

    // MARK: - Private

    private func sendEntry(_ entry: LogEntry) {
        guard let data = try? encoder.encode(entry),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { [weak self] error in
            if error != nil {
                Task { await self?.handleDisconnect() }
            }
        }
    }

    private func sendHandshake() {
        let handshake = DeviceHandshake(
            type: "handshake",
            deviceName: deviceName(),
            appVersion: appVersion(),
            systemVersion: systemVersion(),
            playerState: "idle"
        )
        guard let data = try? encoder.encode(handshake),
              let text = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(text)) { _ in }
    }

    private func bufferEntry(_ entry: LogEntry) {
        buffer.append(entry)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }
    }

    private func flushBuffer() {
        guard isConnected else { return }
        let entries = buffer
        buffer.removeAll()
        for entry in entries {
            sendEntry(entry)
        }
    }

    private func receiveLoop() {
        guard let ws = webSocketTask else { return }
        ws.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        Task { await self?.onMessage?(data) }
                    }
                case .data(let data):
                    Task { await self?.onMessage?(data) }
                @unknown default:
                    break
                }
                // Continue receiving
                Task { await self?.receiveLoop() }
            case .failure:
                Task { await self?.handleDisconnect() }
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        webSocketTask = nil
    }

    // MARK: - Device Info Helpers

    private func deviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    private func systemVersion() -> String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #elseif os(macOS)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "unknown"
        #endif
    }
}

import Foundation
import Network

/// Receives logs from remote iOS devices via WebSocket.
/// Runs on macOS as an NWListener that accepts WS connections from iOS apps
/// on the same LAN. Also publishes a Bonjour service so iOS devices can
/// auto-discover this Mac.
///
/// Usage:
/// ```swift
/// let receiver = RemoteLogReceiver.shared
/// receiver.onLogReceived = { entry in
///     // Display in DebugStreamingView
/// }
/// receiver.start()
/// ```
@MainActor
@Observable
final class RemoteLogReceiver {

    // MARK: - Singleton

    static let shared = RemoteLogReceiver()

    // MARK: - Types

    struct RemoteLogEntry: Codable, Sendable {
        let type: String
        let timestamp: String
        let level: String
        let category: String
        let tag: String
        let message: String
        let fields: [String: String]?
        let sessionId: String?
    }

    struct DeviceHandshake: Codable, Sendable {
        let type: String
        let deviceName: String
        let appVersion: String
        let systemVersion: String
        let playerState: String
    }

    struct ConnectedDevice: Sendable {
        let id: String
        let name: String
        let systemVersion: String
        let appVersion: String
        let connectedAt: Date
    }

    // MARK: - Observable State

    private(set) var isListening = false
    private(set) var connectedDevices: [ConnectedDevice] = []
    private(set) var port: UInt16 = 0

    // MARK: - Callbacks

    /// Called for every log entry received from a remote device.
    var onLogReceived: ((RemoteLogEntry, ConnectedDevice) -> Void)?

    // MARK: - Private

    private var listener: NWListener?
    private var connections: [String: NWConnection] = [:]
    private var deviceInfo: [String: ConnectedDevice] = [:]
    private let bonjourType = "_mksiptv-debug._tcp"
    private let decoder = JSONDecoder()

    private init() {}

    // MARK: - Public API

    /// Start listening for incoming WebSocket connections and publish Bonjour.
    func start() {
        guard listener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true

            // Enable WebSocket protocol
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            let listener = try NWListener(using: params, on: .any)
            self.listener = listener

            listener.service = NWListener.Service(
                name: "MKS-IPTV Debug (\(Host.current().localizedName ?? "Mac"))",
                type: bonjourType,
                txtRecord: NWTXTRecord(["ws": "/ws/device", "version": "1.0"])
            )

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        self?.port = listener.port?.rawValue ?? 0
                        MKSLog.debug.info("RemoteLogReceiver: listening on port \(self?.port ?? 0)")
                    case .failed(let error):
                        self?.isListening = false
                        MKSLog.debug.error("RemoteLogReceiver: listener failed: \(error)")
                    case .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleNewConnection(connection)
                }
            }

            listener.start(queue: .main)
        } catch {
            MKSLog.debug.error("RemoteLogReceiver: failed to start: \(error)")
        }
    }

    /// Stop listening and disconnect all devices.
    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        deviceInfo.removeAll()
        connectedDevices.removeAll()
    }

    /// Send a command to a connected device.
    func sendCommand(_ command: String, payload: [String: String]? = nil, to deviceId: String? = nil) {
        let targetId = deviceId ?? connections.keys.first
        guard let id = targetId, let connection = connections[id] else {
            MKSLog.debug.warning("RemoteLogReceiver: no device connected to send command")
            return
        }

        let msg: [String: Any] = [
            "type": "command",
            "command": command,
            "payload": payload ?? [:]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let text = String(data: data, encoding: .utf8) else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "command", metadata: [metadata])
        connection.send(content: text.data(using: .utf8), contentContext: context, completion: .idempotent)
        MKSLog.debug.info("RemoteLogReceiver: sent command '\(command)' to \(deviceInfo[id]?.name ?? id)")
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        let id = UUID().uuidString.prefix(8).description
        connections[id] = connection

        MKSLog.debug.info("RemoteLogReceiver: new connection \(id)")

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    MKSLog.debug.info("RemoteLogReceiver: connection \(id) ready")
                    self?.receiveMessages(from: connection, id: id)
                case .failed, .cancelled:
                    self?.removeDevice(id: id)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
    }

    private func receiveMessages(from connection: NWConnection, id: String) {
        connection.receiveMessage { [weak self] content, contentContext, _, error in
            guard let self else { return }

            if let error {
                MKSLog.debug.debug("RemoteLogReceiver: receive error on \(id): \(error)")
                Task { @MainActor in self.removeDevice(id: id) }
                return
            }

            if let data = content {
                Task { @MainActor in
                    self.handleMessage(data, from: id)
                }
            }

            // Continue receiving
            Task { @MainActor in
                self.receiveMessages(from: connection, id: id)
            }
        }
    }

    private func handleMessage(_ data: Data, from id: String) {
        // Try handshake first
        if let handshake = try? decoder.decode(DeviceHandshake.self, from: data),
           handshake.type == "handshake" {
            let device = ConnectedDevice(
                id: id,
                name: handshake.deviceName,
                systemVersion: handshake.systemVersion,
                appVersion: handshake.appVersion,
                connectedAt: Date()
            )
            deviceInfo[id] = device
            connectedDevices = Array(deviceInfo.values)
            MKSLog.debug.info("RemoteLogReceiver: device identified: \(device.name) (\(device.systemVersion))")
            return
        }

        // Try log entry
        if let entry = try? decoder.decode(RemoteLogEntry.self, from: data),
           entry.type == "log" {
            let device = deviceInfo[id] ?? ConnectedDevice(
                id: id, name: "Unknown", systemVersion: "?", appVersion: "?", connectedAt: Date()
            )
            onLogReceived?(entry, device)
        }
    }

    private func removeDevice(id: String) {
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        deviceInfo.removeValue(forKey: id)
        connectedDevices = Array(deviceInfo.values)
        MKSLog.debug.info("RemoteLogReceiver: device \(id) disconnected")
    }
}

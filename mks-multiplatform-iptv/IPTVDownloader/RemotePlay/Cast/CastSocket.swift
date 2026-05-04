//
//  CastSocket.swift
//  mks-multiplatform-iptv
//
//  TLS connection to Chromecast on port 8009 using NWConnection.
//  Sends/receives length-prefixed protobuf CastMessage frames.
//

import Foundation
import Network
import IPTVCore

/// Manages a TLS socket connection to a Chromecast device on port 8009.
/// Sends and receives length-prefixed protobuf frames using `NWConnection`.
///
/// Chromecast devices use self-signed TLS certificates, so the TLS configuration
/// accepts all certificates via `sec_protocol_options_set_verify_block`.
actor CastSocket {

    // MARK: - Properties

    /// Target host IP address.
    private let host: String

    /// Target port (always 8009 for Cast V2).
    private let port: UInt16

    /// Underlying NWConnection.
    private var connection: NWConnection?

    /// Whether the socket is currently connected.
    private(set) var isConnected = false

    /// Callback invoked on the main actor when a message is received.
    var onMessageReceived: (@Sendable (CastMessage) -> Void)?

    /// Background task running the receive loop.
    private var receiveTask: Task<Void, Never>?

    /// Connection timeout in seconds.
    private let connectTimeout: TimeInterval = 10.0

    // MARK: - Initialization

    /// Create a CastSocket targeting a Chromecast device.
    /// - Parameters:
    ///   - host: IP address of the Chromecast (e.g. "192.168.1.128").
    ///   - port: Cast V2 port (default 8009).
    init(host: String, port: UInt16 = 8009) {
        self.host = host
        self.port = port
    }

    // MARK: - Connection

    /// Establish TLS connection to the Chromecast.
    /// - Throws: `RemotePlayError.connectionFailed` if connection fails or times out.
    func connect() async throws {
        CastLog.socketConnecting(host: host, port: port)

        let tlsOptions = NWProtocolTLS.Options()

        // Accept self-signed certificates (Chromecast uses self-signed certs)
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in
                completionHandler(true)
            },
            DispatchQueue.global(qos: .userInitiated)
        )

        // Set minimum TLS version to 1.2
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv12
        )

        let params = NWParameters(tls: tlsOptions)
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        let conn = NWConnection(host: nwHost, port: nwPort, using: params)
        self.connection = conn

        // Wait for connection ready or failure
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            let resumeOnce: (Result<Void, Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(.success(()))
                case .failed(let error):
                    CastLog.socketError("TLS failed: \(error.localizedDescription)")
                    resumeOnce(.failure(RemotePlayError.connectionFailed("Cast TLS failed: \(error.localizedDescription)")))
                case .cancelled:
                    CastLog.socketError("Connection cancelled")
                    resumeOnce(.failure(RemotePlayError.connectionFailed("Cast connection cancelled")))
                case .waiting(let error):
                    CastLog.log("SOCKET_WAITING", category: "socket", level: "WRN", fields: ["error": error.localizedDescription])
                default:
                    break
                }
            }

            conn.start(queue: DispatchQueue.global(qos: .userInitiated))

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + self.connectTimeout) {
                CastLog.socketError("Connection timeout after \(self.connectTimeout)s")
                resumeOnce(.failure(RemotePlayError.connectionTimeout))
            }
        }

        isConnected = true
        CastLog.socketConnected(host: host)
        startReceiveLoop()
    }

    /// Send a CastMessage over the TLS connection.
    /// - Parameter message: The CastMessage to send.
    /// - Throws: `RemotePlayError.transportError` if send fails.
    func send(_ message: CastMessage) async throws {
        guard let connection, isConnected else {
            throw RemotePlayError.transportError("Cast socket not connected")
        }

        let data = message.encodeFramed()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    CastLog.socketError("Send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: RemotePlayError.transportError("Cast send failed: \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Disconnect and cleanup.
    func disconnect() {
        CastLog.socketDisconnected()
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
    }

    // MARK: - Receive Loop

    /// Start background task that reads length-prefixed protobuf frames.
    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                do {
                    // Read 4-byte length prefix
                    let lengthData = try await self.readExact(count: 4)
                    let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

                    guard length > 0, length < 1_000_000 else {
                        CastLog.socketError("Invalid frame length: \(length)")
                        break
                    }

                    // Read exactly `length` bytes of protobuf payload
                    let payload = try await self.readExact(count: Int(length))

                    // Decode and dispatch
                    if let message = CastMessage.decodeFromProtobuf(payload) {
                        CastLog.socketRecv(
                            namespace: message.namespace,
                            source: message.sourceId,
                            payloadSize: message.payloadUtf8.utf8.count
                        )
                        let callback = await self.onMessageReceived
                        callback?(message)
                    } else {
                        CastLog.socketError("Failed to decode protobuf frame (\(length) bytes)")
                    }
                } catch {
                    if !Task.isCancelled {
                        CastLog.socketError("Receive loop error: \(error.localizedDescription)")
                    }
                    break
                }
            }

            // Connection died — mark as disconnected
            if !Task.isCancelled {
                CastLog.socketDisconnected(reason: "receive loop ended")
                await self?.markDisconnected()
            }
        }
    }

    /// Mark socket as disconnected (called from receive loop on failure).
    private func markDisconnected() {
        isConnected = false
    }

    /// Read exactly `count` bytes from the connection, accumulating partial reads.
    /// - Parameter count: Number of bytes to read.
    /// - Returns: Data of exactly `count` bytes.
    /// - Throws: Error if connection fails or is cancelled.
    private func readExact(count: Int) async throws -> Data {
        guard let connection else {
            throw RemotePlayError.transportError("Cast socket not connected")
        }

        var accumulated = Data()
        accumulated.reserveCapacity(count)

        while accumulated.count < count {
            let remaining = count - accumulated.count

            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { content, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let content, !content.isEmpty {
                        continuation.resume(returning: content)
                    } else if isComplete {
                        continuation.resume(throwing: RemotePlayError.deviceDisconnected)
                    } else {
                        continuation.resume(throwing: RemotePlayError.transportError("Cast socket: empty read"))
                    }
                }
            }

            accumulated.append(chunk)
        }

        return accumulated
    }
}

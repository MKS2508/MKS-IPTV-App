//
//  CastChannel.swift
//  mks-multiplatform-iptv
//
//  Cast V2 protocol state machine — connection handshake, heartbeat,
//  message routing, and request/response correlation.
//

import Foundation
import IPTVCore

// MARK: - Cast Namespaces

/// Standard Cast V2 protocol namespaces.
enum CastNamespace {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat  = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver   = "urn:x-cast:com.google.cast.receiver"
    static let media      = "urn:x-cast:com.google.cast.media"
}

// MARK: - Cast Session

/// Represents an active Cast session with the Default Media Receiver.
struct CastSession: Sendable {
    /// The session ID assigned by the receiver.
    let sessionId: String

    /// The transport ID for addressing the media application.
    let transportId: String
}

// MARK: - Cast Media Status

/// Parsed media status from a MEDIA_STATUS response.
struct CastMediaStatus: Sendable {
    let mediaSessionId: Int
    let playerState: String
    let currentTime: Double
    let duration: Double
    let volume: Float
    let isMuted: Bool
}

// MARK: - CastChannel

/// Cast V2 protocol orchestrator — manages connection lifecycle, heartbeat,
/// and media commands over a CastSocket.
///
/// ## Connection Flow
/// 1. CONNECT to "receiver-0" on connection namespace
/// 2. GET_STATUS on receiver namespace -> receiver status
/// 3. LAUNCH CC1AD845 (Default Media Receiver) on receiver namespace
/// 4. Wait for RECEIVER_STATUS with sessionId + transportId
/// 5. CONNECT to transportId on connection namespace
/// 6. Start heartbeat (PING every 5s to receiver-0)
actor CastChannel {

    // MARK: - Constants

    /// Sender ID for all outgoing messages.
    private static let senderId = "sender-0"

    /// Default receiver destination.
    private static let receiverId = "receiver-0"

    /// Default Media Receiver app ID.
    private static let defaultMediaReceiverAppId = "CC1AD845"

    /// Heartbeat interval in seconds.
    private static let heartbeatInterval: TimeInterval = 5.0

    /// Request timeout in seconds.
    private static let requestTimeout: TimeInterval = 15.0

    // MARK: - Properties

    /// Underlying TLS socket.
    private let socket: CastSocket

    /// Active Cast session (set after LAUNCH succeeds).
    private(set) var session: CastSession?

    /// Auto-incrementing request ID for correlation.
    private var nextRequestId: Int = 1

    /// Pending request continuations keyed by requestId.
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]

    /// Heartbeat task.
    private var heartbeatTask: Task<Void, Never>?

    /// Whether a PONG was received since last PING.
    private var pongReceived = true

    /// Current media session ID (from MEDIA_STATUS).
    private(set) var mediaSessionId: Int?

    /// Callback for media status updates.
    var onMediaStatusUpdate: (@Sendable (CastMediaStatus) -> Void)?

    /// Callback for state changes (errors, disconnects).
    var onStateChanged: (@Sendable (CastSessionState) -> Void)?

    // MARK: - Initialization

    /// Create a CastChannel with a connected CastSocket.
    /// - Parameter socket: The TLS socket to communicate over.
    init(socket: CastSocket) {
        self.socket = socket
    }

    // MARK: - Connection Flow

    /// Execute the full Cast V2 connection handshake.
    /// Connects to receiver, launches Default Media Receiver, establishes session.
    func connect() async throws {
        CastLog.handshakeStep("BEGIN")

        // Setup message routing
        await socket.set(onMessageReceived: { [weak self] message in
            Task { [weak self] in
                await self?.handleMessage(message)
            }
        })

        // Step 1: CONNECT to receiver-0
        CastLog.handshakeStep("CONNECT_RECEIVER", detail: Self.receiverId)
        try await sendConnect(to: Self.receiverId)

        // Step 2: GET_STATUS to check current receiver state
        CastLog.handshakeStep("GET_STATUS")
        let receiverStatus = try await sendRequest(
            namespace: CastNamespace.receiver,
            destination: Self.receiverId,
            payload: ["type": "GET_STATUS"]
        )

        // Check if Default Media Receiver is already running (only reuse CC1AD845, not YouTube etc.)
        if let existingSession = extractSession(from: receiverStatus, requiredAppId: Self.defaultMediaReceiverAppId) {
            CastLog.handshakeStep("EXISTING_SESSION", detail: "sid=\(existingSession.sessionId) tid=\(existingSession.transportId)")
            self.session = existingSession
            try await sendConnect(to: existingSession.transportId)
            CastLog.sessionEstablished(sessionId: existingSession.sessionId, transportId: existingSession.transportId)
            startHeartbeat()
            return
        }

        // Step 3: LAUNCH Default Media Receiver
        CastLog.handshakeStep("LAUNCH", detail: Self.defaultMediaReceiverAppId)
        let launchResponse = try await sendRequest(
            namespace: CastNamespace.receiver,
            destination: Self.receiverId,
            payload: ["type": "LAUNCH", "appId": Self.defaultMediaReceiverAppId]
        )

        // Step 4: Extract session from RECEIVER_STATUS
        guard let newSession = extractSession(from: launchResponse) else {
            CastLog.error("HANDSHAKE_FAILED", error: "No session in LAUNCH response")
            throw RemotePlayError.connectionFailed("Cast: no session in LAUNCH response")
        }

        self.session = newSession
        CastLog.handshakeStep("SESSION_ACQUIRED", detail: "sid=\(newSession.sessionId) tid=\(newSession.transportId)")

        // Step 5: CONNECT to transport (media app)
        CastLog.handshakeStep("CONNECT_TRANSPORT", detail: newSession.transportId)
        try await sendConnect(to: newSession.transportId)

        // Step 6: Start heartbeat
        CastLog.handshakeStep("COMPLETE")
        CastLog.sessionEstablished(sessionId: newSession.sessionId, transportId: newSession.transportId)
        startHeartbeat()
    }

    /// Disconnect from the Cast device. Sends CLOSE and stops heartbeat.
    func disconnect() async {
        CastLog.log("DISCONNECT", category: "channel")
        stopHeartbeat()

        // Send CLOSE to transport if session exists
        if let session {
            try? await sendMessage(
                namespace: CastNamespace.connection,
                destination: session.transportId,
                payload: "{\"type\":\"CLOSE\"}"
            )
        }

        // Send CLOSE to receiver
        try? await sendMessage(
            namespace: CastNamespace.connection,
            destination: Self.receiverId,
            payload: "{\"type\":\"CLOSE\"}"
        )

        // Cancel all pending requests
        let pendingCount = pendingRequests.count
        for (requestId, continuation) in pendingRequests {
            CastLog.log("CANCEL_PENDING", category: "channel", fields: ["reqId": requestId])
            continuation.resume(throwing: RemotePlayError.deviceDisconnected)
        }
        pendingRequests.removeAll()

        if pendingCount > 0 {
            CastLog.log("CANCELLED_REQUESTS", category: "channel", fields: ["count": pendingCount])
        }

        self.session = nil
        self.mediaSessionId = nil

        await socket.disconnect()
    }

    // MARK: - Media Commands

    /// Load media on the Cast device.
    func loadMedia(
        contentURL: URL,
        contentType: String,
        metadata: [String: Any],
        autoplay: Bool = true,
        currentTime: Double = 0
    ) async throws {
        guard let session else {
            throw RemotePlayError.transportError("Cast: no active session")
        }

        CastLog.mediaLoad(
            url: contentURL.absoluteString,
            contentType: contentType,
            startPosition: currentTime
        )

        var mediaObject: [String: Any] = [
            "contentId": contentURL.absoluteString,
            "contentType": contentType,
            "streamType": "BUFFERED",
            "metadata": metadata
        ]

        // NOTE: fMP4 segment format hints intentionally omitted.
        // Shaka Player auto-detects fMP4 from the #EXT-X-MAP tag in the HLS manifest.
        // Sending hlsSegmentFormat="fmp4" causes LOAD_FAILED on some Cast devices
        // (LEAP-S1, TELEFUNKEN). Omitting lets Shaka handle detection natively.

        var payload: [String: Any] = [
            "type": "LOAD",
            "sessionId": session.sessionId,
            "media": mediaObject,
            "autoplay": autoplay,
            "currentTime": currentTime,
            "customData": [String: Any]()
        ]

        let response = try await sendRequest(
            namespace: CastNamespace.media,
            destination: session.transportId,
            payload: payload
        )

        // Extract mediaSessionId from response
        if let statusArray = response["status"] as? [[String: Any]],
           let firstStatus = statusArray.first,
           let msId = firstStatus["mediaSessionId"] as? Int {
            self.mediaSessionId = msId
            CastLog.log("MEDIA_SESSION_ID", category: "channel", fields: ["msId": msId])
        }

        // Check for LOAD error
        if let type = response["type"] as? String, type == "LOAD_FAILED" {
            let reason = response["detailedErrorCode"] as? Int ?? -1
            CastLog.error("LOAD_FAILED", error: "detailedErrorCode=\(reason)")
            throw RemotePlayError.transportError("Cast LOAD failed: errorCode=\(reason)")
        }
    }

    /// Send PLAY command to resume playback.
    func play() async throws {
        CastLog.controllerAction("PLAY")
        try await sendMediaCommand("PLAY")
    }

    /// Send PAUSE command.
    func pause() async throws {
        CastLog.controllerAction("PAUSE")
        try await sendMediaCommand("PAUSE")
    }

    /// Send STOP command to end media playback.
    func stop() async throws {
        CastLog.controllerAction("STOP")
        try await sendMediaCommand("STOP")
    }

    /// Seek to a specific position.
    func seek(to currentTime: Double) async throws {
        guard let session, let mediaSessionId else {
            throw RemotePlayError.transportError("Cast: no media session for seek")
        }

        CastLog.controllerAction("SEEK", fields: ["to": String(format: "%.1f", currentTime)])

        let payload: [String: Any] = [
            "type": "SEEK",
            "mediaSessionId": mediaSessionId,
            "currentTime": currentTime,
            "resumeState": "PLAYBACK_START",
            "sessionId": session.sessionId
        ]

        _ = try await sendRequest(
            namespace: CastNamespace.media,
            destination: session.transportId,
            payload: payload
        )
    }

    /// Set volume level and/or mute state on the receiver.
    func setVolume(level: Float? = nil, muted: Bool? = nil) async throws {
        var volumeDict: [String: Any] = [:]
        if let level { volumeDict["level"] = Double(level) }
        if let muted { volumeDict["muted"] = muted }

        CastLog.controllerAction("SET_VOLUME", fields: volumeDict)

        let payload: [String: Any] = [
            "type": "SET_VOLUME",
            "volume": volumeDict
        ]

        _ = try await sendRequest(
            namespace: CastNamespace.receiver,
            destination: Self.receiverId,
            payload: payload
        )
    }

    /// Request current media status.
    func getMediaStatus() async throws -> CastMediaStatus? {
        guard let session else { return nil }

        let response = try await sendRequest(
            namespace: CastNamespace.media,
            destination: session.transportId,
            payload: ["type": "GET_STATUS"]
        )

        return parseMediaStatus(from: response)
    }

    /// Request current receiver status (for volume info).
    func getReceiverStatus() async throws -> [String: Any] {
        return try await sendRequest(
            namespace: CastNamespace.receiver,
            destination: Self.receiverId,
            payload: ["type": "GET_STATUS"]
        )
    }

    // MARK: - Message Handling

    /// Route incoming messages by namespace.
    private func handleMessage(_ message: CastMessage) {
        let json = parseJSON(message.payloadUtf8)
        let msgType = json?["type"] as? String
        let hasReqId = json?["requestId"] != nil

        CastLog.messageRouted(namespace: message.namespace, type: msgType, hasRequestId: hasReqId)

        switch message.namespace {
        case CastNamespace.heartbeat:
            handleHeartbeat(message)

        case CastNamespace.receiver:
            handleReceiverMessage(message)

        case CastNamespace.media:
            handleMediaMessage(message)

        case CastNamespace.connection:
            handleConnectionMessage(message)

        default:
            CastLog.log("UNKNOWN_NAMESPACE", category: "channel", level: "WRN", fields: [
                "ns": message.namespace
            ])
        }
    }

    /// Handle heartbeat messages (PING/PONG).
    private func handleHeartbeat(_ message: CastMessage) {
        guard let json = parseJSON(message.payloadUtf8),
              let type = json["type"] as? String else { return }

        if type == "PING" {
            CastLog.heartbeat("PING_RECV")
            // Respond with PONG
            Task {
                try? await sendMessage(
                    namespace: CastNamespace.heartbeat,
                    destination: message.sourceId,
                    payload: "{\"type\":\"PONG\"}"
                )
            }
        } else if type == "PONG" {
            CastLog.heartbeat("PONG_RECV")
            pongReceived = true
        }
    }

    /// Handle receiver namespace messages (RECEIVER_STATUS, LAUNCH_ERROR).
    private func handleReceiverMessage(_ message: CastMessage) {
        guard let json = parseJSON(message.payloadUtf8) else { return }
        let type = json["type"] as? String

        // Check for requestId -> resume pending continuation
        if let requestId = json["requestId"] as? Int,
           let continuation = pendingRequests.removeValue(forKey: requestId) {
            CastLog.requestResponse(requestId: requestId, type: type)
            continuation.resume(returning: json)
            return
        }

        // Unsolicited RECEIVER_STATUS — update session if needed
        if type == "RECEIVER_STATUS" {
            if let newSession = extractSession(from: json), session == nil {
                self.session = newSession
                CastLog.log("UNSOLICITED_SESSION", category: "channel", fields: [
                    "sid": newSession.sessionId,
                    "tid": newSession.transportId
                ])
            }
        } else if type == "LAUNCH_ERROR" {
            let reason = json["reason"] as? String ?? "unknown"
            CastLog.error("LAUNCH_ERROR", error: reason)
        }
    }

    /// Handle media namespace messages (MEDIA_STATUS).
    private func handleMediaMessage(_ message: CastMessage) {
        guard let json = parseJSON(message.payloadUtf8) else { return }
        let type = json["type"] as? String

        // Check for requestId -> resume pending continuation
        if let requestId = json["requestId"] as? Int,
           let continuation = pendingRequests.removeValue(forKey: requestId) {
            CastLog.requestResponse(requestId: requestId, type: type)
            continuation.resume(returning: json)
            return
        }

        // Unsolicited MEDIA_STATUS — update state
        if let status = parseMediaStatus(from: json) {
            self.mediaSessionId = status.mediaSessionId
            CastLog.mediaStatus(
                state: status.playerState,
                currentTime: status.currentTime,
                duration: status.duration
            )
            onMediaStatusUpdate?(status)
        }
    }

    /// Handle connection namespace messages (CLOSE).
    private func handleConnectionMessage(_ message: CastMessage) {
        guard let json = parseJSON(message.payloadUtf8),
              let type = json["type"] as? String else { return }

        if type == "CLOSE" {
            CastLog.log("DEVICE_CLOSE", category: "channel", level: "WRN", fields: [
                "from": message.sourceId
            ])
            onStateChanged?(.disconnected)
        }
    }

    // MARK: - Sending Helpers

    /// Send a CONNECT message on the connection namespace.
    private func sendConnect(to destination: String) async throws {
        try await sendMessage(
            namespace: CastNamespace.connection,
            destination: destination,
            payload: "{\"type\":\"CONNECT\",\"origin\":{}}"
        )
    }

    /// Send a raw message (no response expected).
    private func sendMessage(namespace: String, destination: String, payload: String) async throws {
        let message = CastMessage(
            sourceId: Self.senderId,
            destinationId: destination,
            namespace: namespace,
            payloadUtf8: payload
        )

        CastLog.socketSend(namespace: namespace, destination: destination, payloadSize: payload.utf8.count)
        try await socket.send(message)
    }

    /// Send a request with auto-incrementing requestId and wait for response.
    ///
    /// ## Fix (critical)
    /// The continuation is stored **synchronously on the actor** BEFORE the message
    /// is sent. This eliminates the race condition where a fast response arrives
    /// before the continuation is registered, causing it to be dropped.
    /// A separate timeout Task cleans up the continuation if no response arrives.
    @discardableResult
    private func sendRequest(
        namespace: String,
        destination: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        let requestId = nextRequestId
        nextRequestId += 1

        var fullPayload = payload
        fullPayload["requestId"] = requestId

        let type = payload["type"] as? String ?? "unknown"

        guard let jsonData = try? JSONSerialization.data(withJSONObject: fullPayload, options: []),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw RemotePlayError.transportError("Cast: failed to serialize JSON payload")
        }

        CastLog.requestSend(requestId: requestId, type: type, namespace: namespace, destination: destination)

        // Use withCheckedThrowingContinuation — the body runs synchronously on
        // the actor, so we can store the continuation BEFORE any message is sent.
        // This eliminates the race condition entirely.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            // 1. Store continuation FIRST (synchronous, on-actor)
            pendingRequests[requestId] = continuation

            // 2. Send the message asynchronously (fire-and-forget)
            Task { [weak self] in
                do {
                    try await self?.sendMessage(
                        namespace: namespace,
                        destination: destination,
                        payload: jsonString
                    )
                } catch {
                    // Send failed — remove continuation and resume with error
                    if let cont = await self?.removePendingRequest(for: requestId) {
                        CastLog.error("SEND_FAILED", error: "\(type) reqId=\(requestId): \(error.localizedDescription)")
                        cont.resume(throwing: error)
                    }
                }
            }

            // 3. Timeout — clean up continuation if no response arrives
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(CastChannel.requestTimeout))
                if let cont = await self?.removePendingRequest(for: requestId) {
                    CastLog.requestTimeout(requestId: requestId)
                    cont.resume(throwing: RemotePlayError.connectionTimeout)
                }
            }
        }
    }

    /// Atomically remove and return a pending request continuation.
    private func removePendingRequest(for requestId: Int) -> CheckedContinuation<[String: Any], Error>? {
        return pendingRequests.removeValue(forKey: requestId)
    }

    /// Send a simple media command (PLAY, PAUSE, STOP).
    private func sendMediaCommand(_ type: String) async throws {
        guard let session, let mediaSessionId else {
            throw RemotePlayError.transportError("Cast: no media session for \(type)")
        }

        let payload: [String: Any] = [
            "type": type,
            "mediaSessionId": mediaSessionId,
            "sessionId": session.sessionId
        ]

        _ = try await sendRequest(
            namespace: CastNamespace.media,
            destination: session.transportId,
            payload: payload
        )
    }

    // MARK: - Heartbeat

    /// Start sending PING every 5 seconds.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        pongReceived = true

        CastLog.heartbeat("START")

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(CastChannel.heartbeatInterval))
                guard !Task.isCancelled, let self else { break }

                // Check if previous PONG was received
                let gotPong = await self.pongReceived
                if !gotPong {
                    CastLog.error("HEARTBEAT_TIMEOUT", error: "No PONG received within \(CastChannel.heartbeatInterval)s")
                    await self.onStateChanged?(.error("Heartbeat timeout"))
                    break
                }

                await self.setPongReceived(false)

                do {
                    try await self.sendMessage(
                        namespace: CastNamespace.heartbeat,
                        destination: CastChannel.receiverId,
                        payload: "{\"type\":\"PING\"}"
                    )
                    CastLog.heartbeat("PING_SENT")
                } catch {
                    CastLog.error("HEARTBEAT_SEND_FAILED", error: error.localizedDescription)
                    break
                }
            }
        }
    }

    /// Set pongReceived flag.
    private func setPongReceived(_ value: Bool) {
        pongReceived = value
    }

    /// Stop heartbeat task.
    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        CastLog.heartbeat("STOP")
    }

    // MARK: - Parsing Helpers

    /// Parse JSON string to dictionary.
    private func parseJSON(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    /// Extract CastSession from a RECEIVER_STATUS response.
    private func extractSession(from response: [String: Any], requiredAppId: String? = nil) -> CastSession? {
        guard let status = response["status"] as? [String: Any],
              let applications = status["applications"] as? [[String: Any]],
              let app = applications.first,
              let sessionId = app["sessionId"] as? String,
              let transportId = app["transportId"] as? String else {
            return nil
        }
        // Only reuse session if it matches the required app (e.g. CC1AD845)
        if let required = requiredAppId {
            guard let appId = app["appId"] as? String, appId == required else { return nil }
        }
        return CastSession(sessionId: sessionId, transportId: transportId)
    }

    /// Parse CastMediaStatus from a MEDIA_STATUS response.
    /// The `status` field is an **array** — use the first element.
    private func parseMediaStatus(from response: [String: Any]) -> CastMediaStatus? {
        guard let statusArray = response["status"] as? [[String: Any]],
              let status = statusArray.first else {
            return nil
        }

        let mediaSessionId = status["mediaSessionId"] as? Int ?? 0
        let playerState = status["playerState"] as? String ?? "UNKNOWN"
        let currentTime = status["currentTime"] as? Double ?? 0

        // Duration is nested inside media object
        var duration: Double = 0
        if let media = status["media"] as? [String: Any] {
            duration = media["duration"] as? Double ?? 0
        }

        // Volume info
        var volumeLevel: Float = 1.0
        var isMuted = false
        if let volume = status["volume"] as? [String: Any] {
            volumeLevel = Float(volume["level"] as? Double ?? 1.0)
            isMuted = volume["muted"] as? Bool ?? false
        }

        return CastMediaStatus(
            mediaSessionId: mediaSessionId,
            playerState: playerState,
            currentTime: currentTime,
            duration: duration,
            volume: volumeLevel,
            isMuted: isMuted
        )
    }
}

// MARK: - CastSocket Extension

/// Extension to allow CastChannel to set the message callback on CastSocket.
extension CastSocket {
    /// Set the message received callback.
    func set(onMessageReceived callback: (@Sendable (CastMessage) -> Void)?) {
        self.onMessageReceived = callback
    }
}

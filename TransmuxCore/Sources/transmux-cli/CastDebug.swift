//
//  CastDebug.swift
//  transmux-cli
//
//  Self-contained Google Cast V2 protocol debug client.
//  Connects to a Chromecast, performs the full handshake, and sends LOAD.
//  All protocol messages are logged to stdout for debugging.
//
//  Usage: transmux-cli <input> --cast <ip> [--verbose]
//

import Foundation
import Network

// MARK: - Cast Error

/// Minimal error type for the Cast debug client.
enum CastError: LocalizedError, Sendable {
    case connectionFailed(String)
    case connectionTimeout
    case transportError(String)
    case deviceDisconnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let r): return "Connection failed: \(r)"
        case .connectionTimeout: return "Connection timed out"
        case .transportError(let r): return "Transport error: \(r)"
        case .deviceDisconnected: return "Device disconnected"
        }
    }
}

// MARK: - Protobuf Codec

/// Minimal protobuf encoder/decoder for Cast V2 CastMessage wire format.
/// Wire format: [4-byte big-endian length][protobuf bytes]
enum CastProto {

    struct Message: Sendable {
        let sourceId: String
        let destinationId: String
        let namespace: String
        let payloadUtf8: String

        func encodeFramed() -> Data {
            var body = Data()
            appendVarint(to: &body, fieldNumber: 1, value: 0)      // protocol_version
            appendString(to: &body, fieldNumber: 2, value: sourceId)
            appendString(to: &body, fieldNumber: 3, value: destinationId)
            appendString(to: &body, fieldNumber: 4, value: namespace)
            appendVarint(to: &body, fieldNumber: 5, value: 0)      // payload_type = STRING
            appendString(to: &body, fieldNumber: 6, value: payloadUtf8)

            var frame = Data()
            var length = UInt32(body.count).bigEndian
            frame.append(Data(bytes: &length, count: 4))
            frame.append(body)
            return frame
        }

        static func decode(_ data: Data) -> Message? {
            var src: String?, dst: String?, ns: String?, payload: String?
            var offset = 0

            while offset < data.count {
                guard let (tag, newOff) = decodeVarint(data, offset: offset) else { break }
                offset = newOff
                let wireType = Int(tag & 0x07)
                let fieldNum = Int(tag >> 3)

                switch wireType {
                case 0: // varint
                    guard let (_, nextOff) = decodeVarint(data, offset: offset) else { return nil }
                    offset = nextOff
                case 2: // length-delimited
                    guard let (len, nextOff) = decodeVarint(data, offset: offset) else { return nil }
                    offset = nextOff
                    let count = Int(len)
                    guard offset + count <= data.count else { return nil }
                    let bytes = data.subdata(in: offset..<(offset + count))
                    offset += count
                    let str = String(data: bytes, encoding: .utf8)
                    switch fieldNum {
                    case 2: src = str
                    case 3: dst = str
                    case 4: ns = str
                    case 6: payload = str
                    default: break
                    }
                case 1: offset += 8
                case 5: offset += 4
                default: return nil
                }
            }

            guard let s = src, let d = dst, let n = ns, let p = payload else { return nil }
            return Message(sourceId: s, destinationId: d, namespace: n, payloadUtf8: p)
        }
    }

    // MARK: Varint Helpers

    private static func encodeVarintBytes(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v > 0 { byte |= 0x80 }
            data.append(byte)
        } while v > 0
        return data
    }

    static func appendVarint(to data: inout Data, fieldNumber: Int, value: UInt64) {
        data.append(encodeVarintBytes(UInt64((fieldNumber << 3) | 0)))
        data.append(encodeVarintBytes(value))
    }

    static func appendString(to data: inout Data, fieldNumber: Int, value: String) {
        let utf8 = Data(value.utf8)
        data.append(encodeVarintBytes(UInt64((fieldNumber << 3) | 2)))
        data.append(encodeVarintBytes(UInt64(utf8.count)))
        data.append(utf8)
    }

    static func decodeVarint(_ data: Data, offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset
        while pos < data.count {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1
            if byte & 0x80 == 0 { return (result, pos) }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }
}

// MARK: - Cast Socket

/// TLS socket to Chromecast on port 8009.
actor CastDebugSocket {
    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private(set) var isConnected = false
    var onMessageReceived: (@Sendable (CastProto.Message) -> Void)?
    private var receiveTask: Task<Void, Never>?

    init(host: String, port: UInt16 = 8009) {
        self.host = host
        self.port = port
    }

    func connect() async throws {
        castPrint("SOCKET", "Connecting to \(host):\(port)...")

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, completionHandler in completionHandler(true) },
            DispatchQueue.global(qos: .userInitiated)
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions, .TLSv12
        )

        let params = NWParameters(tls: tlsOptions)
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params
        )
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            let resumeOnce: (Result<Void, Error>) -> Void = { result in
                guard !resumed else { return }
                resumed = true
                cont.resume(with: result)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce(.success(()))
                case .failed(let error):
                    resumeOnce(.failure(CastError.connectionFailed("TLS failed: \(error)")))
                case .cancelled:
                    resumeOnce(.failure(CastError.connectionFailed("Cancelled")))
                default:
                    break
                }
            }

            conn.start(queue: DispatchQueue.global(qos: .userInitiated))

            DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) {
                resumeOnce(.failure(CastError.connectionTimeout))
            }
        }

        isConnected = true
        castPrint("SOCKET", "Connected to \(host):\(port)")
        startReceiveLoop()
    }

    func send(_ message: CastProto.Message) async throws {
        guard let connection, isConnected else {
            throw CastError.transportError("Socket not connected")
        }
        let data = message.encodeFramed()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: CastError.transportError("Send failed: \(error)"))
                } else {
                    cont.resume()
                }
            })
        }
    }

    func disconnect() {
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        castPrint("SOCKET", "Disconnected")
    }

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                do {
                    let lengthData = try await self.readExact(count: 4)
                    let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    guard length > 0, length < 1_000_000 else {
                        castPrint("SOCKET", "ERROR: Invalid frame length: \(length)")
                        break
                    }

                    let payload = try await self.readExact(count: Int(length))
                    if let message = CastProto.Message.decode(payload) {
                        let callback = await self.onMessageReceived
                        callback?(message)
                    } else {
                        castPrint("SOCKET", "ERROR: Failed to decode protobuf (\(length) bytes)")
                    }
                } catch {
                    if !Task.isCancelled {
                        castPrint("SOCKET", "ERROR: Receive loop: \(error.localizedDescription)")
                    }
                    break
                }
            }
        }
    }

    private func readExact(count: Int) async throws -> Data {
        guard let connection else { throw CastError.transportError("Not connected") }
        var accumulated = Data()
        accumulated.reserveCapacity(count)

        while accumulated.count < count {
            let remaining = count - accumulated.count
            let chunk: Data = try await withCheckedThrowingContinuation { cont in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { content, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let content, !content.isEmpty {
                        cont.resume(returning: content)
                    } else if isComplete {
                        cont.resume(throwing: CastError.deviceDisconnected)
                    } else {
                        cont.resume(throwing: CastError.transportError("Empty read"))
                    }
                }
            }
            accumulated.append(chunk)
        }
        return accumulated
    }
}

// MARK: - Cast Channel (Protocol State Machine)

/// Cast V2 protocol orchestrator for the CLI debug tool.
actor CastDebugChannel {

    private static let senderId = "sender-0"
    private static let receiverId = "receiver-0"
    private static let defaultMediaReceiverAppId = "CC1AD845"

    private let socket: CastDebugSocket
    private(set) var sessionId: String?
    private(set) var transportId: String?
    private(set) var mediaSessionId: Int?
    private var nextRequestId: Int = 1
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var heartbeatTask: Task<Void, Never>?
    private var pongReceived = true

    init(socket: CastDebugSocket) {
        self.socket = socket
    }

    // MARK: - Connection Flow

    func connect() async throws {
        castPrint("CAST", "Starting handshake...")

        await socket.set(onMessageReceived: { [weak self] msg in
            Task { [weak self] in await self?.handleMessage(msg) }
        })

        // Step 1: CONNECT to receiver-0
        castPrint("CAST", "Step 1: CONNECT to \(Self.receiverId)")
        try await sendConnect(to: Self.receiverId)

        // Step 2: GET_STATUS
        castPrint("CAST", "Step 2: GET_STATUS")
        let status = try await sendRequest(
            namespace: NS.receiver,
            destination: Self.receiverId,
            payload: ["type": "GET_STATUS"]
        )

        // Log full receiver status
        if let jsonData = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            castPrint("CAST", "RECEIVER_STATUS:\n\(jsonStr)")
        }

        // Check for existing Default Media Receiver session (CC1AD845 only)
        if let session = extractSession(from: status, requiredAppId: Self.defaultMediaReceiverAppId) {
            castPrint("CAST", "Found EXISTING Default Media Receiver session: sid=\(session.0) tid=\(session.1)")
            self.sessionId = session.0
            self.transportId = session.1
            castPrint("CAST", "Step 3: CONNECT to transport \(session.1)")
            try await sendConnect(to: session.1)
            startHeartbeat()
            castPrint("CAST", "Handshake COMPLETE (reused session)")
            return
        }

        // Log if another app is running (e.g. YouTube) — we'll replace it with LAUNCH
        if let existingApp = extractAppInfo(from: status) {
            castPrint("CAST", "Another app running: \(existingApp.name) (appId=\(existingApp.appId)) — will replace with Default Media Receiver")
        }

        // Step 3: LAUNCH Default Media Receiver
        // NOTE: We fire LAUNCH and then poll GET_STATUS instead of waiting for broadcasts.
        // Some devices (e.g. TD SYSTEMS Android TV) send RECEIVER_STATUS broadcasts without
        // the `applications` array while the app is loading, so broadcast-based resolution fails.
        castPrint("CAST", "Step 3: LAUNCH \(Self.defaultMediaReceiverAppId)")
        try await sendRaw(
            namespace: NS.receiver,
            destination: Self.receiverId,
            payload: "{\"type\":\"LAUNCH\",\"appId\":\"\(Self.defaultMediaReceiverAppId)\",\"requestId\":\(nextRequestId)}"
        )
        nextRequestId += 1

        // Poll GET_STATUS until CC1AD845 appears (max ~30s with backoff)
        var session: (String, String)?
        let pollDelays: [UInt64] = [500, 1000, 1500, 2000, 2000, 3000, 3000, 3000, 5000, 5000]
        for (i, delayMs) in pollDelays.enumerated() {
            try await Task.sleep(for: .milliseconds(delayMs))
            castPrint("CAST", "LAUNCH poll \(i+1)/\(pollDelays.count): GET_STATUS...")
            let pollStatus = try await sendRequest(
                namespace: NS.receiver,
                destination: Self.receiverId,
                payload: ["type": "GET_STATUS"]
            )
            if let s = extractSession(from: pollStatus, requiredAppId: Self.defaultMediaReceiverAppId) {
                session = s
                break
            }
            // Log what apps are running (if any)
            if let app = extractAppInfo(from: pollStatus) {
                castPrint("CAST", "LAUNCH poll \(i+1): running app=\(app.name) (\(app.appId)) — waiting for CC1AD845...")
            } else {
                castPrint("CAST", "LAUNCH poll \(i+1): no apps yet — device still loading...")
            }
        }

        guard let session else {
            throw CastError.connectionFailed("LAUNCH timeout: CC1AD845 never appeared after \(pollDelays.count) polls")
        }

        self.sessionId = session.0
        self.transportId = session.1
        castPrint("CAST", "Session acquired: sid=\(session.0) tid=\(session.1)")

        // Step 4: CONNECT to transport
        castPrint("CAST", "Step 4: CONNECT to transport \(session.1)")
        try await sendConnect(to: session.1)

        // Step 5: Heartbeat
        startHeartbeat()
        castPrint("CAST", "Handshake COMPLETE")
    }

    func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let tid = transportId {
            try? await sendRaw(namespace: NS.connection, destination: tid, payload: "{\"type\":\"CLOSE\"}")
        }
        try? await sendRaw(namespace: NS.connection, destination: Self.receiverId, payload: "{\"type\":\"CLOSE\"}")

        for (id, cont) in pendingRequests {
            castPrint("CAST", "Cancelling pending request \(id)")
            cont.resume(throwing: CastError.deviceDisconnected)
        }
        pendingRequests.removeAll()
        await socket.disconnect()
    }

    // MARK: - Media Commands

    func loadMedia(url: URL, contentType: String, title: String, startTime: Double = 0) async throws {
        guard let tid = transportId, let sid = sessionId else {
            throw CastError.transportError("No active session")
        }

        var media: [String: Any] = [
            "contentId": url.absoluteString,
            "contentType": contentType,
            "streamType": "BUFFERED",
            "metadata": [
                "metadataType": 0,
                "title": title
            ] as [String: Any]
        ]

        // NOTE: fMP4 segment format hints REMOVED - some Cast devices reject them.
        // Shaka Player should auto-detect fMP4 from the #EXT-X-MAP tag in the HLS manifest.
        // Previously we sent hlsSegmentFormat="fmp4" and hlsVideoSegmentFormat="fmp4" but
        // this caused immediate LOAD_FAILED on some devices (LEAP-S1, TELEFUNKEN).
        // The Default Media Receiver (CC1AD845) uses Shaka Player which supports fMP4 HLS natively.

        let payload: [String: Any] = [
            "type": "LOAD",
            "sessionId": sid,
            "media": media,
            "autoplay": true,
            "currentTime": startTime,
            "customData": [String: Any]()
        ]

        castPrint("CAST", "LOAD: url=\(url.absoluteString) type=\(contentType) start=\(String(format: "%.1f", startTime))s")

        // Log full LOAD payload
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            castPrint("CAST", "LOAD payload:\n\(jsonStr)")
        }

        let response = try await sendRequest(
            namespace: NS.media,
            destination: tid,
            payload: payload
        )

        // Log full response
        if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            castPrint("CAST", "LOAD response:\n\(jsonStr)")
        }

        // Extract mediaSessionId
        if let statusArray = response["status"] as? [[String: Any]],
           let first = statusArray.first,
           let msId = first["mediaSessionId"] as? Int {
            self.mediaSessionId = msId
            castPrint("CAST", "mediaSessionId = \(msId)")
        }

        // Check for error
        if let type = response["type"] as? String, type == "LOAD_FAILED" {
            let code = response["detailedErrorCode"] as? Int ?? -1
            // Try to get more error details from the status array
            var errorDetails = ""
            if let statusArray = response["status"] as? [[String: Any]],
               let first = statusArray.first {
                if let idleReason = first["idleReason"] as? String {
                    errorDetails += " idleReason=\(idleReason)"
                }
                if let extendedStatus = first["extendedStatus"] as? [String: Any] {
                    if let code = extendedStatus["code"] as? Int {
                        errorDetails += " extCode=\(code)"
                    }
                    if let reason = extendedStatus["reason"] as? String {
                        errorDetails += " extReason=\(reason)"
                    }
                }
                if let media = first["media"] as? [String: Any] {
                    if let contentId = media["contentId"] as? String {
                        errorDetails += " contentId=\(contentId)"
                    }
                }
            }
            castPrint("CAST", "ERROR: LOAD_FAILED code=\(code)\(errorDetails)")
            throw CastError.transportError("LOAD_FAILED: errorCode=\(code)\(errorDetails)")
        }
    }

    func play() async throws {
        try await sendMediaCommand("PLAY")
    }

    func pause() async throws {
        try await sendMediaCommand("PAUSE")
    }

    func stop() async throws {
        try await sendMediaCommand("STOP")
    }

    func seek(to time: Double) async throws {
        guard let tid = transportId, let sid = sessionId, let msId = mediaSessionId else {
            throw CastError.transportError("No media session")
        }
        let payload: [String: Any] = [
            "type": "SEEK",
            "mediaSessionId": msId,
            "currentTime": time,
            "resumeState": "PLAYBACK_START",
            "sessionId": sid
        ]
        _ = try await sendRequest(namespace: NS.media, destination: tid, payload: payload)
        castPrint("CAST", "SEEK to \(String(format: "%.1f", time))s OK")
    }

    func getMediaStatus() async throws {
        guard let tid = transportId else { return }
        let response = try await sendRequest(
            namespace: NS.media,
            destination: tid,
            payload: ["type": "GET_STATUS"]
        )
        if let jsonData = try? JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            castPrint("CAST", "MEDIA_STATUS:\n\(jsonStr)")
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: CastProto.Message) {
        let ns = message.namespace.replacingOccurrences(of: "urn:x-cast:", with: "")
        let json = parseJSON(message.payloadUtf8)
        let type = json?["type"] as? String ?? "?"
        let reqId = json?["requestId"] as? Int

        // Log EVERY incoming message with full payload
        castPrint("RECV", "[\(ns)] type=\(type) src=\(message.sourceId) dst=\(message.destinationId) reqId=\(reqId.map(String.init) ?? "none")")
        if let json = json,
           let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            // Only print full payload for non-heartbeat messages
            if type != "PING" && type != "PONG" {
                castPrint("RECV", "  payload:\n\(jsonStr)")
            }
        }

        // Route by namespace
        switch message.namespace {
        case NS.heartbeat:
            if type == "PING" {
                Task {
                    try? await sendRaw(namespace: NS.heartbeat, destination: message.sourceId, payload: "{\"type\":\"PONG\"}")
                }
            } else if type == "PONG" {
                pongReceived = true
            }

        case NS.receiver:
            // First, handle normal request/response with matching requestId
            if let reqId = reqId, reqId > 0, let cont = pendingRequests.removeValue(forKey: reqId) {
                castPrint("CAST", "Request \(reqId) resolved (type=\(type))")
                cont.resume(returning: json ?? [:])
                return
            }

            // LAUNCH_STATUS is informational — LAUNCH resolution is handled by polling in connect()
            if type == "LAUNCH_STATUS" {
                let status = json?["status"] as? String ?? "?"
                castPrint("CAST", "LAUNCH_STATUS: \(status)")
                return
            }

            // RECEIVER_STATUS broadcasts are informational (logged above via normal flow)
            // LAUNCH resolution is handled by GET_STATUS polling in connect(), not broadcasts

        case NS.media:
            if let reqId = reqId, let cont = pendingRequests.removeValue(forKey: reqId) {
                castPrint("CAST", "Request \(reqId) resolved (type=\(type))")
                cont.resume(returning: json ?? [:])
            } else if type == "MEDIA_STATUS" {
                // Unsolicited status update
                if let statusArr = json?["status"] as? [[String: Any]],
                   let st = statusArr.first {
                    let state = st["playerState"] as? String ?? "?"
                    let time = st["currentTime"] as? Double ?? 0
                    let msId = st["mediaSessionId"] as? Int
                    if let msId { self.mediaSessionId = msId }

                    // Log error details if player is IDLE with error
                    var errorInfo = ""
                    if state == "IDLE", let idleReason = st["idleReason"] as? String {
                        errorInfo += " idleReason=\(idleReason)"
                        if let extendedStatus = st["extendedStatus"] as? [String: Any] {
                            if let code = extendedStatus["code"] as? Int {
                                errorInfo += " extCode=\(code)"
                            }
                            if let reason = extendedStatus["reason"] as? String {
                                errorInfo += " extReason=\(reason)"
                            }
                        }
                    }

                    castPrint("CAST", "Media: state=\(state) time=\(String(format: "%.1f", time))s msId=\(msId.map(String.init) ?? "?")\(errorInfo)")
                }
            }

        case NS.connection:
            if type == "CLOSE" {
                castPrint("CAST", "Device sent CLOSE from \(message.sourceId)")
            }

        default:
            castPrint("CAST", "Unknown namespace: \(message.namespace)")
        }
    }

    // MARK: - Sending

    private func sendConnect(to destination: String) async throws {
        try await sendRaw(
            namespace: NS.connection,
            destination: destination,
            payload: "{\"type\":\"CONNECT\",\"origin\":{}}"
        )
    }

    private func sendRaw(namespace: String, destination: String, payload: String) async throws {
        let ns = namespace.replacingOccurrences(of: "urn:x-cast:", with: "")
        castPrint("SEND", "[\(ns)] -> \(destination) (\(payload.prefix(100))...)")
        let msg = CastProto.Message(
            sourceId: Self.senderId,
            destinationId: destination,
            namespace: namespace,
            payloadUtf8: payload
        )
        try await socket.send(msg)
    }

    @discardableResult
    private func sendRequest(
        namespace: String,
        destination: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        let requestId = nextRequestId
        nextRequestId += 1

        var full = payload
        full["requestId"] = requestId

        guard let data = try? JSONSerialization.data(withJSONObject: full, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else {
            throw CastError.transportError("Failed to serialize JSON")
        }

        let type = payload["type"] as? String ?? "?"
        castPrint("CAST", "Sending request \(requestId) type=\(type)")

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            pendingRequests[requestId] = cont

            Task { [weak self] in
                do {
                    try await self?.sendRaw(namespace: namespace, destination: destination, payload: jsonStr)
                } catch {
                    if let c = await self?.removePending(requestId) {
                        c.resume(throwing: error)
                    }
                }
            }

            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                if let c = await self?.removePending(requestId) {
                    castPrint("CAST", "ERROR: Request \(requestId) TIMED OUT (type=\(type))")
                    c.resume(throwing: CastError.connectionTimeout)
                }
            }
        }
    }

    private func removePending(_ id: Int) -> CheckedContinuation<[String: Any], Error>? {
        pendingRequests.removeValue(forKey: id)
    }

    private func sendMediaCommand(_ type: String) async throws {
        guard let tid = transportId, let sid = sessionId, let msId = mediaSessionId else {
            throw CastError.transportError("No media session for \(type)")
        }
        let payload: [String: Any] = [
            "type": type,
            "mediaSessionId": msId,
            "sessionId": sid
        ]
        _ = try await sendRequest(namespace: NS.media, destination: tid, payload: payload)
        castPrint("CAST", "\(type) OK")
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        pongReceived = true
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                let gotPong = await self.pongReceived
                if !gotPong {
                    castPrint("CAST", "ERROR: Heartbeat timeout (no PONG)")
                    break
                }
                await self.setPongReceived(false)
                try? await self.sendRaw(
                    namespace: NS.heartbeat,
                    destination: CastDebugChannel.receiverId,
                    payload: "{\"type\":\"PING\"}"
                )
            }
        }
    }

    private func setPongReceived(_ v: Bool) { pongReceived = v }

    // MARK: - Parsing

    private func parseJSON(_ str: String) -> [String: Any]? {
        guard let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private func extractSession(from response: [String: Any], requiredAppId: String? = nil) -> (String, String)? {
        guard let status = response["status"] as? [String: Any],
              let apps = status["applications"] as? [[String: Any]],
              let app = apps.first,
              let sid = app["sessionId"] as? String,
              let tid = app["transportId"] as? String else { return nil }
        if let required = requiredAppId {
            guard let appId = app["appId"] as? String, appId == required else { return nil }
        }
        return (sid, tid)
    }

    private func extractAppInfo(from response: [String: Any]) -> (name: String, appId: String)? {
        guard let status = response["status"] as? [String: Any],
              let apps = status["applications"] as? [[String: Any]],
              let app = apps.first,
              let appId = app["appId"] as? String else { return nil }
        let name = app["displayName"] as? String ?? "Unknown"
        return (name, appId)
    }

    // MARK: - Namespace Constants

    private enum NS {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat  = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver   = "urn:x-cast:com.google.cast.receiver"
        static let media      = "urn:x-cast:com.google.cast.media"
    }
}

// MARK: - Socket Extension

extension CastDebugSocket {
    func set(onMessageReceived callback: (@Sendable (CastProto.Message) -> Void)?) {
        self.onMessageReceived = callback
    }
}

// MARK: - LAN IP Detection

func getLANIPAddress() -> String? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    var bestIP: String?
    var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let addr = current {
        defer { current = addr.pointee.ifa_next }
        guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
        let name = String(cString: addr.pointee.ifa_name)
        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(
            addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST
        )
        let ip = String(cString: hostname)
        if name == "en0" { return ip }
        if name.hasPrefix("en") && bestIP == nil { bestIP = ip }
    }
    return bestIP
}

// MARK: - MIME type

func castContentType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "mp4", "m4v": return "video/mp4"
    case "mkv": return "video/x-matroska"
    case "webm": return "video/webm"
    case "avi": return "video/x-msvideo"
    case "ts": return "video/mp2t"
    case "m3u8": return "application/x-mpegURL"
    case "mov": return "video/quicktime"
    default: return "video/mp4"
    }
}

// MARK: - SSDP Discovery

/// Discovered Cast device from SSDP scan.
struct CastDevice: Sendable {
    let name: String
    let ip: String
    let port: UInt16
    let model: String
}

/// Discovers Chromecast/Google TV devices on the LAN via SSDP multicast.
/// Uses POSIX BSD sockets (sendto/recvfrom) because NWConnection filters responses
/// by remote address and silently drops SSDP unicast replies from arbitrary IPs.
///
/// Returns an array of discovered devices after scanning for `timeout` seconds.
func discoverCastDevices(timeout: Int = 5) -> [CastDevice] {
    let multicastAddr = "239.255.255.250"
    let ssdpPort: UInt16 = 1900
    let searchTarget = "urn:dial-multiscreen-org:service:dial:1"

    // Create UDP socket
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else {
        castPrint("SSDP", "ERROR: Failed to create socket: \(String(cString: strerror(errno)))")
        return []
    }
    defer { close(fd) }

    // Set receive timeout
    var recvTimeout = timeval(tv_sec: timeout, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))

    // Allow address reuse
    var reuseAddr: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

    // Build multicast destination
    var destAddr = sockaddr_in()
    destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    destAddr.sin_family = sa_family_t(AF_INET)
    destAddr.sin_port = ssdpPort.bigEndian
    inet_pton(AF_INET, multicastAddr, &destAddr.sin_addr)

    // Build M-SEARCH message
    let message = "M-SEARCH * HTTP/1.1\r\nHOST: \(multicastAddr):\(ssdpPort)\r\nMAN: \"ssdp:discover\"\r\nMX: 3\r\nST: \(searchTarget)\r\nUSER-AGENT: TransmuxCLI/1.0 UPnP/1.1\r\n\r\n"

    // Send M-SEARCH
    message.withCString { ptr in
        withUnsafePointer(to: &destAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                let sent = sendto(fd, ptr, strlen(ptr), 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                if sent < 0 {
                    castPrint("SSDP", "ERROR: sendto failed: \(String(cString: strerror(errno)))")
                }
            }
        }
    }

    castPrint("SSDP", "Sent M-SEARCH for \(searchTarget), waiting \(timeout)s for responses...")

    // Collect LOCATION URLs from responses
    var locations = Set<String>()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
        var senderAddr = sockaddr_in()
        var senderAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buffer, buffer.count, 0, sa, &senderAddrLen)
            }
        }

        if bytesRead <= 0 { break } // timeout or error

        let data = Data(bytes: buffer, count: bytesRead)
        guard let response = String(data: data, encoding: .utf8) else { continue }

        // Parse headers to get LOCATION
        let lines = response.components(separatedBy: "\r\n")
        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("LOCATION:") {
                let value = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty {
                    locations.insert(value)
                    castPrint("SSDP", "Found device at: \(value)")
                }
            }
        }
    }

    if locations.isEmpty {
        castPrint("SSDP", "No devices found")
        return []
    }

    // Fetch device descriptions from LOCATION URLs
    castPrint("SSDP", "Fetching device descriptions for \(locations.count) device(s)...")
    var devices: [CastDevice] = []
    var seenIPs = Set<String>()

    for location in locations {
        guard let url = URL(string: location),
              let host = url.host else { continue }

        // Skip duplicates (same IP)
        if seenIPs.contains(host) { continue }
        seenIPs.insert(host)

        // Fetch the device description XML synchronously
        let semaphore = DispatchSemaphore(value: 0)
        var xmlData: Data?

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data,
               let httpResp = response as? HTTPURLResponse,
               httpResp.statusCode == 200 {
                xmlData = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        guard let xml = xmlData,
              let xmlStr = String(data: xml, encoding: .utf8) else {
            // Couldn't fetch description, add with IP only
            devices.append(CastDevice(name: host, ip: host, port: 8009, model: "Unknown"))
            continue
        }

        // Parse friendlyName and modelName from XML
        let name = parseXMLTag(xmlStr, tag: "friendlyName") ?? host
        let model = parseXMLTag(xmlStr, tag: "modelName") ?? "Unknown"

        devices.append(CastDevice(name: name, ip: host, port: 8009, model: model))
        castPrint("SSDP", "  \(name) (\(model)) at \(host):8009")
    }

    return devices
}

/// Simple XML tag value extractor (no full XML parsing needed for device descriptions).
private func parseXMLTag(_ xml: String, tag: String) -> String? {
    let openTag = "<\(tag)>"
    let closeTag = "</\(tag)>"
    guard let openRange = xml.range(of: openTag),
          let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex) else {
        return nil
    }
    return String(xml[openRange.upperBound..<closeRange.lowerBound])
}

// MARK: - Logging

func castPrint(_ category: String, _ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] [\(category)] \(message)")
    fflush(stdout)
}

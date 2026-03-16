//
//  CastController.swift
//  mks-multiplatform-iptv
//
//  Controls playback on a Google Cast device (Chromecast, Google TV)
//  via the Cast V2 protocol over TLS on port 8009.
//  Implements RemoteDeviceController for integration with RemotePlayManager.
//

import Foundation

/// Controls playback on a Google Cast device via the Cast V2 protocol.
/// Implements the same `RemoteDeviceController` interface as `DLNAController`.
///
/// ## Connection Flow
/// 1. Extract host IP from device `metadata["baseURL"]`
/// 2. Create TLS socket on port 8009 via `CastSocket`
/// 3. Run Cast V2 handshake via `CastChannel` (CONNECT -> LAUNCH -> session)
/// 4. Media commands (LOAD, PLAY, PAUSE, SEEK, STOP, SET_VOLUME)
/// 5. Poll media status every 2 seconds for state sync
///
final class CastController: RemoteDeviceController, @unchecked Sendable {

    // MARK: - Properties

    let device: RemoteDevice
    private(set) var playbackState: RemotePlaybackState = .idle
    private(set) var deviceState: RemoteDeviceState = .idle

    /// Host IP extracted from device metadata.
    private let hostIP: String

    /// Cast V2 port (always 8009).
    private let castPort: UInt16 = 8009

    /// TLS socket connection.
    private var socket: CastSocket?

    /// Cast V2 protocol channel.
    private var channel: CastChannel?

    /// Polling task for position/state updates.
    private var pollingTask: Task<Void, Never>?

    /// Polling interval in seconds.
    private let pollingInterval: TimeInterval = 2.0

    /// Callback for state updates (connected by RemotePlayManager).
    var onStateUpdate: ((RemoteDeviceState) -> Void)?

    // MARK: - Initialization

    init(device: RemoteDevice) throws {
        self.device = device

        guard device.type == .chromecast || device.type == .googleTV else {
            throw RemotePlayError.connectionFailed("Device is not a Cast device")
        }

        // Extract host IP from baseURL metadata
        if let baseURLString = device.metadata["baseURL"],
           let baseURL = URL(string: baseURLString),
           let host = baseURL.host {
            self.hostIP = host
        } else {
            throw RemotePlayError.connectionFailed("No baseURL in Cast device metadata")
        }

        CastLog.controllerAction("INIT", fields: [
            "device": device.name,
            "type": device.type.rawValue,
            "host": hostIP
        ])
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - RemoteDeviceController

    func connect() async throws {
        CastLog.startSession(host: hostIP, port: castPort)
        CastLog.controllerAction("CONNECT_START", fields: ["device": device.name, "host": hostIP])
        playbackState = .connecting(deviceId: device.id)

        do {
            // Create TLS socket
            let sock = CastSocket(host: hostIP, port: castPort)
            self.socket = sock

            // Connect TLS
            try await sock.connect()

            // Create protocol channel
            let chan = CastChannel(socket: sock)
            self.channel = chan

            // Setup state change callback
            await chan.set(onStateChanged: { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .error(let msg) = state {
                        CastLog.error("STATE_ERROR", error: msg)
                        self.playbackState = .error(RemotePlayError.transportError(msg))
                    } else if case .disconnected = state {
                        CastLog.controllerAction("DEVICE_DISCONNECTED")
                        self.playbackState = .idle
                        self.deviceState = .idle
                    }
                }
            })

            // Setup media status callback
            await chan.set(onMediaStatusUpdate: { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateFromMediaStatus(status)
                }
            })

            // Run Cast V2 handshake
            try await chan.connect()

            playbackState = .connected(deviceId: device.id)
            deviceState = .idle
            CastLog.controllerAction("CONNECT_SUCCESS", fields: ["device": device.name])

        } catch {
            CastLog.error("CONNECT_FAILED", error: error.localizedDescription)
            playbackState = .error((error as? RemotePlayError) ?? .connectionFailed(error.localizedDescription))
            throw error
        }
    }

    func disconnect() async {
        CastLog.controllerAction("DISCONNECT")
        stopPolling()

        if let channel {
            await channel.disconnect()
        }

        socket = nil
        channel = nil
        playbackState = .idle
        deviceState = .idle
        CastLog.endSession()
    }

    // MARK: - Content Loading

    func load(url: URL, metadata: MetadataResult?, startPosition: Double, streaming: Bool = false) async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        CastLog.controllerAction("LOAD", fields: [
            "url": url.absoluteString,
            "startPos": String(format: "%.1f", startPosition)
        ])
        playbackState = .loading

        // Force HLS contentType for m3u8 URLs (TransmuxServer serves fMP4 HLS).
        // CastMetadataAdapter.contentType already handles .m3u8 → application/x-mpegURL,
        // but we explicitly ensure it here for URLs coming from the TransmuxServer pipeline.
        let contentType: String
        if url.pathExtension.lowercased() == "m3u8" {
            contentType = "application/x-mpegURL"
        } else {
            contentType = CastMetadataAdapter.contentType(for: url)
        }

        let durationSeconds: Double? = metadata?.runtimeMinutes.map { Double($0) * 60.0 }
        let castMetadata = CastMetadataAdapter.buildCastLoadPayload(
            from: metadata,
            contentURL: url,
            duration: durationSeconds
        )

        CastLog.controllerAction("LOAD_METADATA", fields: [
            "contentType": contentType,
            "title": metadata?.title ?? "untitled",
            "duration": durationSeconds.map { String(format: "%.0f", $0) } ?? "unknown"
        ])

        do {
            try await channel.loadMedia(
                contentURL: url,
                contentType: contentType,
                metadata: castMetadata,
                autoplay: true,
                currentTime: startPosition
            )

            playbackState = .playing
            deviceState.transportState = .playing
            CastLog.controllerAction("LOAD_SUCCESS")

            // Start polling for state updates
            startPolling()

        } catch {
            CastLog.error("LOAD_FAILED", error: error.localizedDescription)
            playbackState = .error((error as? RemotePlayError) ?? .transportError(error.localizedDescription))
            throw error
        }
    }

    func play() async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        try await channel.play()
        playbackState = .playing
        deviceState.transportState = .playing
    }

    func pause() async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        try await channel.pause()
        playbackState = .paused
        deviceState.transportState = .paused
    }

    func seek(to time: Double) async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        playbackState = .seeking(to: time)

        try await channel.seek(to: time)
        deviceState.currentTime = time

        // Restore previous playback state after seek
        if deviceState.transportState == .playing {
            playbackState = .playing
        } else {
            playbackState = .paused
        }
    }

    func stop() async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        CastLog.controllerAction("STOP")
        stopPolling()
        try await channel.stop()
        playbackState = .stopped
        deviceState = .idle
    }

    // MARK: - Volume Control

    func setVolume(_ volume: Float) async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        let clamped = min(max(volume, 0.0), 1.0)
        try await channel.setVolume(level: clamped)
        deviceState.volume = clamped
    }

    func setMuted(_ muted: Bool) async throws {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        try await channel.setVolume(muted: muted)
        deviceState.isMuted = muted
    }

    // MARK: - State Query

    func queryPosition() async throws -> (currentTime: Double, duration: Double, isPlaying: Bool) {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        if let status = try await channel.getMediaStatus() {
            updateFromMediaStatus(status)
            return (status.currentTime, status.duration, status.playerState == "PLAYING")
        }

        return (deviceState.currentTime, deviceState.duration, deviceState.isPlaying)
    }

    func queryVolume() async throws -> (volume: Float, isMuted: Bool) {
        guard let channel else {
            throw RemotePlayError.transportError("Cast: not connected")
        }

        let receiverStatus = try await channel.getReceiverStatus()

        // Parse volume from receiver status
        if let status = receiverStatus["status"] as? [String: Any],
           let volume = status["volume"] as? [String: Any] {
            let level = Float(volume["level"] as? Double ?? 1.0)
            let muted = volume["muted"] as? Bool ?? false
            deviceState.volume = level
            deviceState.isMuted = muted
            return (level, muted)
        }

        return (deviceState.volume, deviceState.isMuted)
    }

    // MARK: - Private Helpers

    /// Map Cast playerState to RemoteDeviceState.TransportState and update local state.
    private func updateFromMediaStatus(_ status: CastMediaStatus) {
        deviceState.currentTime = status.currentTime
        deviceState.duration = status.duration
        deviceState.volume = status.volume
        deviceState.isMuted = status.isMuted

        switch status.playerState {
        case "PLAYING":
            deviceState.transportState = .playing
            playbackState = .playing
        case "PAUSED":
            deviceState.transportState = .paused
            playbackState = .paused
        case "BUFFERING":
            deviceState.transportState = .transitioning
            playbackState = .buffering
        case "IDLE":
            deviceState.transportState = .stopped
        default:
            deviceState.transportState = .unknown
        }

        onStateUpdate?(deviceState)
    }

    // MARK: - Polling

    /// Start polling for position/state updates every 2 seconds.
    private func startPolling() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let _ = try await self?.queryPosition()
                } catch {
                    // Polling error — device may have disconnected
                    if !Task.isCancelled {
                        CastLog.log("POLL_ERROR", category: "controller", level: "WRN", fields: [
                            "error": error.localizedDescription
                        ])
                    }
                }

                try? await Task.sleep(for: .seconds(self?.pollingInterval ?? 2.0))
            }
        }
    }

    /// Stop polling.
    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

// MARK: - Cast Session State

/// Represents the state of a Cast session.
enum CastSessionState: Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
}

// MARK: - CastChannel Callback Setters

extension CastChannel {
    /// Set the state changed callback.
    func set(onStateChanged callback: (@Sendable (CastSessionState) -> Void)?) {
        self.onStateChanged = callback
    }

    /// Set the media status update callback.
    func set(onMediaStatusUpdate callback: (@Sendable (CastMediaStatus) -> Void)?) {
        self.onMediaStatusUpdate = callback
    }
}

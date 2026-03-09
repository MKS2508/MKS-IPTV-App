//
//  DLNAController.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - AVTransport SOAP control for DLNA devices
//

import Foundation

/// Controls playback on a DLNA MediaRenderer via AVTransport:1 SOAP actions.
/// Implements RemoteDeviceController protocol for integration with RemotePlayManager.
///
/// ## Features
/// - SetAVTransportURI: Load content with DIDL-Lite metadata
/// - Play/Pause/Stop/Seek: Transport controls
/// - Volume/Mute: RenderingControl integration
/// - Position polling: GetPositionInfo for state sync
///
final class DLNAController: RemoteDeviceController, @unchecked Sendable {

    // MARK: - Properties

    let device: RemoteDevice
    private(set) var playbackState: RemotePlaybackState = .idle
    private(set) var deviceState: RemoteDeviceState = .idle

    /// AVTransport control URL (required).
    private let controlURL: URL

    /// RenderingControl URL (optional, for volume).
    private let renderingControlURL: URL?

    /// Instance ID for AVTransport (always 0 for single-zone).
    private let instanceId: Int = 0

    /// Default channel for RenderingControl.
    private let defaultChannel = "Master"

    /// Polling task for position updates.
    private var pollingTask: Task<Void, Never>?

    /// Polling interval in seconds.
    private let pollingInterval: TimeInterval = 2.0

    /// Callback for state updates (connected by RemotePlayManager).
    var onStateUpdate: ((RemoteDeviceState) -> Void)?

    // MARK: - Initialization

    init(device: RemoteDevice) throws {
        self.device = device

        // Extract control URL from device metadata
        guard let controlURLString = device.metadata["controlURL"],
              let controlURL = URL(string: controlURLString) else {
            throw RemotePlayError.connectionFailed("No AVTransport controlURL in device metadata")
        }

        self.controlURL = controlURL

        // RenderingControl URL is optional
        self.renderingControlURL = device.metadata["renderingControlURL"].flatMap { URL(string: $0) }
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - RemoteDeviceController

    func connect() async throws {
        // DLNA is connectionless - verify device is reachable by querying state
        playbackState = .connected(deviceId: device.id)

        // Query initial state
        do {
            _ = try await queryPosition()
            // Device is responsive
        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func disconnect() async {
        stopPolling()

        // Stop any playing content
        try? await stop()

        playbackState = .idle
    }

    // MARK: - Content Loading

    func load(url: URL, metadata: MetadataResult?, startPosition: Double) async throws {
        playbackState = .loading

        // Build DIDL-Lite metadata - convert runtimeMinutes to seconds
        let durationSeconds: Double? = metadata?.runtimeMinutes.map { Double($0) * 60.0 }
        let didlMetadata = DLNAMetadataAdapter.buildDIDLLite(
            from: metadata,
            contentURL: url,
            duration: durationSeconds
        )

        do {
            // SetAVTransportURI
            let setURIAction = DLNASOAPClient.AVTransportAction.setAVTransportURI(
                instanceId: instanceId,
                uri: url.absoluteString,
                metadata: didlMetadata
            )
            _ = try await DLNASOAPClient.send(
                action: setURIAction.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: setURIAction.arguments
            )

            // Seek to start position if > 0
            if startPosition > 0 {
                try await seek(to: startPosition)
            }

            // Start playback
            try await play()

            // Start polling for state updates
            startPolling()

        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func play() async throws {
        do {
            let action = DLNASOAPClient.AVTransportAction.play(
                instanceId: instanceId,
                speed: "1"
            )
            _ = try await DLNASOAPClient.send(
                action: action.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: action.arguments
            )

            playbackState = .playing
            deviceState.transportState = .playing

        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func pause() async throws {
        do {
            let action = DLNASOAPClient.AVTransportAction.pause(
                instanceId: instanceId
            )
            _ = try await DLNASOAPClient.send(
                action: action.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: action.arguments
            )

            playbackState = .paused
            deviceState.transportState = .paused

        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func seek(to time: Double) async throws {
        let target = formatSeekTarget(time)

        playbackState = .seeking(to: time)

        do {
            let action = DLNASOAPClient.AVTransportAction.seek(
                instanceId: instanceId,
                unit: "REL_TIME",
                target: target
            )
            _ = try await DLNASOAPClient.send(
                action: action.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: action.arguments
            )

            deviceState.currentTime = time

            // Restore previous state after seeking
            if deviceState.transportState == .playing {
                playbackState = .playing
            } else {
                playbackState = .paused
            }

        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func stop() async throws {
        do {
            let action = DLNASOAPClient.AVTransportAction.stop(
                instanceId: instanceId
            )
            _ = try await DLNASOAPClient.send(
                action: action.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: action.arguments
            )

            playbackState = .stopped
            deviceState = .idle

        } catch let error as RemotePlayError {
            playbackState = .error(error)
            throw error
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    // MARK: - Volume Control

    func setVolume(_ volume: Float) async throws {
        guard let renderingControlURL else {
            throw RemotePlayError.transportError("No RenderingControl URL available")
        }

        let volumeInt = Int((volume * 100).clamped(to: 0...100))

        let action = DLNASOAPClient.RenderingControlAction.setVolume(
            instanceId: instanceId,
            channel: defaultChannel,
            volume: volumeInt
        )
        _ = try await DLNASOAPClient.send(
            action: action.actionName,
            serviceType: .renderingControl,
            controlURL: renderingControlURL,
            arguments: action.arguments
        )

        deviceState.volume = volume
    }

    func setMuted(_ muted: Bool) async throws {
        guard let renderingControlURL else {
            throw RemotePlayError.transportError("No RenderingControl URL available")
        }

        let action = DLNASOAPClient.RenderingControlAction.setMute(
            instanceId: instanceId,
            channel: defaultChannel,
            mute: muted
        )
        _ = try await DLNASOAPClient.send(
            action: action.actionName,
            serviceType: .renderingControl,
            controlURL: renderingControlURL,
            arguments: action.arguments
        )

        deviceState.isMuted = muted
    }

    // MARK: - State Query

    func queryPosition() async throws -> (currentTime: Double, duration: Double, isPlaying: Bool) {
        let posAction = DLNASOAPClient.AVTransportAction.getPositionInfo(
            instanceId: instanceId
        )
        let response = try await DLNASOAPClient.send(
            action: posAction.actionName,
            serviceType: .avTransport,
            controlURL: controlURL,
            arguments: posAction.arguments
        )

        let currentTime = parseTime(response["RelTime"] ?? "00:00:00")
        let duration = parseTime(response["TrackDuration"] ?? "00:00:00")

        // Query transport state for isPlaying
        let transportState = try await queryTransportInfo()
        let isPlaying = transportState == .playing

        deviceState.currentTime = currentTime
        deviceState.duration = duration
        deviceState.transportState = transportState

        return (currentTime, duration, isPlaying)
    }

    func queryVolume() async throws -> (volume: Float, isMuted: Bool) {
        guard let renderingControlURL else {
            throw RemotePlayError.transportError("No RenderingControl URL available")
        }

        // Query volume
        let volAction = DLNASOAPClient.RenderingControlAction.getVolume(
            instanceId: instanceId,
            channel: defaultChannel
        )
        let volumeResponse = try await DLNASOAPClient.send(
            action: volAction.actionName,
            serviceType: .renderingControl,
            controlURL: renderingControlURL,
            arguments: volAction.arguments
        )

        let volumeValue = Float(volumeResponse["CurrentVolume"] ?? "100") ?? 100.0
        let volume = volumeValue / 100.0

        // Query mute state
        let muteAction = DLNASOAPClient.RenderingControlAction.getMute(
            instanceId: instanceId,
            channel: defaultChannel
        )
        let muteResponse = try await DLNASOAPClient.send(
            action: muteAction.actionName,
            serviceType: .renderingControl,
            controlURL: renderingControlURL,
            arguments: muteAction.arguments
        )

        let isMuted = (muteResponse["CurrentMute"] ?? "0") == "1"

        deviceState.volume = volume
        deviceState.isMuted = isMuted

        return (volume, isMuted)
    }

    // MARK: - Private Helpers

    /// Query transport info for current state.
    private func queryTransportInfo() async throws -> RemoteDeviceState.TransportState {
        let action = DLNASOAPClient.AVTransportAction.getTransportInfo(
            instanceId: instanceId
        )
        let response = try await DLNASOAPClient.send(
            action: action.actionName,
            serviceType: .avTransport,
            controlURL: controlURL,
            arguments: action.arguments
        )

        let stateString = response["CurrentTransportState"] ?? "STOPPED"
        return RemoteDeviceState.TransportState(rawValue: stateString) ?? .stopped
    }

    /// Format seek target as HH:MM:SS.
    private func formatSeekTarget(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Parse HH:MM:SS time string to seconds.
    private func parseTime(_ timeString: String) -> Double {
        let components = timeString.split(separator: ":")
        guard components.count == 3 else { return 0 }

        let hours = Double(components[0]) ?? 0
        let minutes = Double(components[1]) ?? 0
        let seconds = Double(components[2]) ?? 0

        return hours * 3600 + minutes * 60 + seconds
    }

    // MARK: - Polling

    /// Start polling for position updates.
    private func startPolling() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let _ = try await self?.queryPosition()
                    if let state = self?.deviceState {
                        self?.onStateUpdate?(state)
                    }
                } catch {
                    // Polling error - device may have disconnected
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

// MARK: - Comparable Extension

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

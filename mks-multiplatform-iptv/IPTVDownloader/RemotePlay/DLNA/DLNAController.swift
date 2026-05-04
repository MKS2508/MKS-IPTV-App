//
//  DLNAController.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - AVTransport SOAP control for DLNA devices
//

import Foundation
import IPTVCore

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

    /// Callback to notify RemotePlayManager when a capability should be removed.
    var onCapabilityDowngrade: ((DeviceCapabilities) -> Void)?

    /// Known content duration from transmux probe (overrides TV-reported duration).
    /// Set by RemotePlayManager after DLNATransmuxSession is created.
    /// Many TVs report garbage TrackDuration for progressive MPEG-TS.
    var knownDuration: Double?

    /// Short-circuit flags to avoid repeated SOAP round-trips after a capability
    /// is confirmed unsupported by the device.
    private var pauseUnsupported = false
    private var seekUnsupported = false

    /// When true, skip Pause and Play(Speed=0) and go directly to Stop-as-pause.
    /// Set after the first successful Stop-as-pause cycle.
    private var useStopAsPause = false

    /// Fake-pause state: content was stopped to simulate pause.
    /// On next play(), re-load content at savedPositionForResume.
    private var isFakePaused = false
    private var savedPositionForResume: Double?

    /// Saved load() parameters for fake-pause resume.
    private var loadedContentURL: URL?
    private var loadedMetadata: MetadataResult?
    private var loadedStreaming: Bool = false

    /// Original source URL (pre-transmux) for metadata title fallback.
    /// Set by RemotePlayManager before calling load().
    var sourceContentURL: URL?

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
        MKSLog.dlna.info("DLNAController.connect — controlURL=\(controlURL.absoluteString)")
        // DLNA is connectionless - verify device is reachable by querying state
        playbackState = .connected(deviceId: device.id)

        // Query initial state
        do {
            let pos = try await queryPosition()
            MKSLog.dlna.info("DLNAController.connect — device responsive, state=\(pos)")
        } catch let error as RemotePlayError {
            MKSLog.dlna.error("DLNAController.connect — FAILED: \(error)")
            playbackState = .error(error)
            throw error
        } catch {
            MKSLog.dlna.error("DLNAController.connect — FAILED: \(error)")
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

    func load(url: URL, metadata: MetadataResult?, startPosition: Double, streaming: Bool = false) async throws {
        MKSLog.dlna.info("DLNAController.load — url=\(url.absoluteString)")
        MKSLog.dlna.debug("DLNAController.load — controlURL=\(controlURL.absoluteString)")
        MKSLog.dlna.debug("DLNAController.load — streaming=\(streaming)")
        MKSLog.dlna.debug("DLNAController.load — metadata.title=\(metadata?.title ?? "nil"), sourceContentURL=\(sourceContentURL?.lastPathComponent ?? "nil")")
        playbackState = .loading

        // Save load parameters for fake-pause resume
        loadedContentURL = url
        loadedMetadata = metadata
        loadedStreaming = streaming
        isFakePaused = false
        savedPositionForResume = nil

        // Build DIDL-Lite metadata - convert runtimeMinutes to seconds
        let durationSeconds: Double? = metadata?.runtimeMinutes.map { Double($0) * 60.0 }
        let didlMetadata = DLNAMetadataAdapter.buildDIDLLite(
            from: metadata,
            contentURL: url,
            duration: durationSeconds,
            streaming: streaming,
            fallbackTitle: deriveFallbackTitle()
        )
        MKSLog.dlna.debug("DLNAController.load — DIDL metadata length=\(didlMetadata.count)")

        do {
            // 0. Stop any current playback — many TVs reject SetAVTransportURI
            //    with error 705 "Access denied" if the transport is busy/locked.
            MKSLog.dlna.debug("DLNAController.load — sending Stop (clear transport)...")
            let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: instanceId)
            do {
                _ = try await DLNASOAPClient.send(
                    action: stopAction.actionName,
                    serviceType: .avTransport,
                    controlURL: controlURL,
                    arguments: stopAction.arguments
                )
                MKSLog.dlna.debug("DLNAController.load — Stop OK")
                // Give the TV time to release the transport lock
                try? await Task.sleep(for: .seconds(1))
            } catch {
                // Stop failing is non-fatal — TV might already be stopped
                MKSLog.dlna.warning("DLNAController.load — Stop failed (non-fatal): \(error)")
            }

            // 1. SetAVTransportURI — tell the TV what to play
            MKSLog.dlna.debug("DLNAController.load — sending SetAVTransportURI...")
            let setURIAction = DLNASOAPClient.AVTransportAction.setAVTransportURI(
                instanceId: instanceId,
                uri: url.absoluteString,
                metadata: didlMetadata
            )
            let setURIResponse = try await DLNASOAPClient.send(
                action: setURIAction.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: setURIAction.arguments
            )
            MKSLog.dlna.debug("DLNAController.load — SetAVTransportURI response=\(setURIResponse)")

            // 2. Play FIRST — most TVs reject Seek until content is playing/buffered
            MKSLog.dlna.debug("DLNAController.load — sending Play...")
            try await play()
            MKSLog.dlna.debug("DLNAController.load — Play sent")

            // 3. Seek AFTER Play (non-fatal) — TV needs time to buffer before accepting seeks.
            //    If seek fails, playback continues from the beginning which is acceptable.
            if startPosition > 0 {
                // Give the TV time to start buffering before attempting seek
                try? await Task.sleep(for: .seconds(2))
                MKSLog.dlna.debug("DLNAController.load — seeking to \(startPosition)s...")
                do {
                    try await seek(to: startPosition)
                    MKSLog.dlna.debug("DLNAController.load — Seek succeeded")
                } catch {
                    MKSLog.dlna.warning("DLNAController.load — Seek failed (non-fatal, playing from start): \(error)")
                    // Restore playing state since seek may have changed it
                    playbackState = .playing
                }
            }

            // Start polling for state updates
            MKSLog.dlna.debug("DLNAController.load — starting polling")
            startPolling()

        } catch let error as RemotePlayError {
            MKSLog.dlna.error("DLNAController.load — FAILED (RemotePlayError): \(error)")
            playbackState = .error(error)
            throw error
        } catch {
            MKSLog.dlna.error("DLNAController.load — FAILED: \(error)")
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }
    }

    func play() async throws {
        // Resume from fake pause (Stop was used as pause substitute)
        if isFakePaused, let resumePos = savedPositionForResume, let url = loadedContentURL {
            MKSLog.dlna.info("Resuming from fake pause at \(String(format: "%.1f", resumePos))s")
            isFakePaused = false
            savedPositionForResume = nil
            try await load(url: url, metadata: loadedMetadata, startPosition: resumePos, streaming: loadedStreaming)
            return
        }

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
        if pauseUnsupported {
            MKSLog.dlna.debug("Pause skipped — already confirmed unsupported by this device")
            throw RemotePlayError.soapError(501, "Pause not supported by this device")
        }

        // Fast path: if Stop-as-pause already proven to work, skip SOAP Pause/Play(Speed=0)
        if useStopAsPause {
            try await performStopAsPause()
            return
        }

        // Tier 1: Standard Pause
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
            return
        } catch let error as RemotePlayError {
            if case .soapError(let code, _) = error, code == 501 || code == 701 {
                MKSLog.dlna.warning("Pause failed (UPnP \(code)), trying Play(Speed=0)...")
            } else {
                playbackState = .error(error)
                throw error
            }
        } catch {
            let remoteError = RemotePlayError.transportError(error.localizedDescription)
            playbackState = .error(remoteError)
            throw remoteError
        }

        // Tier 2: Play(Speed=0) — some TVs accept this as pause
        do {
            let fallbackAction = DLNASOAPClient.AVTransportAction.play(
                instanceId: instanceId,
                speed: "0"
            )
            _ = try await DLNASOAPClient.send(
                action: fallbackAction.actionName,
                serviceType: .avTransport,
                controlURL: controlURL,
                arguments: fallbackAction.arguments
            )
            playbackState = .paused
            deviceState.transportState = .paused
            MKSLog.dlna.info("Play(Speed=0) fallback succeeded")
            return
        } catch {
            MKSLog.dlna.warning("Play(Speed=0) also failed: \(error), trying Stop-as-pause...")
        }

        // Tier 3: Stop + save position (fake pause) — re-loads on play()
        do {
            try await performStopAsPause()
            useStopAsPause = true  // Next time, skip tiers 1 & 2
            return
        } catch {
            MKSLog.dlna.error("Stop-as-pause also failed: \(error)")
        }

        // All three tiers failed — downgrade capability permanently
        pauseUnsupported = true
        downgradeCapability(.pause)
        playbackState = .playing
        throw RemotePlayError.soapError(501, "Pause not supported by this device (all fallbacks failed)")
    }

    /// Stop playback and save current position for resume.
    /// Used as a last-resort pause fallback when Pause and Play(Speed=0) fail.
    private func performStopAsPause() async throws {
        let currentPos = deviceState.currentTime
        MKSLog.dlna.info("Stop-as-pause — saving position \(String(format: "%.1f", currentPos))s before stopping")

        let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: instanceId)
        _ = try await DLNASOAPClient.send(
            action: stopAction.actionName,
            serviceType: .avTransport,
            controlURL: controlURL,
            arguments: stopAction.arguments
        )

        savedPositionForResume = currentPos
        isFakePaused = true
        playbackState = .paused
        deviceState.transportState = .paused
        stopPolling()
        MKSLog.dlna.info("Stop-as-pause succeeded — will resume at \(String(format: "%.1f", currentPos))s on play()")
    }

    func seek(to time: Double) async throws {
        if seekUnsupported {
            MKSLog.dlna.debug("Seek skipped — already confirmed unsupported by this device")
            throw RemotePlayError.soapError(710, "Seek not supported by this device")
        }

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
            // Downgrade seeking capability on known unsupported errors
            if case .soapError(let code, _) = error, code == 710 || code == 501 || code == 711 {
                MKSLog.dlna.warning("Seek failed (UPnP \(code)), disabling seek capability")
                seekUnsupported = true
                downgradeCapability(.seeking)
                // Restore playback state — seek failure is non-fatal for content
                if deviceState.transportState == .playing {
                    playbackState = .playing
                } else {
                    playbackState = .paused
                }
                throw error
            }
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

        let relTimeStr = response["RelTime"] ?? "00:00:00"
        let durationStr = response["TrackDuration"] ?? "00:00:00"
        let trackURI = response["TrackURI"] ?? "nil"
        let currentTime = parseTime(relTimeStr)
        let tvDuration = parseTime(durationStr)

        // Use known duration from transmux probe if available;
        // many TVs report garbage TrackDuration for progressive MPEG-TS
        // (e.g. computing from Content-Length / assumed bitrate).
        let duration = knownDuration ?? tvDuration

        // Log raw GetPositionInfo response for first few polls
        MKSLog.dlna.debug("GetPositionInfo raw — RelTime=\(relTimeStr), TrackDuration=\(durationStr), TrackURI=\(trackURI.prefix(80))")
        if let known = knownDuration, abs(tvDuration - known) > 60 {
            MKSLog.dlna.info("Duration override — TV reported \(durationStr) (\(String(format: "%.0f", tvDuration))s), using known \(String(format: "%.1f", known))s")
        }

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

    /// Remove a capability and notify the manager to update the UI.
    private func downgradeCapability(_ capability: DeviceCapabilities) {
        MKSLog.dlna.info("Downgrading capability: removing \(capability) from device")
        onCapabilityDowngrade?(capability)
    }

    /// Derive a fallback title from sourceContentURL when metadata is nil.
    /// Uses the URL's last path component (without extension) as a human-readable title.
    private func deriveFallbackTitle() -> String? {
        guard let url = sourceContentURL else { return nil }
        let filename = url.deletingPathExtension().lastPathComponent
        guard !filename.isEmpty else { return nil }
        // Clean up common URL artifacts: replace underscores/dots with spaces
        return filename
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
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
            var pollCount = 0
            while !Task.isCancelled {
                do {
                    let pos = try await self?.queryPosition()
                    if let state = self?.deviceState {
                        pollCount += 1
                        // Log first 5 polls and then every 10th for ongoing monitoring
                        if pollCount <= 5 || pollCount % 10 == 0 {
                            MKSLog.dlna.debug("Poll #\(pollCount) — transport=\(state.transportState.rawValue), time=\(String(format: "%.1f", state.currentTime))/\(String(format: "%.1f", state.duration)), isPlaying=\(pos?.isPlaying ?? false)")
                        }
                        self?.onStateUpdate?(state)
                    }
                } catch {
                    MKSLog.dlna.error("Poll error: \(error)")
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

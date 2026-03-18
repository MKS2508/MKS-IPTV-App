//
//  RemotePlayManager.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Main coordinator for DLNA/Cast remote playback
//

import Foundation
import Network
import TransmuxCore

/// Main coordinator for remote playback (DLNA and future Cast support).
/// Manages device discovery, connection lifecycle, and content handoff.
///
/// ## Architecture
/// - Singleton shared instance
/// - Observable for SwiftUI integration
/// - Coordinates SSDPDiscoveryService (DLNA) and future Cast discovery
/// - Manages active RemoteDeviceController for playback control
///
@MainActor
@Observable
final class RemotePlayManager: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = RemotePlayManager()

    // MARK: - Published Properties

    /// All discovered remote devices.
    var discoveredDevices: [RemoteDevice] = []

    /// Currently connected device (if any).
    var connectedDevice: RemoteDevice?

    /// Current playback state.
    var playbackState: RemotePlaybackState = .idle

    /// Current device state (position, volume, etc.).
    var deviceState: RemoteDeviceState?

    /// Currently streaming content URL (LAN-accessible).
    private(set) var streamingURL: URL?

    /// Metadata for current content.
    private(set) var currentMetadata: MetadataResult?

    /// Error to display in UI (if any).
    var lastError: RemotePlayError?

    // MARK: - Private Properties

    /// SSDP discovery service.
    private let ssdpDiscovery = SSDPDiscoveryService()

    /// Active device controller (DLNA or Cast).
    private var activeController: RemoteDeviceController?

    /// Active transmux session ID for cleanup on disconnect or new load.
    private var activeTransmuxSessionID: String?

    /// Background task monitoring transmux completion (sentinel file).
    /// Must be cancelled on disconnect to prevent leaked tasks.
    private var transmuxMonitorTask: Task<Void, Never>?

    /// Discovery state.
    private(set) var isDiscovering = false

    // MARK: - Initialization

    private init() {
        setupDiscoveryCallbacks()
        // Auto-start SSDP discovery at launch so devices are ready
        // before the user opens the player or gear menu.
        startDiscovery()
    }

    // MARK: - Public API - Discovery

    /// Start discovering remote devices on the network.
    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        ssdpDiscovery.startDiscovery()
    }

    /// Stop discovering devices.
    func stopDiscovery() {
        isDiscovering = false
        ssdpDiscovery.stopDiscovery()
    }

    /// Refresh discovery (send new M-SEARCH messages).
    func refreshDiscovery() {
        ssdpDiscovery.refresh()
    }

    /// Clear all discovered devices.
    func clearDiscoveredDevices() {
        ssdpDiscovery.clearDevices()
        discoveredDevices = []
    }

    // MARK: - Public API - Connection

    /// Connect to a remote device.
    /// - Parameter device: The device to connect to
    func connect(to device: RemoteDevice) async throws {
        // If same device is already connected, just return
        if connectedDevice?.id == device.id {
            print("[DLNACast] connect — already connected to \(device.name)")
            return
        }

        // Disconnect existing device if any
        if connectedDevice != nil {
            print("[DLNACast] connect — disconnecting previous device before connecting to \(device.name)")
            await disconnect()
        }

        print("[DLNACast] connect — connecting to \(device.name) (type=\(device.type.displayName), transport=\(device.effectiveTransport))")
        print("[DLNACast] connect — controlURL=\(device.metadata["controlURL"] ?? "MISSING")")
        playbackState = .connecting(deviceId: device.id)

        do {
            // Create appropriate controller based on device type
            let controller = try createController(for: device)

            // Connect to device
            try await controller.connect()

            activeController = controller
            connectedDevice = device
            playbackState = .connected(deviceId: device.id)
            deviceState = .idle
            print("[DLNACast] connect — SUCCESS, connected to \(device.name)")

        } catch {
            print("[DLNACast] connect — FAILED: \(error)")
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Disconnect from current device.
    func disconnect() async {
        guard let controller = activeController else { return }

        print("[DLNACast] disconnect — stopping controller, transmux monitor, and transmux session")

        await controller.disconnect()

        // Cancel transmux monitor task
        transmuxMonitorTask?.cancel()
        transmuxMonitorTask = nil

        // Cleanup active transmux session
        if let sessionID = activeTransmuxSessionID {
            await TransmuxServer.shared.stop()
            await TransmuxingService.shared.cleanup(sessionID: sessionID)
            activeTransmuxSessionID = nil
        }

        activeController = nil
        connectedDevice = nil
        playbackState = .idle
        deviceState = nil
        streamingURL = nil
        currentMetadata = nil
    }

    // MARK: - Public API - Playback

    /// Load content on remote device.
    /// - Parameters:
    ///   - url: Local content URL (will be converted to LAN URL)
    ///   - metadata: Content metadata for display
    ///   - startPosition: Starting position in seconds
    func load(
        url: URL,
        metadata: MetadataResult?,
        startPosition: Double = 0
    ) async throws {
        guard let controller = activeController else {
            print("[DLNACast] load — ERROR: no active controller")
            throw RemotePlayError.noActiveSession
        }

        print("[DLNACast] load — input URL=\(url.absoluteString)")

        // Reset known duration — non-transmux loads use TV-reported duration
        if let dlnaController = activeController as? DLNAController {
            dlnaController.knownDuration = nil
            dlnaController.sourceContentURL = url
        }
        (activeController as? CastController)?.sourceContentURL = url

        // Convert localhost URL to LAN URL for remote access
        guard let lanURL = convertToLANURL(url) else {
            print("[DLNACast] load — ERROR: convertToLANURL failed (no LAN IP?)")
            throw RemotePlayError.networkUnavailable
        }

        print("[DLNACast] load — LAN URL=\(lanURL.absoluteString)")
        print("[DLNACast] load — startPosition=\(startPosition), metadata.title=\(metadata?.title ?? "nil")")

        streamingURL = lanURL
        currentMetadata = metadata

        do {
            try await controller.load(
                url: lanURL,
                metadata: metadata,
                startPosition: startPosition,
                streaming: false
            )
            print("[DLNACast] load — SUCCESS")
        } catch {
            print("[DLNACast] load — FAILED: \(error)")
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Load content directly on remote device without URL conversion.
    /// Used for "Solo Cast" mode — sends the original IPTV URL directly to the Cast device.
    /// No transmuxing, no local playback, no localhost-to-LAN conversion.
    /// - Parameters:
    ///   - url: Remote content URL (IPTV server URL, sent as-is)
    ///   - metadata: Content metadata for display
    ///   - startPosition: Starting position in seconds
    func loadDirect(
        url: URL,
        metadata: MetadataResult?,
        startPosition: Double = 0
    ) async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        // Reset known duration — direct loads use TV-reported duration
        if let dlnaController = activeController as? DLNAController {
            dlnaController.knownDuration = nil
            dlnaController.sourceContentURL = url
        }
        (activeController as? CastController)?.sourceContentURL = url

        streamingURL = url
        currentMetadata = metadata

        do {
            try await controller.load(
                url: url,
                metadata: metadata,
                startPosition: startPosition,
                streaming: false
            )
        } catch {
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Start the appropriate transmux pipeline for the connected device and load content.
    /// - DLNA-family devices: `startDLNATransmux` → progressive MPEG-TS → `TransmuxServer.startDLNA`
    /// - Cast-family devices: `startCastTransmux` → segmented MPEG-TS + HLS → `TransmuxServer.startCast`
    /// Audio transcoding (AC3/EAC3/DTS → AAC) is auto-enabled based on `device.type.needsAudioTranscode`.
    func loadWithTransmux(
        url: URL,
        metadata: MetadataResult?,
        startPosition: Double = 0
    ) async throws {
        guard let device = connectedDevice,
              let controller = activeController else {
            print("[DLNACast] loadWithTransmux — ERROR: no active session")
            throw RemotePlayError.noActiveSession
        }

        print("[DLNACast] loadWithTransmux — source=\(url.absoluteString)")
        print("[DLNACast] loadWithTransmux — device=\(device.name), transport=\(device.effectiveTransport), transcodeAudio=\(device.type.needsAudioTranscode)")

        playbackState = .loading
        currentMetadata = metadata

        // Cleanup any previous transmux session
        if let prevID = activeTransmuxSessionID {
            print("[DLNACast] loadWithTransmux — cleaning up previous session \(prevID)")
            await TransmuxServer.shared.stop()
            await TransmuxingService.shared.cleanup(sessionID: prevID)
            activeTransmuxSessionID = nil
        }

        let transcodeAudio = device.type.needsAudioTranscode
        let service = TransmuxingService.shared

        do {
            let serverSession: TransmuxServer.Session

            switch device.effectiveTransport {
            case .dlna:
                // Progressive MPEG-TS → growing .ts file → HTTP range requests with DLNA headers
                print("[DLNACast] loadWithTransmux — starting DLNA transmux pipeline...")
                let session = try await service.startDLNATransmux(
                    from: url,
                    transcodeAudio: transcodeAudio
                )
                activeTransmuxSessionID = session.sessionID
                print("[DLNACast] loadWithTransmux — DLNA transmux started, sessionID=\(session.sessionID), outputPath=\(session.outputPath)")

                // Inject known duration into DLNAController to override TV-reported garbage
                if let dlnaController = activeController as? DLNAController {
                    dlnaController.knownDuration = session.duration
                    print("[DLNACast] loadWithTransmux — injected knownDuration=\(String(format: "%.1f", session.duration))s into DLNAController")
                }

                // Buffer initial content before starting server
                print("[DLNACast] loadWithTransmux — buffering 2s before starting HTTP server...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                await TransmuxServer.shared.setDLNAMode(true)
                serverSession = try await TransmuxServer.shared.startDLNA(
                    filePath: session.outputPath,
                    expectedSize: session.expectedSize
                )
                print("[DLNACast] loadWithTransmux — TransmuxServer started, localURL=\(serverSession.localURL.absoluteString)")

                // Monitor transmux completion in background (tracked for cancellation on disconnect)
                let outputPath = session.outputPath
                transmuxMonitorTask?.cancel()
                transmuxMonitorTask = Task.detached {
                    let sentinelDir = (outputPath as NSString).deletingLastPathComponent
                    let sentinelPath = sentinelDir + "/.transmux_complete"
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard !Task.isCancelled else { break }
                        if FileManager.default.fileExists(atPath: sentinelPath) {
                            let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath)
                            let finalSize = (attrs?[.size] as? Int64) ?? 0
                            await TransmuxServer.shared.setExpectedSize(finalSize)
                            await TransmuxServer.shared.setComplete()
                            print("[DLNACast] loadWithTransmux — transmux complete, finalSize=\(finalSize)")
                            break
                        }
                    }
                }

            case .castV2:
                // Segmented MPEG-TS → .ts segments + .m3u8 → file serving
                print("[DLNACast] loadWithTransmux — starting Cast transmux pipeline...")
                let session = try await service.startCastTransmux(
                    from: url,
                    transcodeAudio: transcodeAudio
                )
                activeTransmuxSessionID = session.sessionID
                print("[DLNACast] loadWithTransmux — Cast transmux started, sessionID=\(session.sessionID)")

                // Wait for at least 1 segment to be written
                print("[DLNACast] loadWithTransmux — waiting for first segment...")
                while session.segmentCounter.count == 0 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }

                serverSession = try await TransmuxServer.shared.startCast(
                    directory: session.outputDir
                )
                print("[DLNACast] loadWithTransmux — Cast server started, localURL=\(serverSession.localURL.absoluteString)")
            }

            // Convert localhost URL to LAN URL for remote device access
            guard let lanURL = convertToLANURL(serverSession.localURL) else {
                print("[DLNACast] loadWithTransmux — ERROR: convertToLANURL failed")
                throw RemotePlayError.networkUnavailable
            }

            print("[DLNACast] loadWithTransmux — LAN URL for TV=\(lanURL.absoluteString)")
            streamingURL = lanURL

            // Inject original source URL into controller for metadata title fallback
            if let dlnaController = activeController as? DLNAController {
                dlnaController.sourceContentURL = url
            }
            (activeController as? CastController)?.sourceContentURL = url

            // Always use streaming: false — the TransmuxServer supports range requests
            // on growing files, so DIDL-Lite protocolInfo should use OP=01 (byte-range
            // supported), CI=0 (not converted). DLNA TVs refuse content with OP=00/CI=1.
            print("[DLNACast] loadWithTransmux — sending to controller.load(url: \(lanURL.absoluteString), streaming: false)...")
            try await controller.load(
                url: lanURL,
                metadata: metadata,
                startPosition: startPosition,
                streaming: false
            )
            print("[DLNACast] loadWithTransmux — SUCCESS, content playing on \(device.name)")
        } catch {
            print("[DLNACast] loadWithTransmux — FAILED: \(error)")
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Play content on remote device.
    func play() async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.play()
        } catch {
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Pause content on remote device.
    func pause() async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.pause()
        } catch {
            // Don't set error state for unsupported capabilities — the controller
            // already downgraded the capability and kept playback state intact.
            if let rpe = error as? RemotePlayError, case .soapError = rpe {
                throw error
            }
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Seek to position on remote device.
    func seek(to time: Double) async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.seek(to: time)
        } catch {
            // Don't set error state for unsupported capabilities — the controller
            // already downgraded the capability and kept playback state intact.
            if let rpe = error as? RemotePlayError, case .soapError = rpe {
                throw error
            }
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Stop playback on remote device.
    func stop() async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.stop()
        } catch {
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Set volume on remote device.
    func setVolume(_ volume: Float) async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.setVolume(volume)
        } catch {
            throw error
        }
    }

    /// Set mute state on remote device.
    func setMuted(_ muted: Bool) async throws {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        do {
            try await controller.setMuted(muted)
        } catch {
            throw error
        }
    }

    // MARK: - Public API - State Query

    /// Query current position from remote device.
    func queryPosition() async throws -> (currentTime: Double, duration: Double, isPlaying: Bool) {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        let result = try await controller.queryPosition()
        deviceState?.currentTime = result.currentTime
        deviceState?.duration = result.duration
        return result
    }

    /// Query volume from remote device.
    func queryVolume() async throws -> (volume: Float, isMuted: Bool) {
        guard let controller = activeController else {
            throw RemotePlayError.noActiveSession
        }

        let result = try await controller.queryVolume()
        deviceState?.volume = result.volume
        deviceState?.isMuted = result.isMuted
        return result
    }

    // MARK: - Private Helpers

    /// Setup callbacks for device discovery.
    private func setupDiscoveryCallbacks() {
        ssdpDiscovery.onDeviceFound = { [weak self] device in
            guard let self else { return }
            if !self.discoveredDevices.contains(where: { $0.id == device.id }) {
                self.discoveredDevices.append(device)
            }
        }

        ssdpDiscovery.onDeviceLost = { [weak self] deviceId in
            guard let self else { return }
            self.discoveredDevices.removeAll { $0.id == deviceId }

            // If lost device was connected, disconnect
            if self.connectedDevice?.id == deviceId {
                Task {
                    try? await self.disconnect()
                }
            }
        }
    }

    /// Create appropriate controller for device type and wire state callbacks.
    private func createController(for device: RemoteDevice) throws -> RemoteDeviceController {
        let stateHandler: @Sendable (RemoteDeviceState) -> Void = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.deviceState = state
                switch state.transportState {
                case .playing:
                    self?.playbackState = .playing
                case .paused:
                    self?.playbackState = .paused
                case .stopped:
                    self?.playbackState = .stopped
                case .transitioning:
                    self?.playbackState = .buffering
                case .noMedia, .unknown:
                    break
                }
            }
        }

        switch device.effectiveTransport {
        case .dlna:
            let controller = try DLNAController(device: device)
            controller.onStateUpdate = stateHandler
            controller.onCapabilityDowngrade = { [weak self] capability in
                Task { @MainActor [weak self] in
                    self?.connectedDevice?.capabilities.remove(capability)
                    print("[DLNACast] Capability downgraded — remaining: \(self?.connectedDevice?.capabilities ?? [])")
                }
            }
            return controller
        case .castV2:
            let controller = try CastController(device: device)
            controller.onStateUpdate = stateHandler
            return controller
        }
    }

    /// Convert localhost URL to LAN URL for remote device access.
    private func convertToLANURL(_ url: URL) -> URL? {
        // Get LAN IP address
        guard let lanIP = Self.getLANIPAddress() else { return nil }

        // Parse URL components
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // Check if this is a localhost URL
        let localhostHosts = ["localhost", "127.0.0.1", "::1"]
        guard let host = components.host, localhostHosts.contains(host) else {
            // Not a localhost URL, return as-is
            return url
        }

        // Replace host with LAN IP
        components.host = lanIP

        return components.url
    }

    // MARK: - LAN IP Detection

    /// Get the LAN IP address of this device.
    /// Used to convert localhost URLs to LAN URLs for remote device access.
    nonisolated static func getLANIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var bestIP: String?
        var fallbackIP: String?

        var current: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = current {
            defer { current = addr.pointee.ifa_next }

            // Only IPv4 (AF_INET)
            guard addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            // Extract interface name and IP
            let name = String(cString: addr.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)

            // Skip loopback and link-local
            if ip.hasPrefix("127.") || ip.hasPrefix("169.254.") { continue }

            // Prefer en0 (WiFi on Apple devices)
            if name == "en0" {
                bestIP = ip
            } else if fallbackIP == nil {
                fallbackIP = ip
            }
        }

        return bestIP ?? fallbackIP
    }
}

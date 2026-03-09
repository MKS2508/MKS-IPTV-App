//
//  RemotePlayManager.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Main coordinator for DLNA/Cast remote playback
//

import Foundation
import Network

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

    /// Discovery state.
    private(set) var isDiscovering = false

    // MARK: - Initialization

    private init() {
        setupDiscoveryCallbacks()
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
            return
        }

        // Disconnect existing device if any
        if connectedDevice != nil {
            await disconnect()
        }

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

        } catch {
            playbackState = .error((error as? RemotePlayError) ?? .unknown(error.localizedDescription))
            throw error
        }
    }

    /// Disconnect from current device.
    func disconnect() async {
        guard let controller = activeController else { return }

        await controller.disconnect()

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
            throw RemotePlayError.noActiveSession
        }

        // Convert localhost URL to LAN URL for remote access
        guard let lanURL = convertToLANURL(url) else {
            throw RemotePlayError.networkUnavailable
        }

        streamingURL = lanURL
        currentMetadata = metadata

        do {
            try await controller.load(
                url: lanURL,
                metadata: metadata,
                startPosition: startPosition
            )
        } catch {
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

        streamingURL = url
        currentMetadata = metadata

        do {
            try await controller.load(
                url: url,
                metadata: metadata,
                startPosition: startPosition
            )
        } catch {
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
        switch device.type {
        case .dlna:
            let controller = try DLNAController(device: device)
            controller.onStateUpdate = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.deviceState = state
                    // Sync playback state from transport state
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
            return controller
        case .chromecast, .googleTV:
            let controller = try CastController(device: device)
            controller.onStateUpdate = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.deviceState = state
                    // Sync playback state from transport state
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

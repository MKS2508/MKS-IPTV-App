//
//  SSDPDiscoveryService.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SSDP/UPnP device discovery via UDP multicast
//

import Foundation

/// Discovers DLNA MediaRenderer devices via SSDP multicast (239.255.255.250:1900).
///
/// ## Architecture
/// Uses POSIX BSD sockets for SSDP because Network.framework's `NWConnection`
/// creates a "connected" UDP socket that filters incoming packets by remote address.
/// SSDP responses are unicast from each device's own IP, not from the multicast
/// address, so they get silently dropped by connected sockets.
///
/// An unconnected UDP socket (`sendto`/`recvfrom`) correctly receives responses
/// from any source address.
///
/// ## Usage
/// ```swift
/// let discovery = SSDPDiscoveryService()
/// discovery.onDeviceFound = { device in print("Found: \(device.name)") }
/// discovery.startDiscovery()
/// ```
@MainActor
final class SSDPDiscoveryService: @unchecked Sendable {

    // MARK: - Constants

    /// SSDP multicast address.
    private static let ssdpMulticastAddress = "239.255.255.250"

    /// SSDP port.
    private static let ssdpPort: UInt16 = 1900

    /// Maximum wait time for M-SEARCH responses (MX header value).
    private static let searchMX: Int = 3

    /// Interval between periodic re-discovery sweeps.
    private static let rediscoveryInterval: TimeInterval = 30.0

    /// Number of discovery cycles before a device is considered stale.
    private static let maxMissedCycles: Int = 3

    /// Receive timeout per recvfrom call (seconds).
    private static let recvTimeoutSec: Int = 5

    /// Device types to search for (MediaRenderer for playback).
    private static let searchTargets: [String] = [
        "urn:schemas-upnp-org:device:MediaRenderer:1",
        "urn:schemas-upnp-org:device:MediaRenderer:2",
        "urn:dial-multiscreen-org:service:dial:1"
    ]

    // MARK: - Properties

    /// Discovered devices keyed by UDN.
    private(set) var discoveredDevices: [String: RemoteDevice] = [:]

    /// Tracks how many cycles each device has been unseen (for TTL expiry).
    private var deviceMissedCycles: [String: Int] = [:]

    /// Set of device UDNs seen in the current discovery cycle.
    private var devicesSeenThisCycle: Set<String> = []

    /// Callback when a new device is discovered.
    var onDeviceFound: ((RemoteDevice) -> Void)?

    /// Callback when a device is removed (stale or failed to refresh).
    var onDeviceLost: ((String) -> Void)?

    /// Whether discovery is currently active.
    private(set) var isDiscovering = false

    /// Active device description fetch tasks.
    private var fetchTasks: [String: Task<Void, Never>] = [:]

    /// Periodic re-discovery task.
    private var rediscoveryTask: Task<Void, Never>?

    /// Background task for the current M-SEARCH send+receive cycle.
    private var searchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    deinit {
        searchTask?.cancel()
        fetchTasks.values.forEach { $0.cancel() }
        rediscoveryTask?.cancel()
    }

    // MARK: - Public API

    /// Start SSDP discovery for DLNA MediaRenderer devices.
    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true

        performSearch()
        startPeriodicRediscovery()
    }

    /// Stop SSDP discovery and cleanup resources.
    func stopDiscovery() {
        isDiscovering = false

        rediscoveryTask?.cancel()
        rediscoveryTask = nil

        searchTask?.cancel()
        searchTask = nil

        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks.removeAll()
    }

    /// Refresh discovery by sending new M-SEARCH messages.
    func refresh() {
        guard isDiscovering else {
            startDiscovery()
            return
        }

        searchTask?.cancel()
        performSearch()
    }

    /// Clear all discovered devices.
    func clearDevices() {
        let previousDeviceIds = discoveredDevices.keys
        discoveredDevices.removeAll()
        deviceMissedCycles.removeAll()

        for deviceId in previousDeviceIds {
            onDeviceLost?(deviceId)
        }
    }

    // MARK: - Periodic Re-Discovery

    private func startPeriodicRediscovery() {
        rediscoveryTask?.cancel()
        rediscoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SSDPDiscoveryService.rediscoveryInterval))
                guard !Task.isCancelled else { break }
                await self?.performRediscoveryCycle()
            }
        }
    }

    private func performRediscoveryCycle() {
        expireStaleDevices()
        devicesSeenThisCycle.removeAll()
        searchTask?.cancel()
        performSearch()
    }

    private func expireStaleDevices() {
        for deviceId in discoveredDevices.keys {
            if devicesSeenThisCycle.contains(deviceId) {
                deviceMissedCycles[deviceId] = 0
            } else {
                deviceMissedCycles[deviceId, default: 0] += 1
            }
        }

        let expiredIds = deviceMissedCycles.filter { $0.value >= SSDPDiscoveryService.maxMissedCycles }.map(\.key)
        for deviceId in expiredIds {
            discoveredDevices.removeValue(forKey: deviceId)
            deviceMissedCycles.removeValue(forKey: deviceId)
            onDeviceLost?(deviceId)
        }
    }

    // MARK: - M-SEARCH via POSIX Sockets

    /// Send M-SEARCH messages on all targets and listen for responses.
    /// Runs the blocking socket I/O on a background task.
    private func performSearch() {
        searchTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            for target in SSDPDiscoveryService.searchTargets {
                guard !Task.isCancelled else { break }
                await self.sendAndReceive(target: target)
            }
        }
    }

    /// Create an unconnected UDP socket, sendto() the M-SEARCH, and recvfrom()
    /// responses for `recvTimeoutSec` seconds from ANY source IP.
    nonisolated private func sendAndReceive(target: String) async {
        // Create UDP socket
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            MKSLog.dlna.error("SSDP Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }
        defer { close(fd) }

        // Set receive timeout so recvfrom doesn't block forever
        var timeout = timeval(
            tv_sec: SSDPDiscoveryService.recvTimeoutSec,
            tv_usec: 0
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Allow address reuse
        var reuseAddr: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        // Build multicast destination address
        var destAddr = sockaddr_in()
        destAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = SSDPDiscoveryService.ssdpPort.bigEndian
        inet_pton(AF_INET, SSDPDiscoveryService.ssdpMulticastAddress, &destAddr.sin_addr)

        // Build M-SEARCH message
        let message = "M-SEARCH * HTTP/1.1\r\nHOST: \(SSDPDiscoveryService.ssdpMulticastAddress):\(SSDPDiscoveryService.ssdpPort)\r\nMAN: \"ssdp:discover\"\r\nMX: \(SSDPDiscoveryService.searchMX)\r\nST: \(target)\r\nUSER-AGENT: MKS-IPTV/1.0 UPnP/1.1\r\n\r\n"

        // Send M-SEARCH via sendto (unconnected — responses come from any IP)
        message.withCString { ptr in
            withUnsafePointer(to: &destAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    let sent = sendto(fd, ptr, strlen(ptr), 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    if sent < 0 {
                        MKSLog.dlna.error("SSDP sendto failed for \(target): \(String(cString: strerror(errno)))")
                    }
                }
            }
        }

        // Receive loop — recvfrom returns responses from any source IP
        // Runs until timeout or task cancellation
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !Task.isCancelled {
            var senderAddr = sockaddr_in()
            var senderAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buffer, buffer.count, 0, sa, &senderAddrLen)
                }
            }

            // Timeout or error → stop receiving for this target
            if bytesRead <= 0 { break }

            let data = Data(bytes: buffer, count: bytesRead)
            await handleSSDPResponse(data)
        }
    }

    // MARK: - Response Handling

    /// Parse an SSDP response and dispatch device fetch to MainActor.
    nonisolated private func handleSSDPResponse(_ data: Data) async {
        guard let message = String(data: data, encoding: .utf8) else { return }

        let headers = parseSSDPHeaders(message)
        guard isMediaRenderer(headers: headers) else { return }

        guard let locationString = headers["LOCATION"],
              let locationURL = URL(string: locationString) else { return }

        guard let usn = headers["USN"] else { return }
        let udn = extractUDN(from: usn)

        await MainActor.run { [weak self] in
            guard let self else { return }

            self.devicesSeenThisCycle.insert(udn)

            // Already known — just reset TTL
            if self.discoveredDevices.keys.contains(udn) {
                self.deviceMissedCycles[udn] = 0
                return
            }

            // Already fetching
            guard self.fetchTasks[udn] == nil else { return }

            // Fetch device description
            let task = Task<Void, Never> {
                await self.fetchAndParseDeviceDescription(locationURL: locationURL, udn: udn)
            }
            self.fetchTasks[udn] = task
        }
    }

    // MARK: - Header Parsing

    nonisolated private func parseSSDPHeaders(_ message: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = message.components(separatedBy: "\r\n")
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colonIndex]).uppercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return headers
    }

    nonisolated private func isMediaRenderer(headers: [String: String]) -> Bool {
        let st = headers["ST"] ?? headers["NT"] ?? ""
        return st.contains("MediaRenderer") || st.contains("dial-multiscreen-org")
    }

    nonisolated private func extractUDN(from usn: String) -> String {
        if let range = usn.range(of: "uuid:([a-fA-F0-9-]+)", options: .regularExpression) {
            return String(usn[range])
        }
        return usn
    }

    // MARK: - Device Description Fetch

    private func fetchAndParseDeviceDescription(locationURL: URL, udn: String) async {
        do {
            var parsed = try await DLNADeviceParser.parse(from: locationURL)

            // If device has no AVTransport and no DIAL, probe common alternative
            // description paths for a MediaRenderer endpoint (e.g. /dmr.xml on port 2870).
            if parsed.avTransportControlURL == nil && !parsed.hasDIALService,
               let ip = locationURL.host {
                let ssdpPort = locationURL.port ?? 80
                MKSLog.dlna.debug("SSDP Device \(parsed.friendlyName) has no AVTransport, probing for MediaRenderer on \(ip)...")
                if let upgraded = await DLNADeviceParser.probeForMediaRenderer(ip: ip, ssdpPort: ssdpPort) {
                    parsed = upgraded
                }
            }

            // Skip devices with no usable transport (no AVTransport AND no DIAL).
            // These are typically AirPlay-only devices (e.g. Apple TV) that advertise
            // via SSDP but can't receive DLNA or Cast content.
            if parsed.avTransportControlURL == nil && !parsed.hasDIALService {
                MKSLog.dlna.debug("SSDP Skipping \(parsed.friendlyName) — no AVTransport and no DIAL (likely AirPlay-only)")
                await MainActor.run { [weak self] in
                    self?.fetchTasks.removeValue(forKey: udn)
                }
                return
            }

            let device = DLNADeviceParser.toRemoteDevice(parsed)

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.discoveredDevices[udn] = device
                self.deviceMissedCycles[udn] = 0
                self.fetchTasks.removeValue(forKey: udn)
                self.onDeviceFound?(device)
            }
        } catch {
            MKSLog.dlna.error("SSDP Failed to parse device at \(locationURL): \(error)")
            await MainActor.run { [weak self] in
                self?.fetchTasks.removeValue(forKey: udn)
            }
        }
    }
}

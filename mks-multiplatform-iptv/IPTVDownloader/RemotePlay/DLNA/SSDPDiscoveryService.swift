//
//  SSDPDiscoveryService.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SSDP/UPnP device discovery via UDP multicast
//

import Foundation
import Network

/// Discovers DLNA MediaRenderer devices via SSDP multicast (239.255.255.250:1900).
/// Uses Network.framework for UDP multicast and unicast communication.
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

    /// Device types to search for (MediaRenderer for playback).
    private static let searchTargets: [String] = [
        "urn:schemas-upnp-org:device:MediaRenderer:1",
        "urn:schemas-upnp-org:device:MediaRenderer:2",
        "urn:dial-multiscreen-org:service:dial:1"  // DIAL protocol (some smart TVs)
    ]

    // MARK: - Properties

    /// UDP connection for listening to SSDP messages.
    private var listenerConnection: NWConnection?

    /// UDP connection for sending M-SEARCH messages.
    private var searchConnection: NWConnection?

    /// Queue for network operations.
    private let networkQueue = DispatchQueue(label: "SSDPDiscovery.network", qos: .utility)

    /// Discovered devices keyed by UDN.
    private(set) var discoveredDevices: [String: RemoteDevice] = [:]

    /// Callback when a new device is discovered.
    var onDeviceFound: ((RemoteDevice) -> Void)?

    /// Callback when a device is removed (failed to refresh).
    var onDeviceLost: ((String) -> Void)?

    /// Whether discovery is currently active.
    private(set) var isDiscovering = false

    /// Active device description fetch tasks.
    private var fetchTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Lifecycle

    deinit {
        // Cleanup connections directly since deinit can't call MainActor methods
        listenerConnection?.cancel()
        searchConnection?.cancel()
        fetchTasks.values.forEach { $0.cancel() }
    }

    // MARK: - Public API

    /// Start SSDP discovery for DLNA MediaRenderer devices.
    /// Sends M-SEARCH messages and listens for responses.
    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true

        // Start UDP listener for M-SEARCH responses
        startUDPListener()

        // Send M-SEARCH for immediate discovery
        sendMSearchMessages()
    }

    /// Stop SSDP discovery and cleanup resources.
    func stopDiscovery() {
        isDiscovering = false

        // Cancel pending fetch tasks
        fetchTasks.values.forEach { $0.cancel() }
        fetchTasks.removeAll()

        // Cancel connections
        listenerConnection?.cancel()
        listenerConnection = nil

        searchConnection?.cancel()
        searchConnection = nil
    }

    /// Refresh discovery by sending new M-SEARCH messages.
    func refresh() {
        guard isDiscovering else {
            startDiscovery()
            return
        }
        sendMSearchMessages()
    }

    /// Clear all discovered devices.
    func clearDevices() {
        let previousDeviceIds = discoveredDevices.keys
        discoveredDevices.removeAll()

        for deviceId in previousDeviceIds {
            onDeviceLost?(deviceId)
        }
    }

    // MARK: - UDP Listener

    /// Start UDP listener for M-SEARCH responses on port 1900.
    private func startUDPListener() {
        // Bind to SSDP port for receiving responses
        let localEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.any),
            port: .init(rawValue: 0)!  // Use ephemeral port, we'll send to multicast
        )

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let connection = NWConnection(to: localEndpoint, using: parameters)

        connection.stateUpdateHandler = { [weak self, connection] state in
            switch state {
            case .ready:
                // Start receiving - use captured connection reference
                connection.receiveMessage { data, _, _, error in
                    if let data = data, error == nil {
                        self?.handleSSDPMessage(data)
                    }
                    // Continue receiving
                    connection.receiveMessage { data, _, _, error in
                        if let data = data, error == nil {
                            self?.handleSSDPMessage(data)
                        }
                    }
                }
            case .failed(let error):
                print("[SSDP] Listener failed: \(error)")
            default:
                break
            }
        }

        connection.start(queue: networkQueue)
        listenerConnection = connection
    }

    /// Continuous receive loop for UDP messages.
    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data, error == nil {
                self?.handleSSDPMessage(data)
            }
            // Continue receiving
            self?.receiveLoop(on: connection)
        }
    }

    // MARK: - M-SEARCH

    /// Send M-SEARCH messages for all target types.
    private func sendMSearchMessages() {
        for target in SSDPDiscoveryService.searchTargets {
            sendMSearch(target: target)
        }
    }

    /// Send a single M-SEARCH message for the specified search target.
    private func sendMSearch(target: String) {
        let message = buildMSearchMessage(target: target)
        guard let data = message.data(using: .utf8) else { return }

        let endpoint = NWEndpoint.hostPort(
            host: .init(SSDPDiscoveryService.ssdpMulticastAddress),
            port: .init(rawValue: SSDPDiscoveryService.ssdpPort)!
        )

        let connection = NWConnection(to: endpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                connection?.send(content: data, completion: .contentProcessed { error in
                    if let error = error {
                        print("[SSDP] M-SEARCH send error: \(error)")
                    }
                    // Close connection after sending
                    connection?.cancel()
                })
            case .failed(let error):
                print("[SSDP] M-SEARCH connection failed: \(error)")
                connection?.cancel()
            default:
                break
            }
        }

        connection.start(queue: networkQueue)
    }

    /// Build M-SEARCH message for UPnP device discovery.
    private func buildMSearchMessage(target: String) -> String {
        """
        M-SEARCH * HTTP/1.1\r
        HOST: \(SSDPDiscoveryService.ssdpMulticastAddress):\(SSDPDiscoveryService.ssdpPort)\r
        MAN: "ssdp:discover"\r
        MX: \(SSDPDiscoveryService.searchMX)\r
        ST: \(target)\r
        USER-AGENT: MKS-IPTV/1.0 UPnP/1.1\r
        \r

        """
    }

    // MARK: - Message Handling

    /// Handle incoming SSDP message (NOTIFY or M-SEARCH response).
    private func handleSSDPMessage(_ data: Data) {
        guard let message = String(data: data, encoding: .utf8) else { return }

        // Parse SSDP headers
        let headers = parseSSDPHeaders(message)

        // Check if this is a MediaRenderer device
        guard isMediaRenderer(headers: headers) else { return }

        // Extract LOCATION URL
        guard let locationString = headers["LOCATION"],
              let locationURL = URL(string: locationString) else { return }

        // Extract USN (Unique Service Name) as device identifier
        guard let usn = headers["USN"] else { return }

        // Extract UDN from USN (format: uuid:device-uuid or uuid:device-uuid::urn:...)
        let udn = extractUDN(from: usn)

        // Avoid duplicate fetches
        guard !discoveredDevices.keys.contains(udn), !fetchTasks.keys.contains(udn) else { return }

        // Fetch device description in background
        let task = Task<Void, Never> { [weak self] in
            await self?.fetchAndParseDeviceDescription(
                locationURL: locationURL,
                udn: udn
            )
        }

        fetchTasks[udn] = task
    }

    /// Parse SSDP message headers into a dictionary.
    private func parseSSDPHeaders(_ message: String) -> [String: String] {
        var headers: [String: String] = [:]

        let lines = message.components(separatedBy: "\r\n")
        for line in lines {
            let colonIndex = line.firstIndex(of: ":")
            guard let index = colonIndex else { continue }

            let key = String(line[..<index]).uppercased()
            let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return headers
    }

    /// Check if the SSDP headers indicate a MediaRenderer device.
    private func isMediaRenderer(headers: [String: String]) -> Bool {
        // Check ST (Search Target) or NT (Notification Type)
        let searchTarget = headers["ST"] ?? headers["NT"] ?? ""

        // Accept MediaRenderer devices
        return searchTarget.contains("MediaRenderer") ||
               searchTarget.contains("dial-multiscreen-org")
    }

    /// Extract UDN from USN header value.
    private func extractUDN(from usn: String) -> String {
        // USN format: uuid:device-uuid or uuid:device-uuid::urn:...
        if let uuidRange = usn.range(of: "uuid:([a-fA-F0-9-]+)", options: .regularExpression) {
            return String(usn[uuidRange])
        }
        return usn
    }

    // MARK: - Device Description Fetch

    /// Fetch and parse UPnP device description XML.
    private func fetchAndParseDeviceDescription(
        locationURL: URL,
        udn: String
    ) async {
        do {
            let parsedDevice = try await DLNADeviceParser.parse(from: locationURL)

            // Convert to RemoteDevice
            let remoteDevice = RemoteDevice.dlna(
                id: parsedDevice.udn,
                name: parsedDevice.friendlyName,
                capabilities: parsedDevice.capabilities,
                controlURL: parsedDevice.avTransportControlURL?.absoluteString ?? "",
                eventSubURL: parsedDevice.avTransportEventSubURL?.absoluteString,
                iconURL: parsedDevice.iconURL?.absoluteString,
                manufacturer: parsedDevice.manufacturer,
                modelName: parsedDevice.modelName,
                baseURL: parsedDevice.baseURL.absoluteString
            )

            // Store and notify on main actor
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.discoveredDevices[udn] = remoteDevice
                self.fetchTasks.removeValue(forKey: udn)
                self.onDeviceFound?(remoteDevice)
            }
        } catch {
            // Failed to parse device description
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.fetchTasks.removeValue(forKey: udn)
            }
        }
    }
}

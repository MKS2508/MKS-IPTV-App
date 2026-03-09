//
//  DLNADebug.swift
//  transmux-cli
//
//  DLNA debug client for testing DLNA playback from the CLI.
//  Discovers DLNA MediaRenderers via SSDP, sends AVTransport SOAP
//  commands, and provides an interactive control session.
//
//  Much simpler than CastDebug.swift — no TLS, no protobuf, no heartbeat.
//  Just HTTP SOAP requests to UPnP control endpoints.
//

import Foundation
import TransmuxCore

// MARK: - SSDP Discovery (DLNA MediaRenderers)

/// Discovers DLNA MediaRenderer devices on the LAN via SSDP multicast.
/// Uses BSD sockets (same pattern as discoverCastDevices in CastDebug.swift).
///
/// Returns an array of parsed DLNADevice objects with resolved control URLs.
func discoverDLNADevices(timeout: Int = 5) async -> [DLNADevice] {
    let multicastAddr = "239.255.255.250"
    let ssdpPort: UInt16 = 1900
    let searchTarget = "urn:schemas-upnp-org:device:MediaRenderer:1"

    // Create UDP socket
    let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard fd >= 0 else {
        dlnaPrint("SSDP", "ERROR: Failed to create socket: \(String(cString: strerror(errno)))")
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
                    dlnaPrint("SSDP", "ERROR: sendto failed: \(String(cString: strerror(errno)))")
                }
            }
        }
    }

    dlnaPrint("SSDP", "Sent M-SEARCH for \(searchTarget), waiting \(timeout)s...")

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
                    dlnaPrint("SSDP", "Found LOCATION: \(value)")
                }
            }
        }
    }

    if locations.isEmpty {
        dlnaPrint("SSDP", "No DLNA MediaRenderers found")
        return []
    }

    // Parse device descriptions from LOCATION URLs
    dlnaPrint("SSDP", "Parsing \(locations.count) device description(s)...")
    var devices: [DLNADevice] = []
    var seenIPs = Set<String>()

    for location in locations {
        guard let url = URL(string: location),
              let host = url.host else { continue }

        // Skip duplicates (same IP)
        if seenIPs.contains(host) { continue }
        seenIPs.insert(host)

        do {
            let device = try await DLNADeviceParser.parse(from: url)
            devices.append(device)
            dlnaPrint("SSDP", "  \(device.friendlyName) (\(device.modelName ?? "?")) at \(device.ip):\(device.port)")
            dlnaPrint("SSDP", "    AVTransport: \(device.avTransportControlURL)")
            if let rc = device.renderingControlURL {
                dlnaPrint("SSDP", "    RenderingControl: \(rc)")
            }
        } catch {
            dlnaPrint("SSDP", "  FAILED to parse \(host): \(error.localizedDescription)")
        }
    }

    return devices
}

// MARK: - Interactive DLNA Session

/// Run an interactive DLNA playback session with a MediaRenderer device.
/// Sends SetAVTransportURI + Play, then enters a command loop for control.
///
/// - Parameters:
///   - device: The DLNA MediaRenderer device
///   - contentURL: URL of the content to play (served by TransmuxServer)
///   - title: Display title for the content
///   - duration: Total content duration (for DIDL-Lite metadata)
///   - verbose: Print extra debug info
func runDLNASession(
    device: DLNADevice,
    contentURL: URL,
    title: String,
    duration: Double,
    verbose: Bool,
    streaming: Bool = false
) async {
    dlnaPrint("DLNA", "Starting session with \(device.friendlyName) at \(device.ip):\(device.port)")
    dlnaPrint("DLNA", "Content URL: \(contentURL)")
    dlnaPrint("DLNA", "AVTransport: \(device.avTransportControlURL)")

    // Build DIDL-Lite metadata
    let metadata = DLNAMetadataBuilder.buildDIDLLite(
        title: title,
        contentURL: contentURL,
        duration: duration,
        streaming: streaming
    )

    if verbose {
        dlnaPrint("DLNA", "DIDL-Lite metadata:\n\(metadata)")
    }

    // Step 1: Stop any current playback
    dlnaPrint("DLNA", "Step 1: Stopping current playback...")
    do {
        let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: 0)
        _ = try await DLNASOAPClient.send(
            action: stopAction.actionName,
            serviceType: .avTransport,
            controlURL: device.avTransportControlURL,
            arguments: stopAction.arguments
        )
        dlnaPrint("DLNA", "Stop OK")
    } catch {
        // Not critical — device may have nothing playing
        dlnaPrint("DLNA", "Stop: \(error.localizedDescription) (non-fatal)")
    }

    // Step 2: SetAVTransportURI
    dlnaPrint("DLNA", "Step 2: SetAVTransportURI...")
    do {
        let setURIAction = DLNASOAPClient.AVTransportAction.setAVTransportURI(
            instanceId: 0,
            uri: contentURL.absoluteString,
            metadata: metadata
        )
        let response = try await DLNASOAPClient.send(
            action: setURIAction.actionName,
            serviceType: .avTransport,
            controlURL: device.avTransportControlURL,
            arguments: setURIAction.arguments
        )
        dlnaPrint("DLNA", "SetAVTransportURI OK")
        if verbose && !response.isEmpty {
            dlnaPrint("DLNA", "Response: \(response)")
        }
    } catch {
        dlnaPrint("DLNA", "ERROR: SetAVTransportURI failed: \(error.localizedDescription)")
        dlnaPrint("DLNA", "Continuing in interactive mode — you can retry with LOAD")
    }

    // Step 3: Play
    dlnaPrint("DLNA", "Step 3: Play...")
    do {
        let playAction = DLNASOAPClient.AVTransportAction.play(instanceId: 0, speed: "1")
        _ = try await DLNASOAPClient.send(
            action: playAction.actionName,
            serviceType: .avTransport,
            controlURL: device.avTransportControlURL,
            arguments: playAction.arguments
        )
        dlnaPrint("DLNA", "Play OK")
    } catch {
        dlnaPrint("DLNA", "ERROR: Play failed: \(error.localizedDescription)")
    }

    // Step 4: Interactive command loop
    print("")
    print("=========================================")
    print("  DLNA Session Active")
    print("  Device: \(device.friendlyName) (\(device.ip):\(device.port))")
    print("  Content: \(contentURL)")
    print("")
    print("  Commands:")
    print("    PLAY           Resume playback")
    print("    PAUSE          Pause playback")
    print("    STOP           Stop media")
    print("    SEEK <seconds> Seek to position")
    print("    STATUS         Get position + transport state")
    print("    VOLUME <0-100> Set volume (if supported)")
    print("    LOAD [url]     (Re)load content")
    print("    QUIT           Exit session")
    print("=========================================")
    print("")

    signal(SIGINT) { _ in
        print("\n[DLNA] Interrupted — exiting")
        exit(0)
    }

    print("dlna> ", terminator: "")
    fflush(stdout)

    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("dlna> ", terminator: "")
            fflush(stdout)
            continue
        }

        let parts = trimmed.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).uppercased()

        switch cmd {
        case "QUIT", "EXIT", "Q":
            dlnaPrint("DLNA", "Stopping playback and exiting...")
            do {
                let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: 0)
                _ = try await DLNASOAPClient.send(
                    action: stopAction.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: stopAction.arguments
                )
            } catch { /* best effort */ }
            return

        case "PLAY":
            do {
                let action = DLNASOAPClient.AVTransportAction.play(instanceId: 0, speed: "1")
                _ = try await DLNASOAPClient.send(
                    action: action.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: action.arguments
                )
                dlnaPrint("DLNA", "PLAY OK")
            } catch {
                dlnaPrint("DLNA", "PLAY FAILED: \(error.localizedDescription)")
            }

        case "PAUSE":
            do {
                let action = DLNASOAPClient.AVTransportAction.pause(instanceId: 0)
                _ = try await DLNASOAPClient.send(
                    action: action.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: action.arguments
                )
                dlnaPrint("DLNA", "PAUSE OK")
            } catch {
                dlnaPrint("DLNA", "PAUSE FAILED: \(error.localizedDescription)")
            }

        case "STOP":
            do {
                let action = DLNASOAPClient.AVTransportAction.stop(instanceId: 0)
                _ = try await DLNASOAPClient.send(
                    action: action.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: action.arguments
                )
                dlnaPrint("DLNA", "STOP OK")
            } catch {
                dlnaPrint("DLNA", "STOP FAILED: \(error.localizedDescription)")
            }

        case "SEEK":
            guard parts.count > 1, let time = Double(parts[1]) else {
                dlnaPrint("DLNA", "Usage: SEEK <seconds>")
                break
            }
            let hhmmss = DLNAMetadataBuilder.formatDuration(time)
            do {
                let action = DLNASOAPClient.AVTransportAction.seek(
                    instanceId: 0,
                    unit: "REL_TIME",
                    target: hhmmss
                )
                _ = try await DLNASOAPClient.send(
                    action: action.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: action.arguments
                )
                dlnaPrint("DLNA", "SEEK to \(hhmmss) (\(String(format: "%.1f", time))s) OK")
            } catch {
                dlnaPrint("DLNA", "SEEK FAILED: \(error.localizedDescription)")
            }

        case "STATUS":
            do {
                let info = try await getDLNAStatus(device: device)
                let posStr = DLNAMetadataBuilder.formatDuration(info.currentTime)
                let durStr = DLNAMetadataBuilder.formatDuration(info.duration)
                dlnaPrint("DLNA", "State: \(info.transportState.rawValue)")
                dlnaPrint("DLNA", "Position: \(posStr) (\(String(format: "%.1f", info.currentTime))s)")
                dlnaPrint("DLNA", "Duration: \(durStr) (\(String(format: "%.1f", info.duration))s)")
                if let uri = info.trackURI {
                    dlnaPrint("DLNA", "TrackURI: \(uri)")
                }
            } catch {
                dlnaPrint("DLNA", "STATUS FAILED: \(error.localizedDescription)")
            }

        case "VOLUME", "VOL":
            guard parts.count > 1, let vol = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                dlnaPrint("DLNA", "Usage: VOLUME <0-100>")
                break
            }
            guard let rcURL = device.renderingControlURL else {
                dlnaPrint("DLNA", "RenderingControl not available on this device")
                break
            }
            do {
                let action = DLNASOAPClient.RenderingControlAction.setVolume(
                    instanceId: 0,
                    channel: "Master",
                    volume: max(0, min(100, vol))
                )
                _ = try await DLNASOAPClient.send(
                    action: action.actionName,
                    serviceType: .renderingControl,
                    controlURL: rcURL,
                    arguments: action.arguments
                )
                dlnaPrint("DLNA", "VOLUME \(vol) OK")
            } catch {
                dlnaPrint("DLNA", "VOLUME FAILED: \(error.localizedDescription)")
            }

        case "LOAD":
            let loadURL: URL
            if parts.count > 1, let customURL = URL(string: String(parts[1])) {
                loadURL = customURL
            } else {
                loadURL = contentURL
            }
            dlnaPrint("DLNA", "Loading \(loadURL)...")
            do {
                // Stop first
                let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: 0)
                _ = try? await DLNASOAPClient.send(
                    action: stopAction.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: stopAction.arguments
                )

                let loadMeta = DLNAMetadataBuilder.buildDIDLLite(
                    title: title,
                    contentURL: loadURL,
                    duration: duration,
                    streaming: streaming
                )
                let setAction = DLNASOAPClient.AVTransportAction.setAVTransportURI(
                    instanceId: 0,
                    uri: loadURL.absoluteString,
                    metadata: loadMeta
                )
                _ = try await DLNASOAPClient.send(
                    action: setAction.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: setAction.arguments
                )

                let playAction = DLNASOAPClient.AVTransportAction.play(instanceId: 0, speed: "1")
                _ = try await DLNASOAPClient.send(
                    action: playAction.actionName,
                    serviceType: .avTransport,
                    controlURL: device.avTransportControlURL,
                    arguments: playAction.arguments
                )
                dlnaPrint("DLNA", "LOAD + PLAY OK")
            } catch {
                dlnaPrint("DLNA", "LOAD FAILED: \(error.localizedDescription)")
            }

        case "HELP", "?":
            print("Commands: PLAY | PAUSE | STOP | SEEK <s> | STATUS | VOLUME <0-100> | LOAD [url] | QUIT")

        default:
            dlnaPrint("DLNA", "Unknown: \(trimmed). Type HELP.")
        }

        print("dlna> ", terminator: "")
        fflush(stdout)
    }

    // stdin closed
    dlnaPrint("DLNA", "stdin closed — stopping playback...")
    do {
        let stopAction = DLNASOAPClient.AVTransportAction.stop(instanceId: 0)
        _ = try await DLNASOAPClient.send(
            action: stopAction.actionName,
            serviceType: .avTransport,
            controlURL: device.avTransportControlURL,
            arguments: stopAction.arguments
        )
    } catch { /* best effort */ }
}

// MARK: - Status Query

/// Get current transport position and state from the DLNA device.
func getDLNAStatus(device: DLNADevice) async throws -> DLNAPositionInfo {
    // GetPositionInfo
    let posAction = DLNASOAPClient.AVTransportAction.getPositionInfo(instanceId: 0)
    let posResponse = try await DLNASOAPClient.send(
        action: posAction.actionName,
        serviceType: .avTransport,
        controlURL: device.avTransportControlURL,
        arguments: posAction.arguments
    )

    // GetTransportInfo (for current state)
    let transAction = DLNASOAPClient.AVTransportAction.getTransportInfo(instanceId: 0)
    let transResponse = try await DLNASOAPClient.send(
        action: transAction.actionName,
        serviceType: .avTransport,
        controlURL: device.avTransportControlURL,
        arguments: transAction.arguments
    )

    let relTime = posResponse["RelTime"] ?? "00:00:00"
    let trackDuration = posResponse["TrackDuration"] ?? "00:00:00"
    let trackURI = posResponse["TrackURI"]
    let currentState = transResponse["CurrentTransportState"] ?? "STOPPED"

    return DLNAPositionInfo(
        currentTime: DLNAMetadataBuilder.parseDuration(relTime),
        duration: DLNAMetadataBuilder.parseDuration(trackDuration),
        trackURI: trackURI,
        transportState: DLNATransportState(rawString: currentState)
    )
}

// MARK: - Direct Device Construction

/// Construct a DLNADevice by fetching the device description from a known IP.
/// Tries common DLNA device description paths.
///
/// - Parameters:
///   - ip: The device's IP address
///   - port: The device's HTTP port (default: 2870 for TELEFUNKEN, but tries common ports)
/// - Returns: Parsed DLNADevice or nil if not reachable
func constructDLNADevice(ip: String, port: UInt16? = nil) async -> DLNADevice? {
    let commonPaths = ["/dmr.xml", "/DeviceDescription.xml", "/description.xml", "/rootDesc.xml"]
    let commonPorts: [UInt16] = port.map { [$0] } ?? [2870, 8008, 49152, 1400, 8080]

    for tryPort in commonPorts {
        for path in commonPaths {
            guard let url = URL(string: "http://\(ip):\(tryPort)\(path)") else { continue }

            dlnaPrint("DLNA", "Trying \(url)...")
            do {
                let device = try await DLNADeviceParser.parse(from: url)
                dlnaPrint("DLNA", "Found: \(device.friendlyName) at \(device.ip):\(device.port)")
                return device
            } catch {
                // Try next combination
                continue
            }
        }
    }

    dlnaPrint("DLNA", "Could not find device description at \(ip)")
    return nil
}

// MARK: - Logging

func dlnaPrint(_ category: String, _ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    print("[\(ts)] [\(category)] \(message)")
    fflush(stdout)
}

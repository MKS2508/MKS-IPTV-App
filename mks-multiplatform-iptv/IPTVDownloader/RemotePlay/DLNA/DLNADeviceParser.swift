//
//  DLNADeviceParser.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - UPnP device description XML parser
//

import Foundation
import IPTVCore

/// Parses UPnP device description XML from the LOCATION URL in SSDP responses.
/// Extracts device info, service control URLs, and icon URLs.
enum DLNADeviceParser {

    // MARK: - Parsed Device

    /// Parsed UPnP device information.
    struct ParsedDevice: Sendable {
        /// Unique Device Name (UDN) - used as device identifier.
        let udn: String

        /// User-friendly device name shown in UI.
        let friendlyName: String

        /// Device manufacturer.
        let manufacturer: String?

        /// Device model name.
        let modelName: String?

        /// Device model description.
        let modelDescription: String?

        /// Base URL for resolving relative URLs.
        let baseURL: URL

        /// AVTransport service control URL.
        let avTransportControlURL: URL?

        /// AVTransport service event subscription URL.
        let avTransportEventSubURL: URL?

        /// RenderingControl service control URL.
        let renderingControlURL: URL?

        /// ConnectionManager service control URL.
        let connectionManagerURL: URL?

        /// Preferred icon URL (largest PNG icon).
        let iconURL: URL?

        /// Whether the device exposes a DIAL service (Google Cast SSDP discovery).
        let hasDIALService: Bool

        /// Device capabilities inferred from available services.
        let capabilities: DeviceCapabilities
    }

    // MARK: - Parsing

    /// Fetch and parse the device description XML from the SSDP LOCATION URL.
    /// - Parameter locationURL: The URL from the SSDP LOCATION header
    /// - Returns: Parsed device information
    /// - Throws: RemotePlayError.deviceDescriptionParseError if parsing fails
    static func parse(from locationURL: URL) async throws -> ParsedDevice {
        // Fetch device description XML
        let (data, response) = try await URLSession.shared.data(from: locationURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RemotePlayError.deviceDescriptionParseError("HTTP error fetching device description")
        }

        // Parse XML
        let parser = UPnPDeviceXMLParser(baseURL: locationURL)
        guard let device = parser.parse(data) else {
            throw RemotePlayError.deviceDescriptionParseError(parser.lastError ?? "Unknown parsing error")
        }

        return device
    }

    // MARK: - MediaRenderer Probe

    /// Common device description paths where TVs expose their MediaRenderer service.
    /// Many TVs (e.g. TELEFUNKEN) advertise a basic `tvdevice` via SSDP but expose
    /// their full MediaRenderer with AVTransport at a different path/port.
    private static let probePaths = ["/dmr.xml", "/DeviceDescription.xml", "/description.xml", "/rootDesc.xml"]
    private static let probePorts: [Int] = [2870, 8008, 49152, 1400, 8080]

    /// Short-timeout URLSession for probe requests.
    /// URLSession.shared has a 60s default — probing 20 unreachable endpoints
    /// serially would block for up to 20 min and pin the CPU.
    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return URLSession(configuration: config)
    }()

    /// Probe common alternative device description paths on the same IP to find
    /// a MediaRenderer with AVTransport. All candidates are probed in parallel
    /// with a 2-second per-request timeout so the entire scan completes in ~2s
    /// regardless of how many hosts refuse the connection.
    /// - Returns: An upgraded `ParsedDevice` with AVTransport, or `nil` if none found
    static func probeForMediaRenderer(ip: String, ssdpPort: Int) async -> ParsedDevice? {
        // Build the full candidate URL list
        var candidates: [URL] = []
        for port in probePorts where port != ssdpPort {
            for path in probePaths {
                if let url = URL(string: "http://\(ip):\(port)\(path)") {
                    candidates.append(url)
                }
            }
        }
        for path in probePaths {
            if let url = URL(string: "http://\(ip):\(ssdpPort)\(path)") {
                candidates.append(url)
            }
        }

        // Race all candidates in parallel — return on first valid MediaRenderer hit.
        return await withTaskGroup(of: ParsedDevice?.self) { group in
            for url in candidates {
                group.addTask {
                    do {
                        let (data, response) = try await probeSession.data(from: url)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            return nil
                        }
                        let parser = UPnPDeviceXMLParser(baseURL: url)
                        guard let device = parser.parse(data),
                              device.avTransportControlURL != nil else { return nil }
                        MKSLog.dlna.info("Probe HIT: found MediaRenderer at \(url) with AVTransport")
                        return device
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let device = result {
                    group.cancelAll()
                    return device
                }
            }
            MKSLog.dlna.debug("Probe: no MediaRenderer found on \(ip)")
            return nil
        }
    }

    /// Convert parsed device to RemoteDevice struct.
    /// - Parameter parsed: Parsed device information
    /// - Returns: RemoteDevice ready for use in RemotePlayManager
    static func toRemoteDevice(_ parsed: ParsedDevice) -> RemoteDevice {
        let deviceType = inferDeviceType(parsed)

        var metadata: [String: String] = [
            "udn": parsed.udn,
            "baseURL": parsed.baseURL.absoluteString
        ]

        if let controlURL = parsed.avTransportControlURL {
            metadata["controlURL"] = controlURL.absoluteString
        }
        if let eventSubURL = parsed.avTransportEventSubURL {
            metadata["eventSubURL"] = eventSubURL.absoluteString
        }
        if let renderingURL = parsed.renderingControlURL {
            metadata["renderingControlURL"] = renderingURL.absoluteString
        }
        if let iconURL = parsed.iconURL {
            metadata["iconURL"] = iconURL.absoluteString
        }
        if let manufacturer = parsed.manufacturer {
            metadata["manufacturer"] = manufacturer
        }
        if let modelName = parsed.modelName {
            metadata["modelName"] = modelName
        }

        return RemoteDevice(
            id: parsed.udn,
            name: parsed.friendlyName,
            type: deviceType,
            capabilities: parsed.capabilities,
            isConnected: false,
            metadata: metadata
        )
    }
    // MARK: - Device Type Inference

    /// Infer a more specific device type from manufacturer and model strings.
    /// - Has AVTransport → DLNA family (check manufacturer for specific type)
    /// - No AVTransport + has DIAL service → Chromecast (Cast V2 over TLS port 8009)
    /// - No AVTransport + no DIAL → basic DLNA with limited capabilities
    private static func inferDeviceType(_ parsed: ParsedDevice) -> DeviceType {
        // No AVTransport: check for DIAL service (Google Cast SSDP discovery component)
        guard parsed.avTransportControlURL != nil else {
            return parsed.hasDIALService ? .chromecast : .dlna
        }

        let manufacturer = (parsed.manufacturer ?? "").lowercased()
        let model = (parsed.modelName ?? "").lowercased()
        let friendlyName = parsed.friendlyName.lowercased()

        // Amazon Fire TV
        if manufacturer.contains("amazon") || model.contains("fire") || friendlyName.contains("fire tv") {
            return .fireTV
        }

        // Android TV (generic)
        if manufacturer.contains("google") && (model.contains("android") || model.contains("chromecast")) {
            return .androidTV
        }

        // Known Smart TV brands
        let smartTVBrands = [
            "samsung", "lg", "sony", "philips", "hisense", "tcl", "telefunken",
            "panasonic", "toshiba", "sharp", "vizio", "grundig", "thomson"
        ]
        if smartTVBrands.contains(where: { manufacturer.contains($0) || friendlyName.contains($0) }) {
            return .smartTV
        }

        return .dlna
    }
}

// MARK: - UPnP XML Parser

/// XML parser delegate for UPnP device description documents.
private final class UPnPDeviceXMLParser: NSObject, XMLParserDelegate {
    private let baseURL: URL

    private var currentElement: String = ""
    private var currentText: String = ""
    private var elementStack: [String] = []

    // Parsed values
    private var udn: String?
    private var friendlyName: String?
    private var manufacturer: String?
    private var modelName: String?
    private var modelDescription: String?
    private var baseURLString: String?

    // Services
    private var currentServiceType: String?
    private var currentControlURL: String?
    private var currentEventSubURL: String?

    // Collected services
    private var services: [(type: String, controlURL: String?, eventSubURL: String?)] = []

    // Icons
    private var currentIconWidth: Int?
    private var currentIconHeight: Int?
    private var currentIconMimetype: String?
    private var currentIconURL: String?
    private var bestIconURL: URL?
    private var bestIconIsPNG: Bool = false
    private var bestIconSize: Int = 0

    // Error tracking
    var lastError: String?

    // Capabilities
    private var capabilities: DeviceCapabilities = []

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(_ data: Data) -> DLNADeviceParser.ParsedDevice? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        // Process namespaces so we get the localName without prefixes
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            lastError = "XML parsing failed"
            MKSLog.dlna.error("XML parsing failed, raw data length: \(data.count)")
            return nil
        }

        guard let udn, let friendlyName else {
            lastError = "Missing required fields: udn or friendlyName"
            return nil
        }

        // Resolve base URL
        let resolvedBaseURL: URL
        if let base = baseURLString, let url = URL(string: base) {
            resolvedBaseURL = url
        } else {
            resolvedBaseURL = baseURL
        }

        // Find known services
        let avTransport = services.first { $0.type.contains("AVTransport") }
        let renderingControl = services.first { $0.type.contains("RenderingControl") }
        let connectionManager = services.first { $0.type.contains("ConnectionManager") }
        let hasDIAL = services.contains { $0.type.contains("dial-multiscreen") || $0.type.contains("dial:") }

        MKSLog.dlna.debug("Device: \(friendlyName ?? "?")")
        MKSLog.dlna.debug("Base URL: \(resolvedBaseURL.absoluteString)")
        MKSLog.dlna.debug("Services found: \(services.count)")
        for svc in services {
            MKSLog.dlna.debug("  type=\(svc.type) controlURL=\(svc.controlURL ?? "nil") eventSubURL=\(svc.eventSubURL ?? "nil")")
        }
        if services.isEmpty {
            // Dump first 2000 chars of raw XML for debugging
            let rawXML = String(data: data, encoding: .utf8) ?? "<binary data>"
            MKSLog.dlna.warning("WARNING: 0 services parsed! Raw XML (first 2000 chars):")
            MKSLog.dlna.warning(String(rawXML.prefix(2000)))
        }
        MKSLog.dlna.debug("AVTransport: \(avTransport != nil ? "found" : "MISSING")")
        if let ctrl = avTransport?.controlURL {
            let resolved = resolveURL(ctrl, base: resolvedBaseURL)
            MKSLog.dlna.debug("AVTransport controlURL raw='\(ctrl)' resolved=\(resolved?.absoluteString ?? "nil")")
        } else if avTransport != nil {
            MKSLog.dlna.warning("WARNING: AVTransport found but controlURL is nil!")
        }

        // Build capabilities based on available services
        var caps: DeviceCapabilities = [.video, .audio]
        if avTransport != nil {
            caps.insert(.seeking)
            caps.insert(.pause)
        }
        if renderingControl != nil {
            caps.insert(.volumeControl)
        }

        return DLNADeviceParser.ParsedDevice(
            udn: udn,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            modelDescription: modelDescription,
            baseURL: resolvedBaseURL,
            avTransportControlURL: resolveURL(avTransport?.controlURL, base: resolvedBaseURL),
            avTransportEventSubURL: resolveURL(avTransport?.eventSubURL, base: resolvedBaseURL),
            renderingControlURL: resolveURL(renderingControl?.controlURL, base: resolvedBaseURL),
            connectionManagerURL: resolveURL(connectionManager?.controlURL, base: resolvedBaseURL),
            iconURL: bestIconURL,
            hasDIALService: hasDIAL,
            capabilities: caps
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        // Reset service parsing state when entering a new service
        if elementName == "service" {
            currentServiceType = nil
            currentControlURL = nil
            currentEventSubURL = nil
        }

        // Reset icon parsing state when entering a new icon
        if elementName == "icon" {
            currentIconWidth = nil
            currentIconHeight = nil
            currentIconMimetype = nil
            currentIconURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        elementStack.removeLast()

        switch elementName {
        // Device info
        case "UDN":
            udn = trimmedText
        case "friendlyName":
            friendlyName = trimmedText
        case "manufacturer":
            manufacturer = trimmedText
        case "modelName":
            modelName = trimmedText
        case "modelDescription":
            modelDescription = trimmedText
        case "URLBase":
            baseURLString = trimmedText

        // Service info
        case "serviceType":
            currentServiceType = trimmedText
        case "controlURL":
            currentControlURL = trimmedText
        case "eventSubURL":
            currentEventSubURL = trimmedText

        // Service complete
        case "service":
            if let type = currentServiceType {
                services.append((type: type, controlURL: currentControlURL, eventSubURL: currentEventSubURL))
            }

        // Icon info
        case "width":
            currentIconWidth = Int(trimmedText)
        case "height":
            currentIconHeight = Int(trimmedText)
        case "mimetype":
            currentIconMimetype = trimmedText
        case "url":
            currentIconURL = trimmedText

        // Icon complete - check if this is the best icon
        case "icon":
            if let url = currentIconURL,
               let mimetype = currentIconMimetype,
               mimetype.contains("png") || mimetype.contains("jpeg") || mimetype.contains("jpg") {
                // Prefer PNG, prefer larger icons
                let isPNG = mimetype.contains("png")
                let size = (currentIconWidth ?? 0) * (currentIconHeight ?? 0)

                if let resolvedURL = resolveURL(url, base: baseURL) {
                    if bestIconURL == nil {
                        // First valid icon
                        bestIconURL = resolvedURL
                        bestIconIsPNG = isPNG
                        bestIconSize = size
                    } else if isPNG && !bestIconIsPNG {
                        // Prefer PNG over JPEG
                        bestIconURL = resolvedURL
                        bestIconIsPNG = isPNG
                        bestIconSize = size
                    } else if isPNG == bestIconIsPNG && size > bestIconSize {
                        // Same format, prefer larger
                        bestIconURL = resolvedURL
                        bestIconSize = size
                    }
                }
            }

        default:
            break
        }

        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        lastError = parseError.localizedDescription
    }

    // MARK: - URL Resolution

    /// Resolve a potentially relative URL against the base URL.
    private func resolveURL(_ path: String?, base: URL) -> URL? {
        guard let path, !path.isEmpty else { return nil }

        // Already absolute URL
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }

        // Relative URL
        return URL(string: path, relativeTo: base)
    }
}

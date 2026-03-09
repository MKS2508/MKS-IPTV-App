//
//  DLNADeviceParser.swift
//  TransmuxCore
//
//  Parses UPnP device description XML to extract DLNADevice info.
//  Fetches the LOCATION URL from SSDP and parses the XML for
//  device name, services (AVTransport, RenderingControl), and control URLs.
//
//  Ported from mks-multiplatform-iptv RemotePlay/DLNA/DLNADeviceParser.swift,
//  outputting DLNADevice directly instead of RemoteDevice.
//

import Foundation

/// Parses UPnP device description XML from the LOCATION URL in SSDP responses.
/// Extracts device info and service control URLs, producing a DLNADevice.
public enum DLNADeviceParser {

    // MARK: - Parsing

    /// Fetch and parse the device description XML from the SSDP LOCATION URL.
    /// - Parameter locationURL: The URL from the SSDP LOCATION header
    /// - Returns: Parsed DLNADevice with resolved control URLs
    /// - Throws: DLNAError.parseError if parsing fails
    public static func parse(from locationURL: URL) async throws -> DLNADevice {
        // Fetch device description XML
        let (data, response) = try await URLSession.shared.data(from: locationURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DLNAError.parseError("HTTP error fetching device description from \(locationURL)")
        }

        // Parse XML
        let parser = UPnPDeviceXMLParser(baseURL: locationURL)
        guard let device = parser.parse(data) else {
            throw DLNAError.parseError(parser.lastError ?? "Unknown parsing error")
        }

        return device
    }
}

// MARK: - UPnP XML Parser

/// XML parser delegate for UPnP device description documents.
/// Produces a DLNADevice with resolved AVTransport and RenderingControl URLs.
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
    private var baseURLString: String?

    // Services
    private var currentServiceType: String?
    private var currentControlURL: String?
    private var currentEventSubURL: String?

    // Collected services
    private var services: [(type: String, controlURL: String?, eventSubURL: String?)] = []

    // Error tracking
    var lastError: String?

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(_ data: Data) -> DLNADevice? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            lastError = "XML parsing failed"
            TransmuxLog.log("DLNA XML parsing failed, data length: \(data.count)", tag: "DLNAParser", level: .error)
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

        // Find AVTransport service
        let avTransport = services.first { $0.type.contains("AVTransport") }
        let renderingControl = services.first { $0.type.contains("RenderingControl") }

        TransmuxLog.log("Device: \(friendlyName)", tag: "DLNAParser")
        TransmuxLog.log("Base URL: \(resolvedBaseURL.absoluteString)", tag: "DLNAParser")
        TransmuxLog.log("Services found: \(services.count)", tag: "DLNAParser")
        for svc in services {
            TransmuxLog.log("  type=\(svc.type) controlURL=\(svc.controlURL ?? "nil")", tag: "DLNAParser")
        }

        // AVTransport is required for playback
        guard let avTransportControlURL = resolveURL(avTransport?.controlURL, base: resolvedBaseURL) else {
            lastError = "No AVTransport controlURL found"
            TransmuxLog.log("AVTransport: MISSING (device not usable for playback)", tag: "DLNAParser", level: .warn)
            return nil
        }

        // Extract IP and port from the base URL
        let ip = resolvedBaseURL.host ?? baseURL.host ?? "unknown"
        let port = UInt16(resolvedBaseURL.port ?? baseURL.port ?? 80)

        TransmuxLog.log("AVTransport controlURL: \(avTransportControlURL.absoluteString)", tag: "DLNAParser")

        return DLNADevice(
            udn: udn,
            friendlyName: friendlyName,
            manufacturer: manufacturer,
            modelName: modelName,
            ip: ip,
            port: port,
            avTransportControlURL: avTransportControlURL,
            renderingControlURL: resolveURL(renderingControl?.controlURL, base: resolvedBaseURL)
        )
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        elementStack.append(elementName)

        if elementName == "service" {
            currentServiceType = nil
            currentControlURL = nil
            currentEventSubURL = nil
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

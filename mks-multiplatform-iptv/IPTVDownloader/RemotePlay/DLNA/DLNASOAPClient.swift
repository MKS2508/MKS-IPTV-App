//
//  DLNASOAPClient.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - SOAP request/response for DLNA AVTransport
//

import Foundation

/// Sends SOAP requests to DLNA/UPnP control endpoints and parses responses.
/// Handles AVTransport:1 and RenderingControl:1 service actions.
enum DLNASOAPClient {

    // MARK: - Service Types

    /// UPnP service types supported by this client.
    enum ServiceType: String, Sendable {
        case avTransport = "urn:schemas-upnp-org:service:AVTransport:1"
        case renderingControl = "urn:schemas-upnp-org:service:RenderingControl:1"
        case connectionManager = "urn:schemas-upnp-org:service:ConnectionManager:1"

        /// SOAP action namespace prefix.
        var soapPrefix: String {
            rawValue
        }
    }

    // MARK: - SOAP Request

    /// Send a SOAP action and return the parsed response body.
    /// - Parameters:
    ///   - action: The UPnP action name (e.g., "Play", "Pause", "Seek")
    ///   - serviceType: The UPnP service type
    ///   - controlURL: The device's control endpoint URL
    ///   - arguments: Action arguments as name-value pairs
    ///   - timeout: Request timeout in seconds (default: 10)
    /// - Returns: Parsed response as dictionary of element values
    /// - Throws: RemotePlayError.soapError if the device returns an error
    static func send(
        action: String,
        serviceType: ServiceType,
        controlURL: URL,
        arguments: [(name: String, value: String)] = [],
        timeout: TimeInterval = 10
    ) async throws -> [String: String] {
        // Build SOAP envelope
        let envelope = buildEnvelope(
            action: action,
            serviceType: serviceType,
            arguments: arguments
        )

        // Create request
        var request = URLRequest(url: controlURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = envelope.data(using: .utf8)
        request.setValue(
            "\(serviceType.soapPrefix)#\(action)",
            forHTTPHeaderField: "SOAPAction"
        )
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")

        // Send request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemotePlayError.transportError("Invalid HTTP response")
        }

        // Parse response
        let parsedResponse = try parseResponse(data)

        // Check for UPnP error
        if let errorCode = parsedResponse["errorCode"],
           let code = Int(errorCode) {
            let errorDescription = parsedResponse["errorDescription"] ?? "Unknown error"
            throw RemotePlayError.soapError(code, errorDescription)
        }

        // Check HTTP status for non-200 responses
        if httpResponse.statusCode != 200 {
            throw RemotePlayError.transportError("HTTP \(httpResponse.statusCode)")
        }

        return parsedResponse
    }

    // MARK: - Envelope Building

    /// Build SOAP envelope XML for UPnP action.
    private static func buildEnvelope(
        action: String,
        serviceType: ServiceType,
        arguments: [(name: String, value: String)]
    ) -> String {
        let argsXML = arguments.map { arg in
            "<\(arg.name)>\(xmlEscape(arg.value))</\(arg.name)>"
        }.joined()

        return """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:\(action) xmlns:u="\(serviceType.soapPrefix)">
              \(argsXML)
            </u:\(action)>
          </s:Body>
        </s:Envelope>
        """
    }

    // MARK: - Response Parsing

    /// Parse SOAP response XML to extract element values.
    /// Handles both success responses and UPnP fault responses.
    private static func parseResponse(_ data: Data) throws -> [String: String] {
        let parser = SOAPResponseParser()
        try parser.parse(data)
        return parser.values
    }

    // MARK: - Helpers

    /// XML-escape a string for safe embedding in XML.
    static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - SOAP Response Parser

/// XML parser delegate for extracting values from SOAP responses.
private final class SOAPResponseParser: NSObject, XMLParserDelegate {
    private(set) var values: [String: String] = [:]
    private var currentElement: String = ""
    private var currentValue: String = ""
    private var isInFault = false
    private var isInBody = false

    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw RemotePlayError.transportError("Failed to parse SOAP response")
        }
    }

    // MARK: - XMLParserDelegate

    func parserDidStartDocument(_ parser: XMLParser) {
        values.removeAll()
        isInFault = false
        isInBody = false
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentValue = ""

        // Track if we're in a fault response
        if elementName == "Fault" {
            isInFault = true
        }

        // Track if we're in the Body
        if elementName == "Body" {
            isInBody = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmedValue = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only store non-empty values
        if !trimmedValue.isEmpty && elementName != "Envelope" && elementName != "Body" {
            // Map common response elements
            let key = mapElementName(elementName)
            values[key] = trimmedValue
        }

        currentElement = ""
        currentValue = ""

        if elementName == "Body" {
            isInBody = false
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Error will be caught by parse() returning false
    }

    // MARK: - Element Name Mapping

    /// Map XML element names to simplified keys.
    private func mapElementName(_ name: String) -> String {
        // Handle namespace-prefixed elements
        let localName = name.components(separatedBy: ":").last ?? name

        // Map known UPnP error elements
        switch localName {
        case "errorCode":
            return "errorCode"
        case "errorDescription":
            return "errorDescription"
        case "detail":
            return "errorDescription"  // Some devices use detail for error message
        default:
            return localName
        }
    }
}

// MARK: - Common SOAP Actions

extension DLNASOAPClient {

    /// AVTransport action arguments and response keys.
    enum AVTransportAction {
        case setAVTransportURI(instanceId: Int, uri: String, metadata: String?)
        case play(instanceId: Int, speed: String)
        case pause(instanceId: Int)
        case stop(instanceId: Int)
        case seek(instanceId: Int, unit: String, target: String)
        case next(instanceId: Int)
        case previous(instanceId: Int)
        case getPositionInfo(instanceId: Int)
        case getTransportInfo(instanceId: Int)
        case getMediaInfo(instanceId: Int)

        var actionName: String {
            switch self {
            case .setAVTransportURI: return "SetAVTransportURI"
            case .play: return "Play"
            case .pause: return "Pause"
            case .stop: return "Stop"
            case .seek: return "Seek"
            case .next: return "Next"
            case .previous: return "Previous"
            case .getPositionInfo: return "GetPositionInfo"
            case .getTransportInfo: return "GetTransportInfo"
            case .getMediaInfo: return "GetMediaInfo"
            }
        }

        var arguments: [(name: String, value: String)] {
            switch self {
            case .setAVTransportURI(let instanceId, let uri, let metadata):
                return [
                    ("InstanceID", String(instanceId)),
                    ("CurrentURI", uri),
                    ("CurrentURIMetaData", metadata ?? "")
                ]
            case .play(let instanceId, let speed):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Speed", speed)
                ]
            case .pause(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .stop(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .seek(let instanceId, let unit, let target):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Unit", unit),
                    ("Target", target)
                ]
            case .next(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .previous(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .getPositionInfo(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .getTransportInfo(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            case .getMediaInfo(let instanceId):
                return [
                    ("InstanceID", String(instanceId))
                ]
            }
        }
    }

    /// RenderingControl action arguments.
    enum RenderingControlAction {
        case setVolume(instanceId: Int, channel: String, volume: Int)
        case getVolume(instanceId: Int, channel: String)
        case setMute(instanceId: Int, channel: String, mute: Bool)
        case getMute(instanceId: Int, channel: String)

        var actionName: String {
            switch self {
            case .setVolume: return "SetVolume"
            case .getVolume: return "GetVolume"
            case .setMute: return "SetMute"
            case .getMute: return "GetMute"
            }
        }

        var arguments: [(name: String, value: String)] {
            switch self {
            case .setVolume(let instanceId, let channel, let volume):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Channel", channel),
                    ("DesiredVolume", String(volume))
                ]
            case .getVolume(let instanceId, let channel):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Channel", channel)
                ]
            case .setMute(let instanceId, let channel, let mute):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Channel", channel),
                    ("DesiredMute", mute ? "1" : "0")
                ]
            case .getMute(let instanceId, let channel):
                return [
                    ("InstanceID", String(instanceId)),
                    ("Channel", channel)
                ]
            }
        }
    }
}

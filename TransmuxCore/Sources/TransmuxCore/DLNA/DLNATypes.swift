//
//  DLNATypes.swift
//  TransmuxCore
//
//  Shared DLNA/UPnP types for TransmuxCore DLNA support.
//  Used by both the library (DLNASOAPClient, DLNADeviceParser) and CLI (DLNADebug).
//

import Foundation

// MARK: - DLNADevice

/// Parsed DLNA MediaRenderer device with resolved control URLs.
/// Created by DLNADeviceParser from UPnP device description XML.
public struct DLNADevice: Sendable {
    /// Unique Device Name (UDN) from the UPnP device description.
    public let udn: String

    /// User-friendly device name shown in UI.
    public let friendlyName: String

    /// Device manufacturer (e.g. "TELEFUNKEN").
    public let manufacturer: String?

    /// Device model name.
    public let modelName: String?

    /// Device IP address.
    public let ip: String

    /// Device HTTP port (e.g. 2870).
    public let port: UInt16

    /// AVTransport:1 service control URL (required for playback).
    public let avTransportControlURL: URL

    /// RenderingControl:1 service control URL (optional, for volume).
    public let renderingControlURL: URL?

    public init(
        udn: String,
        friendlyName: String,
        manufacturer: String?,
        modelName: String?,
        ip: String,
        port: UInt16,
        avTransportControlURL: URL,
        renderingControlURL: URL?
    ) {
        self.udn = udn
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.ip = ip
        self.port = port
        self.avTransportControlURL = avTransportControlURL
        self.renderingControlURL = renderingControlURL
    }
}

// MARK: - DLNAPositionInfo

/// Position and transport state from GetPositionInfo + GetTransportInfo responses.
public struct DLNAPositionInfo: Sendable {
    /// Current playback position in seconds.
    public let currentTime: Double

    /// Total content duration in seconds.
    public let duration: Double

    /// Currently playing URI (from GetPositionInfo TrackURI).
    public let trackURI: String?

    /// Current transport state (PLAYING, PAUSED, STOPPED, etc.).
    public let transportState: DLNATransportState

    public init(currentTime: Double, duration: Double, trackURI: String?, transportState: DLNATransportState) {
        self.currentTime = currentTime
        self.duration = duration
        self.trackURI = trackURI
        self.transportState = transportState
    }
}

// MARK: - DLNATransportState

/// DLNA AVTransport transport state values.
public enum DLNATransportState: String, Sendable {
    case stopped = "STOPPED"
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case transitioning = "TRANSITIONING"
    case noMedia = "NO_MEDIA_PRESENT"

    /// Initialize from a raw string, defaulting to `.stopped` for unknown values.
    public init(rawString: String) {
        self = DLNATransportState(rawValue: rawString) ?? .stopped
    }
}

// MARK: - DLNAError

/// Errors specific to DLNA/UPnP operations.
public enum DLNAError: LocalizedError, Sendable {
    /// SOAP fault returned by the device (UPnP error code + description).
    case soapFault(code: Int, description: String)

    /// HTTP-level error from the device.
    case httpError(statusCode: Int)

    /// Failed to parse XML response or device description.
    case parseError(String)

    /// Device is unreachable or connection failed.
    case deviceUnreachable(String)

    public var errorDescription: String? {
        switch self {
        case .soapFault(let code, let desc):
            return "DLNA SOAP fault (\(code)): \(desc)"
        case .httpError(let status):
            return "DLNA HTTP error: \(status)"
        case .parseError(let msg):
            return "DLNA parse error: \(msg)"
        case .deviceUnreachable(let msg):
            return "DLNA device unreachable: \(msg)"
        }
    }
}

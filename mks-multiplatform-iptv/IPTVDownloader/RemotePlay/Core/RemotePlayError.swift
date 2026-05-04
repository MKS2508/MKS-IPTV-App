//
//  RemotePlayError.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - DLNA/Cast error handling
//

import Foundation
import IPTVCore

/// Errors that can occur during remote playback operations.
/// Covers discovery, connection, transport control, and handoff scenarios.
enum RemotePlayError: LocalizedError, Equatable, Sendable {
    /// SSDP discovery failed to start or receive responses.
    case discoveryFailed(String)

    /// Connection to device failed.
    case connectionFailed(String)

    /// Connection timed out before completing.
    case connectionTimeout

    /// Device was not found in available devices list.
    case deviceNotFound

    /// Device disconnected unexpectedly during playback.
    case deviceDisconnected

    /// UPnP SOAP error with code and description.
    case soapError(Int, String)

    /// Transport control operation failed.
    case transportError(String)

    /// No local player available for handoff.
    case noLocalPlayer

    /// No active transmux session available.
    case noActiveSession

    /// Content format not supported by remote device.
    case unsupportedFormat

    /// Network is unavailable for discovery or streaming.
    case networkUnavailable

    /// Failed to parse device description XML.
    case deviceDescriptionParseError(String)

    /// Failed to build DIDL-Lite metadata.
    case metadataBuildError(String)

    /// Unknown or unexpected error.
    case unknown(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .discoveryFailed(let reason):
            return "Discovery failed: \(reason)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionTimeout:
            return "Connection timed out"
        case .deviceNotFound:
            return "Device not found"
        case .deviceDisconnected:
            return "Device disconnected"
        case .soapError(let code, let description):
            return "UPnP error \(code): \(description)"
        case .transportError(let reason):
            return "Transport error: \(reason)"
        case .noLocalPlayer:
            return "No local player available"
        case .noActiveSession:
            return "No active transmux session"
        case .unsupportedFormat:
            return "Format not supported for remote playback"
        case .networkUnavailable:
            return "Network unavailable"
        case .deviceDescriptionParseError(let reason):
            return "Failed to parse device description: \(reason)"
        case .metadataBuildError(let reason):
            return "Failed to build metadata: \(reason)"
        case .unknown(let description):
            return description
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .discoveryFailed:
            return "Make sure you're connected to the same WiFi network as your TV."
        case .connectionFailed, .connectionTimeout:
            return "Try restarting your TV or checking your network connection."
        case .deviceNotFound:
            return "The device may have been turned off or disconnected from the network."
        case .deviceDisconnected:
            return "Try reconnecting to the device."
        case .soapError:
            return "The device may not support this operation."
        case .noLocalPlayer:
            return "Start playback locally first, then try casting."
        case .noActiveSession:
            return "Wait for content to finish loading."
        case .unsupportedFormat:
            return "Try a different video format or play locally."
        case .networkUnavailable:
            return "Check your network connection."
        case .deviceDescriptionParseError:
            return "The device may not be fully DLNA-compatible."
        case .metadataBuildError, .transportError:
            return "Try restarting the app or the device."
        case .unknown:
            return "An unexpected error occurred."
        }
    }

    // MARK: - Equatable

    static func == (lhs: RemotePlayError, rhs: RemotePlayError) -> Bool {
        switch (lhs, rhs) {
        case (.discoveryFailed(let a), .discoveryFailed(let b)):
            return a == b
        case (.connectionFailed(let a), .connectionFailed(let b)):
            return a == b
        case (.connectionTimeout, .connectionTimeout):
            return true
        case (.deviceNotFound, .deviceNotFound):
            return true
        case (.deviceDisconnected, .deviceDisconnected):
            return true
        case (.soapError(let c1, let d1), .soapError(let c2, let d2)):
            return c1 == c2 && d1 == d2
        case (.transportError(let a), .transportError(let b)):
            return a == b
        case (.noLocalPlayer, .noLocalPlayer):
            return true
        case (.noActiveSession, .noActiveSession):
            return true
        case (.unsupportedFormat, .unsupportedFormat):
            return true
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.deviceDescriptionParseError(let a), .deviceDescriptionParseError(let b)):
            return a == b
        case (.metadataBuildError(let a), .metadataBuildError(let b)):
            return a == b
        case (.unknown(let a), .unknown(let b)):
            return a == b
        default:
            return false
        }
    }
}

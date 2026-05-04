//
//  RemotePlaybackState.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - State machine for remote playback lifecycle
//

import Foundation
import IPTVCore

/// State machine representing the lifecycle of remote playback.
/// Used by RemotePlayManager to track and expose current state to UI.
enum RemotePlaybackState: Equatable, Sendable {
    /// No active remote playback, no device connected.
    case idle

    /// Currently searching for devices via SSDP/Cast discovery.
    case discovering

    /// Attempting to connect to a specific device.
    case connecting(deviceId: String)

    /// Connected to device but not playing content.
    case connected(deviceId: String)

    /// Loading content on the remote device.
    case loading

    /// Content is actively playing on remote device.
    case playing

    /// Content is paused on remote device.
    case paused

    /// Content is buffering on remote device.
    case buffering

    /// Seeking to a specific position.
    case seeking(to: Double)

    /// Playback stopped, content cleared from device.
    case stopped

    /// An error occurred during remote playback.
    case error(RemotePlayError)

    // MARK: - Computed Properties

    /// Whether the state represents active playback (playing, paused, buffering, seeking).
    var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering, .seeking:
            return true
        default:
            return false
        }
    }

    /// Whether a device is currently connected (regardless of playback state).
    var isConnected: Bool {
        switch self {
        case .connected, .loading, .playing, .paused, .buffering, .seeking:
            return true
        default:
            return false
        }
    }

    /// The ID of the connected device, if any.
    var connectedDeviceId: String? {
        switch self {
        case .connecting(let deviceId),
             .connected(let deviceId):
            return deviceId
        case .loading, .playing, .paused, .buffering, .seeking:
            // These states imply connection but don't carry deviceId
            // RemotePlayManager tracks the actual device separately
            return nil
        default:
            return nil
        }
    }

    /// Whether currently in a transient/busy state.
    var isBusy: Bool {
        switch self {
        case .discovering, .connecting, .loading, .seeking, .buffering:
            return true
        default:
            return false
        }
    }

    /// Human-readable description of the state for UI display.
    var displayDescription: String {
        switch self {
        case .idle:
            return "Not Connected"
        case .discovering:
            return "Searching for Devices..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .loading:
            return "Loading..."
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .buffering:
            return "Buffering..."
        case .seeking:
            return "Seeking..."
        case .stopped:
            return "Stopped"
        case .error(let error):
            return error.errorDescription ?? "Error"
        }
    }
}

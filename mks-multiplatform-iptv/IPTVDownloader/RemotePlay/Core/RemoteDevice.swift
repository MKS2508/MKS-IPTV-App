//
//  RemoteDevice.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Core data model for remote playback devices
//

import Foundation
import SwiftUI

// MARK: - Transport Protocol

/// Underlying streaming protocol used to send content to a device.
enum TransportProtocol: String, Sendable {
    /// UPnP AVTransport SOAP control.
    case dlna
    /// Google Cast V2 over TLS port 8009.
    case castV2
}

// MARK: - Device Type

/// Classification of remote playback device by protocol and manufacturer.
enum DeviceType: String, Codable, Sendable, CaseIterable {
    case dlna = "dlna"
    case chromecast = "chromecast"
    case googleTV = "google_tv"
    case androidTV = "android_tv"
    case fireTV = "fire_tv"
    case smartTV = "smart_tv"

    /// SF Symbol name for device icon.
    var icon: String {
        switch self {
        case .dlna: "tv"
        case .chromecast: "dot.radiowaves.left.and.right"
        case .googleTV: "play.tv"
        case .androidTV: "tv.and.mediabox"
        case .fireTV: "flame"
        case .smartTV: "tv.inset.filled"
        }
    }

    /// Display name for the protocol/device family.
    var displayName: String {
        switch self {
        case .dlna: "DLNA"
        case .chromecast: "Chromecast"
        case .googleTV: "Google TV"
        case .androidTV: "Android TV"
        case .fireTV: "Fire TV"
        case .smartTV: "Smart TV"
        }
    }

    /// Color for UI highlighting.
    var accentColor: Color {
        switch self {
        case .dlna: .cyan
        case .chromecast: .blue
        case .googleTV: .green
        case .androidTV: .green
        case .fireTV: .orange
        case .smartTV: .purple
        }
    }

    /// Underlying transport protocol for transmux pipeline decisions.
    var transportProtocol: TransportProtocol {
        switch self {
        case .dlna, .smartTV, .fireTV, .androidTV: .dlna
        case .chromecast, .googleTV: .castV2
        }
    }

    /// Whether this device type typically needs audio transcoding (AC3/EAC3/DTS → AAC).
    var needsAudioTranscode: Bool {
        switch self {
        case .chromecast: true
        case .dlna, .smartTV, .fireTV: true
        case .googleTV, .androidTV: false
        }
    }
}

// MARK: - Device Capabilities

/// Capabilities a remote device advertises via UPnP or Cast protocols.
struct DeviceCapabilities: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    /// Device supports video playback.
    static let video = DeviceCapabilities(rawValue: 1 << 0)

    /// Device supports audio playback.
    static let audio = DeviceCapabilities(rawValue: 1 << 1)

    /// Device supports subtitles/captions.
    static let subtitles = DeviceCapabilities(rawValue: 1 << 2)

    /// Device supports seeking within content.
    static let seeking = DeviceCapabilities(rawValue: 1 << 3)

    /// Device supports pause during playback.
    static let pause = DeviceCapabilities(rawValue: 1 << 4)

    /// Device supports volume control.
    static let volumeControl = DeviceCapabilities(rawValue: 1 << 5)

    /// Device supports HLS (HTTP Live Streaming) playback.
    static let hlsPlayback = DeviceCapabilities(rawValue: 1 << 6)

    /// Device supports MP4 container.
    static let mp4Playback = DeviceCapabilities(rawValue: 1 << 7)

    /// Device supports 4K resolution.
    static let fourK = DeviceCapabilities(rawValue: 1 << 8)

    /// Device supports HDR content.
    static let hdr = DeviceCapabilities(rawValue: 1 << 9)

    /// Full capabilities (most common for modern devices).
    static let full: DeviceCapabilities = [
        .video, .audio, .subtitles, .seeking, .pause, .volumeControl,
        .hlsPlayback, .mp4Playback
    ]

    /// Basic capabilities (minimum for playback).
    static let basic: DeviceCapabilities = [.video, .audio]
}

// MARK: - Remote Device

/// Concrete struct representing any discoverable remote playback device.
/// Protocol-specific details are stored in the opaque `metadata` dictionary.
///
/// ## Design Notes
/// - Uses concrete struct instead of protocol with associatedtype for simplicity
/// - `metadata` dictionary stores protocol-specific data:
///   - DLNA: controlURL, eventSubURL, iconURL, manufacturer, modelName, udn
///   - Cast: serviceInstanceName, modelName, deviceId
/// - Sendable conformance ensures Swift 6 concurrency safety
///
struct RemoteDevice: Identifiable, Hashable, Sendable {
    // MARK: - Properties

    /// Unique identifier for the device.
    /// For DLNA: UDN from device description
    /// For Cast: Cast device ID
    let id: String

    /// User-friendly device name.
    let name: String

    /// Protocol/device type classification.
    let type: DeviceType

    /// Capabilities advertised by the device.
    let capabilities: DeviceCapabilities

    /// Whether the device is currently connected.
    var isConnected: Bool

    /// User override for the transport protocol. When set, takes precedence
    /// over the device type's default `transportProtocol`.
    var transportOverride: TransportProtocol?

    /// Protocol-specific payload.
    /// Keys vary by device type:
    /// - DLNA: controlURL, eventSubURL, iconURL, manufacturer, modelName, udn, baseURL
    /// - Cast: serviceInstanceName, modelName, deviceId
    var metadata: [String: String]

    // MARK: - Computed Properties

    /// Manufacturer name, if available.
    var manufacturer: String? {
        metadata["manufacturer"]
    }

    /// Model name, if available.
    var modelName: String? {
        metadata["modelName"]
    }

    /// Icon URL for the device, if available.
    var iconURL: URL? {
        metadata["iconURL"].flatMap { URL(string: $0) }
    }

    /// Effective transport protocol, respecting user override.
    var effectiveTransport: TransportProtocol {
        transportOverride ?? type.transportProtocol
    }

    /// Whether the device has limited DLNA capabilities (no AVTransport control URL).
    var hasLimitedCapabilities: Bool {
        type.transportProtocol == .dlna && !capabilities.contains(.seeking) && !capabilities.contains(.pause)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RemoteDevice, rhs: RemoteDevice) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Factory Methods

    /// Creates a DLNA-family device from parsed UPnP data.
    /// - Parameter deviceType: Specific device classification (defaults to `.dlna`).
    static func dlna(
        id: String,
        name: String,
        capabilities: DeviceCapabilities,
        controlURL: String,
        eventSubURL: String? = nil,
        iconURL: String? = nil,
        manufacturer: String? = nil,
        modelName: String? = nil,
        baseURL: String? = nil,
        deviceType: DeviceType = .dlna
    ) -> RemoteDevice {
        var meta: [String: String] = [
            "controlURL": controlURL,
            "udn": id
        ]
        if let eventSubURL { meta["eventSubURL"] = eventSubURL }
        if let iconURL { meta["iconURL"] = iconURL }
        if let manufacturer { meta["manufacturer"] = manufacturer }
        if let modelName { meta["modelName"] = modelName }
        if let baseURL { meta["baseURL"] = baseURL }

        return RemoteDevice(
            id: id,
            name: name,
            type: deviceType,
            capabilities: capabilities,
            isConnected: false,
            metadata: meta
        )
    }

    /// Creates a Cast device placeholder.
    static func cast(
        id: String,
        name: String,
        modelName: String? = nil
    ) -> RemoteDevice {
        var meta: [String: String] = ["deviceId": id]
        if let modelName { meta["modelName"] = modelName }

        return RemoteDevice(
            id: id,
            name: name,
            type: .chromecast,
            capabilities: .full,
            isConnected: false,
            metadata: meta
        )
    }
}

// MARK: - Device State

/// Represents the current state of a remote device as reported by the device.
struct RemoteDeviceState: Equatable, Sendable {
    /// Current playback state on the device.
    enum TransportState: String, Sendable {
        case playing = "PLAYING"
        case paused = "PAUSED_PLAYBACK"
        case stopped = "STOPPED"
        case transitioning = "TRANSITIONING"
        case noMedia = "NO_MEDIA_PRESENT"
        case unknown = "UNKNOWN"
    }

    /// Current transport state.
    var transportState: TransportState

    /// Current playback position in seconds.
    var currentTime: Double

    /// Total duration in seconds.
    var duration: Double

    /// Current volume (0.0 - 1.0).
    var volume: Float

    /// Whether the device is muted.
    var isMuted: Bool

    /// Whether the device is currently playing.
    var isPlaying: Bool {
        transportState == .playing
    }

    /// Whether the device has media loaded.
    var hasMedia: Bool {
        switch transportState {
        case .playing, .paused, .transitioning:
            return true
        case .stopped, .noMedia, .unknown:
            return false
        }
    }

    static let idle = RemoteDeviceState(
        transportState: .noMedia,
        currentTime: 0,
        duration: 0,
        volume: 1.0,
        isMuted: false
    )
}

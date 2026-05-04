//
//  RemoteDeviceController.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Protocol abstraction for device-specific control
//

import Foundation
import IPTVCore

/// Protocol for device-specific playback control.
/// Each protocol implementation (DLNA, Cast) provides a concrete controller.
///
/// ## Design Notes
/// - NO associatedtype - uses concrete types for simplicity and type erasure avoidance
/// - Uses `any VideoPlayerProtocol` instead of generic constraints
/// - MetadataResult is imported from Core/Metadata module
///
protocol RemoteDeviceController: AnyObject, Sendable {
    // MARK: - Properties

    /// The device this controller manages.
    var device: RemoteDevice { get }

    /// Current playback state reported by the device.
    var playbackState: RemotePlaybackState { get }

    /// Current device state (position, volume, transport state).
    var deviceState: RemoteDeviceState { get }

    // MARK: - Connection Lifecycle

    /// Connect to the device and verify it's ready for commands.
    /// - Throws: RemotePlayError.connectionFailed if connection fails
    func connect() async throws

    /// Disconnect from the device and cleanup resources.
    func disconnect() async

    // MARK: - Content Loading

    /// Load content from URL with metadata and optional start position.
    /// - Parameters:
    ///   - url: Content URL (LAN-accessible, not localhost)
    ///   - metadata: Optional media metadata for device display
    ///   - startPosition: Optional start position in seconds (default: 0)
    ///   - streaming: When true, content is progressive/live (transmuxed MPEG-TS).
    ///     Affects DLNA DIDL-Lite flags (OP=00 no seeking, CI=1 converted).
    /// - Throws: RemotePlayError if loading fails
    func load(url: URL, metadata: MetadataResult?, startPosition: Double, streaming: Bool) async throws

    // MARK: - Transport Control

    /// Resume playback or start playing loaded content.
    /// - Throws: RemotePlayError.transportError if play command fails
    func play() async throws

    /// Pause playback.
    /// - Throws: RemotePlayError.transportError if pause command fails
    func pause() async throws

    /// Seek to a specific time position.
    /// - Parameter time: Target position in seconds
    /// - Throws: RemotePlayError.transportError if seek fails
    func seek(to time: Double) async throws

    /// Stop playback and clear loaded media.
    /// - Throws: RemotePlayError.transportError if stop command fails
    func stop() async throws

    // MARK: - Volume Control

    /// Set volume level.
    /// - Parameter volume: Volume level from 0.0 (muted) to 1.0 (max)
    /// - Throws: RemotePlayError.transportError if volume command fails
    func setVolume(_ volume: Float) async throws

    /// Set mute state.
    /// - Parameter muted: Whether to mute the device
    /// - Throws: RemotePlayError.transportError if mute command fails
    func setMuted(_ muted: Bool) async throws

    // MARK: - State Query

    /// Query current playback position and state from device.
    /// Used for state synchronization between app and device.
    /// - Returns: Tuple of (currentTime, duration, isPlaying)
    /// - Throws: RemotePlayError.transportError if query fails
    func queryPosition() async throws -> (currentTime: Double, duration: Double, isPlaying: Bool)

    /// Query current volume level from device.
    /// - Returns: Current volume (0.0 - 1.0) and mute state
    /// - Throws: RemotePlayError.transportError if query fails
    func queryVolume() async throws -> (volume: Float, isMuted: Bool)
}

// MARK: - Controller Factory Protocol

/// Protocol for creating device-specific controllers.
/// Allows protocol-specific discovery services to create their controllers.
protocol RemoteDeviceControllerFactory: Sendable {
    /// Creates a controller for the given device.
    /// - Parameter device: The device to control
    /// - Returns: A controller instance for the device
    /// - Throws: RemotePlayError if controller creation fails
    func createController(for device: RemoteDevice) throws -> any RemoteDeviceController
}

// MARK: - DLNA Controller Factory

/// Factory for creating DLNA controllers.
struct DLNAControllerFactory: RemoteDeviceControllerFactory {
    /// Creates a DLNAController for the given DLNA device.
    func createController(for device: RemoteDevice) throws -> any RemoteDeviceController {
        try DLNAController(device: device)
    }
}

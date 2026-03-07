# RemotePlay Implementation Plan — MKS-IPTV-App

This plan is organized into 4 phases, with precise file paths, code structures, dependency ordering, and integration points. Each phase builds on the previous one and can be shipped independently.

---

## User Decisions

1. **DLNA first, then Cast SDK immediately after** — architecture must support both from the start
2. **@MainActor @Observable class** for RemotePlayManager (not actor, not ObservableObject)
3. **Concrete RemoteDevice struct with DeviceType enum** (no protocol with associatedtype)
4. **Network.framework for SSDP discovery** (NWConnectionGroup for UDP multicast)

---

## Phase 0: Foundation Types (No Dependencies)

These files define pure data types with zero dependencies beyond Foundation. They must be built first because every other component depends on them.

### Step 0.1: RemoteDevice.swift — Core data model

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Core/RemoteDevice.swift`

```swift
import Foundation

/// Classification of remote playback device by protocol.
enum DeviceType: String, Codable, Sendable, CaseIterable {
    case dlna = "dlna"
    case chromecast = "chromecast"
    case googleTV = "google_tv"

    var icon: String {
        switch self {
        case .dlna: return "tv"
        case .chromecast: return "dot.radiowaves.left.and.right"
        case .googleTV: return "appletv"
        }
    }

    var displayName: String {
        switch self {
        case .dlna: return "DLNA"
        case .chromecast: return "Chromecast"
        case .googleTV: return "Google TV"
        }
    }
}

/// Capabilities a remote device advertises.
struct DeviceCapabilities: OptionSet, Codable, Sendable, Hashable {
    let rawValue: Int

    static let video         = DeviceCapabilities(rawValue: 1 << 0)
    static let audio         = DeviceCapabilities(rawValue: 1 << 1)
    static let subtitles     = DeviceCapabilities(rawValue: 1 << 2)
    static let seeking       = DeviceCapabilities(rawValue: 1 << 3)
    static let pause         = DeviceCapabilities(rawValue: 1 << 4)
    static let volumeControl = DeviceCapabilities(rawValue: 1 << 5)
    static let hlsPlayback   = DeviceCapabilities(rawValue: 1 << 6)

    static let full: DeviceCapabilities = [.video, .audio, .subtitles, .seeking, .pause, .volumeControl, .hlsPlayback]
}

/// Concrete struct representing any discoverable remote playback device.
/// Protocol-specific details are stored in the opaque `metadata` dictionary.
struct RemoteDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: DeviceType
    let capabilities: DeviceCapabilities
    var isConnected: Bool

    /// Protocol-specific payload.
    /// DLNA: controlURL, eventSubURL, iconURL, manufacturer, modelName
    /// Cast: serviceInstanceName, modelName
    var metadata: [String: String]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: RemoteDevice, rhs: RemoteDevice) -> Bool {
        lhs.id == rhs.id
    }
}
```

**Key decisions:**
- Sendable conformance satisfies Swift 6 strict concurrency
- `metadata: [String: String]` is the extensibility point
- `isConnected` is `var` because it gets mutated on connection state changes

### Step 0.2: RemotePlaybackState.swift — State machine

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Core/RemotePlaybackState.swift`

```swift
import Foundation

/// State machine for remote playback lifecycle.
enum RemotePlaybackState: Equatable, Sendable {
    case idle
    case discovering
    case connecting(deviceId: String)
    case connected(deviceId: String)
    case loading
    case playing
    case paused
    case buffering
    case seeking(to: Double)
    case stopped
    case error(RemotePlayError)

    var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering, .seeking: return true
        default: return false
        }
    }
}
```

### Step 0.3: RemotePlayError.swift — Error types

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Core/RemotePlayError.swift`

```swift
import Foundation

enum RemotePlayError: LocalizedError, Equatable, Sendable {
    case discoveryFailed(String)
    case connectionFailed(String)
    case connectionTimeout
    case deviceNotFound
    case deviceDisconnected
    case soapError(Int, String)       // UPnP error code + description
    case transportError(String)
    case noLocalPlayer
    case noActiveSession
    case unsupportedFormat
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .discoveryFailed(let reason): return "Discovery failed: \(reason)"
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .connectionTimeout: return "Connection timed out"
        case .deviceNotFound: return "Device not found"
        case .deviceDisconnected: return "Device disconnected"
        case .soapError(let code, let desc): return "UPnP error \(code): \(desc)"
        case .transportError(let reason): return "Transport error: \(reason)"
        case .noLocalPlayer: return "No local player available"
        case .noActiveSession: return "No active transmux session"
        case .unsupportedFormat: return "Format not supported for remote playback"
        case .networkUnavailable: return "Network unavailable"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.discoveryFailed(let a), .discoveryFailed(let b)): return a == b
        case (.connectionFailed(let a), .connectionFailed(let b)): return a == b
        case (.connectionTimeout, .connectionTimeout): return true
        case (.deviceNotFound, .deviceNotFound): return true
        case (.deviceDisconnected, .deviceDisconnected): return true
        case (.soapError(let c1, let d1), .soapError(let c2, let d2)): return c1 == c2 && d1 == d2
        case (.transportError(let a), .transportError(let b)): return a == b
        case (.noLocalPlayer, .noLocalPlayer): return true
        case (.noActiveSession, .noActiveSession): return true
        case (.unsupportedFormat, .unsupportedFormat): return true
        case (.networkUnavailable, .networkUnavailable): return true
        default: return false
        }
    }
}
```

### Step 0.4: RemoteDeviceController.swift — Protocol for device-specific control

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Core/RemoteDeviceController.swift`

```swift
import Foundation

/// Protocol for device-specific playback control.
/// Each protocol implementation (DLNA, Cast) provides a concrete controller.
/// NO associatedtype — uses concrete RemoteDevice for type erasure.
protocol RemoteDeviceController: AnyObject, Sendable {
    /// The device this controller manages.
    var device: RemoteDevice { get }

    /// Current playback state reported by the device.
    var playbackState: RemotePlaybackState { get }

    /// Connect to the device.
    func connect() async throws

    /// Disconnect from the device.
    func disconnect() async

    /// Load content from URL with metadata and start position.
    func load(url: URL, metadata: MetadataResult?, startPosition: Double) async throws

    /// Resume/play.
    func play() async throws

    /// Pause.
    func pause() async throws

    /// Seek to time in seconds.
    func seek(to time: Double) async throws

    /// Stop playback and clear media.
    func stop() async throws

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Float) async throws

    /// Query current position from device (for state sync).
    func queryPosition() async throws -> (currentTime: Double, duration: Double, isPlaying: Bool)
}
```

---

## Phase 1: DLNA Implementation (Network.framework only)

### Step 1.1: SSDPDiscoveryService.swift — UDP multicast device discovery

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/SSDPDiscoveryService.swift`

Uses NWConnectionGroup for UDP multicast to `239.255.255.250:1900`. Follows the same Network.framework patterns as TransmuxServer.

**Key components:**
- M-SEARCH message targeting `urn:schemas-upnp-org:device:MediaRenderer:1`
- Parse SSDP NOTIFY/RESPONSE headers, extract LOCATION URL
- Trigger DLNADeviceParser to fetch device description XML

### Step 1.2: DLNADeviceParser.swift — UPnP XML device description parser

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/DLNADeviceParser.swift`

Uses XMLParser (Foundation) to extract:
- `<device>` → `<friendlyName>`, `<manufacturer>`, `<modelName>`, `<UDN>`
- `<serviceList>` → AVTransport:1 controlURL, eventSubURL
- `<serviceList>` → RenderingControl:1 controlURL
- `<iconList>` → largest PNG icon URL

### Step 1.3: DLNASOAPClient.swift — SOAP request/response

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/DLNASOAPClient.swift`

Sends SOAP requests to DLNA/UPnP control endpoints via URLSession.

**Supported actions:**
- SetAVTransportURI — load content
- Play, Pause, Stop — transport control
- Seek — REL_TIME target
- GetPositionInfo — query position
- GetTransportInfo — query state
- SetVolume — on RenderingControl:1

### Step 1.4: DLNAMetadataAdapter.swift — MetadataResult to DIDL-Lite conversion

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/DLNAMetadataAdapter.swift`

Converts `MetadataResult` to DIDL-Lite XML. **Critical:** Title formatting must replicate the exact logic from `PlayerMetadataHelper.setNowPlayingInfo` (lines 207-219 of PlayerProtocol.swift):

- Episode: `"ShowTitle - S01E03 - EpisodeTitle"`
- Series: `showTitle`
- Movie: `title`

### Step 1.5: DLNAController.swift — AVTransport SOAP control

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/DLNAController.swift`

Implements `RemoteDeviceController` protocol with position polling every 2 seconds via GetPositionInfo.

### Step 1.6: DLNAEventSubscriber.swift — Optional GENA (placeholder)

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/DLNA/DLNAEventSubscriber.swift`

Deferred — polling via GetPositionInfo is sufficient for Phase 1.

---

## Phase 2: RemotePlayManager Coordinator

### Step 2.1: RemotePlayManager.swift — Main coordinator

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Core/RemotePlayManager.swift`

```swift
import SwiftUI
import TransmuxCore

/// Central coordinator for remote playback across all protocols (DLNA, Cast).
/// NOT a VideoPlayerProtocol — coordinates between local player and remote devices.
@MainActor @Observable
final class RemotePlayManager {

    static let shared = RemotePlayManager()

    // MARK: - Published State (Observable)
    private(set) var availableDevices: [RemoteDevice] = []
    private(set) var connectedDevice: RemoteDevice?
    private(set) var playbackState: RemotePlaybackState = .idle
    private(set) var isDiscovering: Bool = false

    // Mirrored playback state for UI
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering: Bool = false

    var isConnected: Bool { connectedDevice != nil }

    // MARK: - Internal State
    private var ssdpService: SSDPDiscoveryService?
    private var activeController: (any RemoteDeviceController)?
    private var positionPollingTask: Task<Void, Never>?

    // Weak reference to local player for handoff
    weak var localPlayer: AnyObject?
    private var localPlayerRef: (any VideoPlayerProtocol)? {
        localPlayer as? any VideoPlayerProtocol
    }

    private var currentSessionURL: URL?
    private var currentMetadata: MetadataResult?

    private init() {}

    // MARK: - Discovery
    func startDiscovery() { ... }
    func stopDiscovery() { ... }

    // MARK: - Connection
    func connect(to device: RemoteDevice) async throws { ... }
    func disconnect() async { ... }

    // MARK: - Playback
    func castToDevice(
        _ device: RemoteDevice,
        session: TransmuxServer.Session,
        metadata: MetadataResult?,
        localPlayer: any VideoPlayerProtocol
    ) async throws { ... }

    func play() async throws { ... }
    func pause() async throws { ... }
    func seek(to time: Double) async throws { ... }
    func stop() async throws { ... }
    func setVolume(_ volume: Float) async throws { ... }

    // MARK: - Handoff
    func handoffToRemote(...) async throws { ... }
    func handoffToLocal() async throws { ... }

    // MARK: - Controller Factory
    private func createController(for device: RemoteDevice) throws -> any RemoteDeviceController {
        switch device.type {
        case .dlna:
            return try DLNAController(device: device)
        case .chromecast, .googleTV:
            fatalError("Cast controller not yet implemented")
        }
    }
}
```

### Step 2.2: TransmuxServer.swift modifications

**File:** `TransmuxCore/Sources/TransmuxCore/Core/TransmuxServer.swift`

Add public static method to expose LAN IP:

```swift
/// Public accessor for the device's LAN IP address.
public nonisolated static func currentLANIPAddress() -> String? {
    getLANIPAddress()
}
```

Add helper on Session:

```swift
extension TransmuxServer.Session {
    /// URL using the LAN IP instead of localhost, for remote device access.
    public var lanURL: URL? {
        guard let ip = TransmuxServer.currentLANIPAddress() else { return nil }
        var components = URLComponents(url: localURL, resolvingAgainstBaseURL: false)
        components?.host = ip
        return components?.url
    }
}
```

### Step 2.3: FFmpegPlayerImplementation.swift modifications

**File:** `mks-multiplatform-iptv/IPTVDownloader/Core/Player/FFmpegPlayerImplementation.swift`

Add property to expose active session:

```swift
/// The active TransmuxServer session, if transmux is running.
private(set) var transmuxServerSession: TransmuxServer.Session?
```

---

## Phase 3: UI Integration

### Step 3.1: RemotePlayButton.swift — Menu-based device selector

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Views/RemotePlayButton.swift`

Compact menu button with Liquid Glass styling via `adaptiveGlass` modifier. Shows connected device controls and available devices list.

### Step 3.2: DevicePickerSheet.swift — Full modal picker

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Views/DevicePickerSheet.swift`

Full-screen device picker modal with device details and connection status.

### Step 3.3: RemotePlayOverlay.swift — Player overlay controls

**File:** `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Views/RemotePlayOverlay.swift`

Full-screen overlay shown when content is casting. Replaces local video surface with "Casting to..." indicator.

### Step 3.4: MKSPlayerView.swift modifications

**File:** `mks-multiplatform-iptv/IPTVDownloader/Features/Player/MKSPlayerView.swift`

- Add `RemotePlayButton` to overlay stack (fullscreen mode)
- Add `RemotePlayOverlay` when `remotePlay.isConnected`
- Pass `transmuxServerSession` from FFmpegPlayerImplementation

### Step 3.5: MediaDetailSheet.swift modifications

**File:** `mks-multiplatform-iptv/IPTVDownloader/Features/Media/Views/MediaDetailSheet.swift`

Add Cast button to action buttons section.

### Step 3.6: App Entry Point

**File:** `mks-multiplatform-iptv/mks_multiplatform_iptvApp.swift`

Inject `RemotePlayManager.shared` into environment:

```swift
.environment(RemotePlayManager.shared)
```

---

## Phase 4: Cast SDK Placeholder

### Step 4.1: Cast/ directory

**Files:**
- `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Cast/CastController.swift` (placeholder)
- `mks-multiplatform-iptv/IPTVDownloader/RemotePlay/Cast/CastMetadataAdapter.swift` (placeholder)

---

## Implementation Order Summary

```
Phase 0 (Foundation):
├── 0.3 RemotePlayError.swift      (no deps)
├── 0.1 RemoteDevice.swift         (no deps)
├── 0.2 RemotePlaybackState.swift  (depends on 0.3)
└── 0.4 RemoteDeviceController.swift (depends on 0.1, 0.2, MetadataResult)

Phase 1 (DLNA):
├── 1.3 DLNASOAPClient.swift       (no deps beyond Foundation)
├── 1.2 DLNADeviceParser.swift     (depends on 0.1)
├── 1.4 DLNAMetadataAdapter.swift  (depends on MetadataResult)
├── 1.1 SSDPDiscoveryService.swift (depends on 0.1, Network.framework)
├── 1.5 DLNAController.swift       (depends on 0.1, 0.2, 0.4, 1.3, 1.4)
└── 1.6 DLNAEventSubscriber.swift  (placeholder)

Phase 2 (Coordinator):
├── 2.2 TransmuxServer.swift mod   (expose getLANIPAddress)
├── 2.3 FFmpegPlayerImpl.swift mod (expose transmuxServerSession)
└── 2.1 RemotePlayManager.swift    (depends on Phase 0+1)

Phase 3 (UI):
├── 3.1 RemotePlayButton.swift     (depends on 2.1)
├── 3.2 DevicePickerSheet.swift    (depends on 2.1)
├── 3.3 RemotePlayOverlay.swift    (depends on 2.1)
├── 3.4 MKSPlayerView.swift mod    (depends on 3.1, 3.3)
├── 3.5 MediaDetailSheet.swift mod (depends on 3.2)
└── 3.6 App entry point mod        (depends on 2.1)

Phase 4 (Cast placeholder):
└── 4.1 Cast/ placeholders
```

---

## Files Summary

### Files to Create (14 files)

```
IPTVDownloader/RemotePlay/
├── Core/
│   ├── RemotePlayManager.swift
│   ├── RemoteDevice.swift
│   ├── RemotePlaybackState.swift
│   ├── RemoteDeviceController.swift
│   └── RemotePlayError.swift
├── DLNA/
│   ├── SSDPDiscoveryService.swift
│   ├── DLNADeviceParser.swift
│   ├── DLNAController.swift
│   ├── DLNASOAPClient.swift
│   ├── DLNAMetadataAdapter.swift
│   └── DLNAEventSubscriber.swift
├── Cast/
│   ├── CastController.swift
│   └── CastMetadataAdapter.swift
└── Views/
    ├── RemotePlayButton.swift
    ├── DevicePickerSheet.swift
    └── RemotePlayOverlay.swift
```

### Files to Modify (5 files)

| File | Changes |
|------|---------|
| `TransmuxCore/.../TransmuxServer.swift` | Expose `getLANIPAddress()` publicly, add `Session.lanURL` |
| `.../Player/FFmpegPlayerImplementation.swift` | Expose `transmuxServerSession` property |
| `.../Player/MKSPlayerView.swift` | Add RemotePlayButton + RemotePlayOverlay |
| `.../Media/Views/MediaDetailSheet.swift` | Add Cast button to actions |
| `mks_multiplatform_iptvApp.swift` | Inject RemotePlayManager.shared |

---

## Concurrency Safety Notes

All new code must compile under Swift 6 strict concurrency:

| Type | Strategy |
|------|----------|
| RemoteDevice | Sendable (all value types) |
| RemotePlaybackState | Sendable (enum with Sendable associated values) |
| RemotePlayError | Sendable (enum with String associated values) |
| DeviceCapabilities | Sendable (OptionSet with Int rawValue) |
| RemotePlayManager | @MainActor isolation covers all mutable state |
| SSDPDiscoveryService | @MainActor with @unchecked Sendable (NWConnectionGroup callbacks) |
| DLNAController | @unchecked Sendable (async mutation only) |
| DLNASOAPClient | enum with static methods, inherently Sendable |
| DLNAMetadataAdapter | enum with static methods, inherently Sendable |
| DLNADeviceParser | enum with static methods, inherently Sendable |

---

## Testing Strategy

### Phase 0
- Verify Sendable conformance compiles under Swift 6 strict concurrency
- Unit test RemoteDevice hashing/equality
- Unit test DeviceCapabilities bitwise operations
- Unit test RemotePlaybackState transitions

### Phase 1
- Unit test DLNADeviceParser with sample UPnP XML (Samsung, LG, Sony)
- Unit test DLNASOAPClient.buildEnvelope output format
- Unit test DLNAMetadataAdapter.buildDIDLLite with various MetadataResult configurations
- Unit test DLNAMetadataAdapter.formatTitle matches PlayerMetadataHelper.setNowPlayingInfo exactly
- Integration test SSDPDiscoveryService on real network (manual)
- Integration test full DLNA flow with real TV or BubbleUPnP (manual)

### Phase 2
- Unit test RemotePlayManager state transitions
- Unit test handoff flow: local pause, position capture, remote load, position restore
- Unit test TransmuxServer.Session.lanURL computation
- Integration test: full flow from discovery through DLNAController.load() with mock SOAP server

### Phase 3
- Build and run on iOS 26 simulator — verify RemotePlayButton renders with Liquid Glass
- Build and run on macOS 26 — verify button appears in player window
- Build on tvOS 26 — verify no compilation errors
- Manual test: verify device list populates on same LAN as DLNA TV
- Manual test: verify full handoff flow from MediaDetailSheet

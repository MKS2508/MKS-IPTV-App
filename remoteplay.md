# Remote Play - Chromecast & DLNA/UPnP Integration

## Goal

Enable MKS-IPTV to stream transmuxed content to external devices: Chromecast/Google TV, Smart TVs, game consoles, and any DLNA/UPnP compatible renderer. The system must integrate seamlessly with the existing TransmuxServer architecture, reusing the HLS/fMP4 pipeline that already powers AirPlay.

### Core Objectives

1. **Google Cast Integration** - Stream to Chromecast, Google TV, Android TV devices
2. **DLNA/UPnP Support** - Stream to Smart TVs (Samsung, LG, Sony), Xbox, PlayStation, and other UPnP renderers
3. **Unified API** - Single `RemotePlayManager` abstraction that handles device discovery, connection, and playback control
4. **Zero Duplication** - Reuse existing TransmuxServer URLs, no additional transcoding pipeline

### Why This Matters

Currently, AirPlay works because TransmuxServer serves HLS over HTTP using the LAN IP address. The same URLs can be consumed by any device on the network that supports:
- HLS (HTTP Live Streaming) with fMP4 segments
- Standard HTTP range requests
- Basic content discovery

This means **no new transcoding infrastructure is needed** - we just need to implement device discovery and control protocols.

---

## Architecture Overview

### Current State (AirPlay Only)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         MKS-IPTV-App                                │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────────────┐  │
│  │ IPTV Server │───▶│ StreamProxy  │───▶│ TransmuxCore          │  │
│  │ (M3U8/TS)   │    │ (URL proxy)  │    │ (MKV→fMP4 remux)      │  │
│  └─────────────┘    └──────────────┘    └───────────┬───────────┘  │
│                                                     │              │
│                                           ┌─────────▼─────────┐    │
│                                           │   TransmuxServer  │    │
│                                           │   :8100-8199      │    │
│                                           │   (HLS + fMP4)    │    │
│                                           └─────────┬─────────┘    │
│                                                     │              │
│                         ┌───────────────────────────┼──────────┐   │
│                         ▼                           ▼          ▼   │
│                    ┌─────────┐                 ┌─────────┐ ┌─────┐ │
│                    │ AirPlay │                 │ AVPlayer│ │PiP  │ │
│                    │ (Apple) │                 │ (Local) │ │     │ │
│                    └─────────┘                 └─────────┘ └─────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Target State (Multi-Protocol)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         MKS-IPTV-App                                │
│                                                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────────────┐  │
│  │ IPTV Server │───▶│ StreamProxy  │───▶│ TransmuxCore          │  │
│  │ (M3U8/TS)   │    │ (URL proxy)  │    │ (MKV→fMP4 remux)      │  │
│  └─────────────┘    └──────────────┘    └───────────┬───────────┘  │
│                                                     │              │
│                                           ┌─────────▼─────────┐    │
│                                           │   TransmuxServer  │    │
│                                           │   :8100-8199      │    │
│                                           │   (HLS + fMP4)    │    │
│                                           └─────────┬─────────┘    │
│                                                     │              │
│                                           ┌─────────▼─────────┐    │
│                                           │  RemotePlayManager│    │
│                                           │  (Unified API)    │    │
│                                           └─────────┬─────────┘    │
│                                                     │              │
│     ┌───────────────────────────────────────────────┼──────────┐   │
│     │                       │                       │          │   │
│     ▼                       ▼                       ▼          ▼   │
│ ┌───────────┐         ┌───────────┐          ┌──────────┐ ┌─────┐ │
│ │ AirPlay   │         │Google Cast│          │   DLNA   │ │PiP  │ │
│ │ Controller│         │ Controller│          │Controller│ │     │ │
│ └─────┬─────┘         └─────┬─────┘          └────┬─────┘ └─────┘ │
│       │                     │                     │               │
└───────┼─────────────────────┼─────────────────────┼───────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
   ┌─────────┐          ┌───────────┐        ┌─────────────┐
   │ Apple TV│          │Chromecast │        │  Smart TVs  │
   │ AirPlay │          │ Google TV │        │  Xbox/PS    │
   │ devices │          │ Android TV│        │  DLNA Audio │
   └─────────┘          └───────────┘        └─────────────┘
```

---

## Component Design

### 1. RemotePlayManager (Unified API)

```swift
/// Central coordinator for all remote playback protocols.
/// Provides a unified API regardless of the underlying transport.
actor RemotePlayManager: ObservableObject {

    // MARK: - Published State

    @Published private(set) var availableDevices: [RemoteDevice] = []
    @Published private(set) var connectedDevice: RemoteDevice?
    @Published private(set) var playbackState: RemotePlaybackState = .idle

    // MARK: - Device Discovery

    /// Start discovering all supported device types.
    func startDiscovery() async

    /// Stop all discovery operations.
    func stopDiscovery() async

    /// Manually refresh device list.
    func refreshDevices() async

    // MARK: - Connection

    /// Connect to a specific device.
    func connect(to device: RemoteDevice) async throws

    /// Disconnect from current device.
    func disconnect() async

    // MARK: - Playback Control

    /// Load and play content from a TransmuxServer session.
    func play(session: TransmuxServer.Session, metadata: MediaMetadata) async throws

    /// Pause playback.
    func pause() async throws

    /// Resume playback.
    func resume() async throws

    /// Seek to position.
    func seek(to time: TimeInterval) async throws

    /// Stop playback and clear loaded media.
    func stop() async throws

    /// Set volume (0.0 - 1.0).
    func setVolume(_ volume: Float) async throws
}
```

### 2. RemoteDevice Protocol

```swift
/// Abstract representation of a remote playback device.
protocol RemoteDevice: Identifiable, Hashable {
    var id: String { get }
    var name: String { get }
    var type: DeviceType { get }
    var capabilities: DeviceCapabilities { get }
    var isConnected: Bool { get }

    associatedtype Controller: RemoteDeviceController

    func createController() -> Controller
}

enum DeviceType: String, Codable {
    case airPlay = "airplay"
    case chromecast = "chromecast"
    case googleTV = "google_tv"
    case dlnaRenderer = "dlna"
    case samsungTV = "samsung_tv"
    case lgTV = "lg_tv"
    case xbox = "xbox"
    case playStation = "playstation"
    case unknown = "unknown"
}

struct DeviceCapabilities: OptionSet, Codable {
    let rawValue: Int

    static let video = DeviceCapabilities(rawValue: 1 << 0)
    static let audio = DeviceCapabilities(rawValue: 1 << 1)
    static let subtitles = DeviceCapabilities(rawValue: 1 << 2)
    static let seeking = DeviceCapabilities(rawValue: 1 << 3)
    static let pause = DeviceCapabilities(rawValue: 1 << 4)
    static let volumeControl = DeviceCapabilities(rawValue: 1 << 5)
    static let liveStream = DeviceCapabilities(rawValue: 1 << 6)

    static let all: DeviceCapabilities = [.video, .audio, .subtitles, .seeking, .pause, .volumeControl, .liveStream]
}
```

### 3. Protocol Controllers

```swift
/// Controller protocol for device-specific operations.
protocol RemoteDeviceController {
    associatedtype Device: RemoteDevice

    var device: Device { get }
    var playbackState: RemotePlaybackState { get }

    func connect() async throws
    func disconnect() async
    func load(url: URL, metadata: MediaMetadata) async throws
    func play() async throws
    func pause() async throws
    func seek(to time: TimeInterval) async throws
    func stop() async throws
    func setVolume(_ volume: Float) async throws
}
```

---

## Implementation Plan

### Phase 1: Google Cast SDK Integration (Priority: High)

#### 1.1 Dependencies

```ruby
# Podfile or Package.swift
pod 'google-cast-sdk', '~> 4.8'
# or
.target(
    name: "mks-multiplatform-iptv",
    dependencies: [
        .product(name: "GoogleCast", package: "google-cast-sdk")
    ]
)
```

#### 1.2 Core Components

| File | Purpose |
|------|---------|
| `RemotePlay/Cast/CastDevice.swift` | GCKDevice wrapper conforming to RemoteDevice |
| `RemotePlay/Cast/CastController.swift` | GCKSession management, media loading |
| `RemotePlay/Cast/CastDiscoveryService.swift` | GCKDeviceManager wrapper |
| `RemotePlay/Cast/CastMediaManager.swift` | Convert TransmuxSession to GCKMediaInformation |

#### 1.3 Key Implementation Details

```swift
// CastDiscoveryService.swift
actor CastDiscoveryService {
    private var deviceManager: GCKDeviceManager?
    private(set) var discoveredDevices: [CastDevice] = []

    func startDiscovery() {
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)

        GCKCastContext.sharedInstance().discoveryManager.add(self)
        GCKCastContext.sharedInstance().discoveryManager.startDiscovery()
    }
}

// CastController.swift
actor CastController: RemoteDeviceController {
    private var session: GCKCastSession?

    func load(url: URL, metadata: MediaMetadata) async throws {
        let gckMetadata = GCKMediaMetadata()
        gckMetadata.setString(metadata.title, forKey: kGCKMetadataKeyTitle)
        gckMetadata.setString(metadata.subtitle ?? "", forKey: kGCKMetadataKeySubtitle)

        if let posterURL = metadata.posterURL {
            gckMetadata.addImage(GCKImage(url: posterURL, width: 480, height: 720))
        }

        let mediaInfo = GCKMediaInformation(
            contentID: url.absoluteString,
            streamType: .buffered,
            contentType: "application/x-mpegURL",  // HLS
            metadata: gckMetadata,
            streamDuration: metadata.duration,
            mediaTracks: nil,
            textTrackStyle: nil,
            customData: nil
        )

        try await withCheckedThrowingContinuation { continuation in
            session?.remoteMediaClient?.load(mediaInfo) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
```

#### 1.4 UI Components

```swift
// SwiftUI Cast Button
struct CastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.tintColor = .white
        return button
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}

// Device Picker Sheet
struct CastDevicePicker: View {
    @ObservedObject var remotePlayManager: RemotePlayManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(remotePlayManager.availableDevices.filter { $0.type.isChromecast }) { device in
                DeviceRow(device: device) {
                    Task {
                        try? await remotePlayManager.connect(to: device)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Cast to...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

---

### Phase 2: DLNA/UPnP Integration (Priority: Medium)

#### 2.1 Dependencies

```ruby
# Podfile
pod 'CocoaAsyncSocket'  # SSDP discovery
# UPnPX is old ObjC, consider modern Swift implementation
```

#### 2.2 Core Components

| File | Purpose |
|------|---------|
| `RemotePlay/DLNA/DLNADevice.swift` | UPnP MediaRenderer wrapper |
| `RemotePlay/DLNA/DLNAController.swift` | SOAP-based control protocol |
| `RemotePlay/DLNA/DLNADiscoveryService.swift` | SSDP multicast discovery |
| `RemotePlay/DLNA/DLNASOAPClient.swift` | SOAP request/response handling |

#### 2.3 SSDP Discovery

```swift
// DLNADiscoveryService.swift
actor DLNADiscoveryService {
    private var udpSocket: GCDAsyncUdpSocket?
    private(set) var discoveredDevices: [DLNADevice] = []

    private let ssdpAddress = "239.255.255.250"
    private let ssdpPort: UInt16 = 1900

    func startDiscovery() async throws {
        udpSocket = GCDAsyncUdpSocket(delegate: self, delegateQueue: .global())
        try udpSocket?.bind(toPort: 0)
        try udpSocket?.enableBroadcast(true)
        try udpSocket?.beginReceiving()

        // Send M-SEARCH for MediaRenderers
        let searchMessage = """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 3\r
            ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
            USER-AGENT: iOS/17.0 UPnP/1.1 MKS-IPTV/1.0\r\n\r\n
            """

        guard let data = searchMessage.data(using: .utf8) else { return }
        udpSocket?.send(data, toHost: ssdpAddress, port: ssdpPort, withTimeout: 5, tag: 0)

        // Also search for generic MediaServer
        let serverSearch = searchMessage
            .replacingOccurrences(of: "MediaRenderer", with: "MediaServer")
        udpSocket?.send(serverSearch.data(using: .utf8)!, toHost: ssdpAddress, port: ssdpPort, withTimeout: 5, tag: 1)
    }

    private func parseSSDPResponse(_ response: String) -> DLNADevice? {
        // Parse HTTP-like response
        // Extract LOCATION header for device description XML
        // Fetch and parse XML to get control URLs
    }
}
```

#### 2.4 SOAP Control

```swift
// DLNAController.swift
actor DLNAController: RemoteDeviceController {
    let device: DLNADevice
    private var controlURL: URL
    private var eventURL: URL?

    func load(url: URL, metadata: MediaMetadata) async throws {
        // Build DIDL-Lite metadata
        let didl = """
            <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
                       xmlns:dc="http://purl.org/dc/elements/1.1/"
                       xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
                <item id="0" parentID="-1" restricted="1">
                    <dc:title>\(metadata.title)</dc:title>
                    <upnp:class>object.item.videoItem</upnp:class>
                    <res protocolInfo="http-get:*:application/x-mpegURL:*">\(url.absoluteString)</res>
                </item>
            </DIDL-Lite>
            """

        // SetAVTransportURI SOAP action
        let soapBody = """
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                <s:Body>
                    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                        <InstanceID>0</InstanceID>
                        <CurrentURI>\(url.absoluteString)</CurrentURI>
                        <CurrentURIMetaData>\(didl.xmlEscaped)</CurrentURIMetaData>
                    </u:SetAVTransportURI>
                </s:Body>
            </s:Envelope>
            """

        try await sendSOAPAction(body: soapBody, soapAction: "SetAVTransportURI")

        // Start playback
        try await play()
    }

    func play() async throws {
        let soapBody = """
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
                        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
                <s:Body>
                    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                        <InstanceID>0</InstanceID>
                        <Speed>1</Speed>
                    </u:Play>
                </s:Body>
            </s:Envelope>
            """

        try await sendSOAPAction(body: soapBody, soapAction: "Play")
    }

    private func sendSOAPAction(body: String, soapAction: String) async throws {
        var request = URLRequest(url: controlURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(soapAction)\"",
                        forHTTPHeaderField: "SOAPAction")

        let (_, response) = try await URLSession.shared.data(for: request)
        // Parse response for errors
    }
}
```

#### 2.5 DLNA Device Description Parsing

```swift
// DLNADeviceParser.swift
struct DLNADeviceDescription: Codable {
    let device: DeviceInfo

    struct DeviceInfo: Codable {
        let friendlyName: String
        let manufacturer: String
        let modelName: String
        let UDN: String
        let serviceList: ServiceList?
        let iconList: IconList?

        struct ServiceList: Codable {
            let service: [Service]

            struct Service: Codable {
                let serviceType: String
                let serviceId: String
                let controlURL: String
                let eventSubURL: String
                let SCPDURL: String
            }
        }

        struct IconList: Codable {
            let icon: [Icon]

            struct Icon: Codable {
                let mimetype: String
                let width: Int
                let height: Int
                let url: String
            }
        }
    }
}

extension DLNADevice {
    static func parse(from xmlURL: URL) async throws -> DLNADevice {
        let (data, _) = try await URLSession.shared.data(from: xmlURL)

        // Manual XML parsing (XMLDecoder doesn't handle nested structures well)
        let parser = DLNAXMLParser(data: data)
        let description = try parser.parse()

        return DLNADevice(
            id: description.device.UDN,
            name: description.device.friendlyName,
            manufacturer: description.device.manufacturer,
            model: description.device.modelName,
            controlURL: description.device.avTransportControlURL,
            iconURL: description.device.largestIconURL
        )
    }
}
```

---

### Phase 3: Unified UI Integration

#### 3.1 RemotePlayButton Component

```swift
// Views/Components/RemotePlayButton.swift
struct RemotePlayButton: View {
    @StateObject private var remotePlay = RemotePlayManager.shared
    @State private var showDevicePicker = false

    let session: TransmuxServer.Session?
    let metadata: MediaMetadata

    var body: some View {
        Menu {
            if let connected = remotePlay.connectedDevice {
                // Connected device - show controls
                Section(connected.name) {
                    Button(role: .destructive) {
                        Task { await remotePlay.disconnect() }
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }

            Section("Cast to Device") {
                ForEach(remotePlay.availableDevices) { device in
                    Button {
                        Task {
                            try? await remotePlay.connect(to: device)
                            if let session = session {
                                try? await remotePlay.play(session: session, metadata: metadata)
                            }
                        }
                    } label: {
                        Label(device.name, systemImage: device.type.icon)
                    }
                }
            }
        } label: {
            Image(systemName: remotePlay.connectedDevice != nil ? "tv.fill" : "tv")
                .symbolRenderingMode(.hierarchical)
        }
        .task {
            await remotePlay.startDiscovery()
        }
    }
}
```

#### 3.2 Integration with MediaDetailSheet

```swift
// Views/Media/MediaDetailSheet.swift modifications
struct MediaDetailSheet: View {
    // ... existing code ...

    @StateObject private var remotePlay = RemotePlayManager.shared

    var body: some View {
        // ... existing UI ...

        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    // Existing AirPlay button (if any)

                    // New Remote Play button
                    if let session = transmuxSession {
                        RemotePlayButton(
                            session: session,
                            metadata: MediaMetadata(
                                title: movie.title,
                                subtitle: movie.year,
                                posterURL: movie.posterURL,
                                duration: movie.duration
                            )
                        )
                    }

                    // Cast button for Google Cast
                    CastButton()
                        .frame(width: 44, height: 44)
                }
            }
        }
    }
}
```

---

## File Structure

```
mks-multiplatform-iptv/
├── IPTVDownloader/
│   ├── RemotePlay/
│   │   ├── Core/
│   │   │   ├── RemotePlayManager.swift       # Main coordinator
│   │   │   ├── RemoteDevice.swift            # Protocol + base types
│   │   │   ├── RemotePlaybackState.swift     # State machine
│   │   │   └── MediaMetadata.swift           # Content metadata
│   │   │
│   │   ├── Cast/                             # Google Cast implementation
│   │   │   ├── CastDevice.swift
│   │   │   ├── CastController.swift
│   │   │   ├── CastDiscoveryService.swift
│   │   │   └── CastMediaManager.swift
│   │   │
│   │   ├── DLNA/                             # DLNA/UPnP implementation
│   │   │   ├── DLNADevice.swift
│   │   │   ├── DLNAController.swift
│   │   │   ├── DLNADiscoveryService.swift
│   │   │   ├── DLNASOAPClient.swift
│   │   │   ├── DLNADeviceParser.swift
│   │   │   └── DLNAEventSubscriber.swift
│   │   │
│   │   └── Views/                            # UI components
│   │       ├── RemotePlayButton.swift
│   │       ├── DevicePickerSheet.swift
│   │       └── DeviceRow.swift
│   │
│   └── Features/
│       └── Media/
│           └── Views/
│               └── MediaDetailSheet.swift    # Modified to include RemotePlay
```

---

## Dependencies

### Required Frameworks

| Dependency | Version | Purpose | Platform |
|------------|---------|---------|----------|
| `google-cast-sdk` | 4.8+ | Chromecast support | iOS, macOS |
| `CocoaAsyncSocket` | 7.6+ | SSDP/UPnP discovery | All |
| `Network.framework` | Native | HTTP/SOAP communication | All |

### Optional Enhancements

| Dependency | Purpose |
|------------|---------|
| `RxSwift` | Reactive device state (if preferred over Combine) |
| `XMLCoder` | Better XML parsing for UPnP descriptions |

---

## Testing Strategy

### Unit Tests

```swift
// Tests/RemotePlayTests/CastControllerTests.swift
final class CastControllerTests: XCTestCase {
    func testLoadMediaWithValidSession() async throws {
        // Mock GCKCastSession
        // Verify mediaInfo construction
        // Verify load() is called with correct URL
    }
}

// Tests/RemotePlayTests/DLNADiscoveryTests.swift
final class DLNADiscoveryTests: XCTestCase {
    func testSSDPMessageFormat() {
        let service = DLNADiscoveryService()
        let message = service.buildSearchMessage(serviceType: .mediaRenderer)
        XCTAssertTrue(message.contains("M-SEARCH"))
        XCTAssertTrue(message.contains("urn:schemas-upnp-org:device:MediaRenderer:1"))
    }
}
```

### Integration Tests

1. **Chromecast Discovery**: Verify devices appear in simulator/device
2. **DLNA Discovery**: Test with real Smart TV or emulator
3. **Playback Flow**: End-to-end test from device selection to playback
4. **Seek/Pause/Resume**: Test all control operations

### Manual Testing Checklist

- [ ] Chromecast Gen 3: Discovery, connect, play, seek, disconnect
- [ ] Chromecast with Google TV: Full playback with UI
- [ ] Samsung TV (Tizen): DLNA discovery and playback
- [ ] LG TV (webOS): DLNA discovery and playback
- [ ] Xbox Series X: DLNA playback
- [ ] PlayStation 5: DLNA playback
- [ ] Multi-device: Switch between devices mid-playback

---

## Known Limitations

### Google Cast

1. **Content ID Requirements**: Chromecast requires the content URL to be accessible from the device. Local network URLs work, but the device must be on the same WiFi.
2. **HLS Support**: Default Media Receiver supports HLS, but custom receivers may need additional setup for fMP4 segments.
3. **DRM**: Widevine support requires custom receiver application.

### DLNA/UPnP

1. **Format Compatibility**: Not all DLNA renderers support HLS. Some may require direct MP4 streaming.
2. **Subtitle Support**: VTT/SRT subtitles may not work on all devices.
3. **Seeking Accuracy**: Some older devices have poor seeking precision.
4. **Event Subscription**: GENA event subscription for playback state may not work on all devices.

### General

1. **Network Requirements**: All devices must be on the same local network.
2. **Firewall**: Some corporate networks block SSDP multicast.
3. **Battery Impact**: Continuous discovery can drain battery on mobile devices.

---

## Future Enhancements

1. **Samsung Tizen SDK**: Direct integration with Samsung TVs for better control
2. **LG webOS SDK**: Direct integration with LG TVs
3. **Roku SDK**: External Control Protocol (ECP) for Roku devices
4. **Fire TV**: Amazon Fling SDK integration
5. **Miracast**: Direct Wi-Fi Display protocol (limited iOS support)
6. **Custom Cast Receiver**: Build hosted receiver app for enhanced features

---

---

## Player Architecture Integration

### Current Architecture Analysis

The existing player stack uses a protocol-oriented design:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Player Stack                                │
│                                                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │ MKSPlayerView   │───▶│ PlayerManager   │───▶│ PlayerFactory   │  │
│  │ (SwiftUI)       │    │ (Singleton)     │    │ (Factory)       │  │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘  │
│           │                      │                      │           │
│           │                      ▼                      ▼           │
│           │             ┌───────────────────────────────────────┐   │
│           │             │         VideoPlayerProtocol          │   │
│           │             │  - isPlaying, currentTime, duration  │   │
│           │             │  - load(), play(), pause(), seek()   │   │
│           │             │  - playerView() -> AnyView           │   │
│           │             │  - underlyingAVPlayer: AVPlayer?     │   │
│           │             └───────────────┬───────────────────┬─┘   │
│           │                             │                   │      │
│           │              ┌──────────────┼───────────────┐   │      │
│           │              ▼              ▼               ▼   │      │
│           │     AVPlayerImpl    FFmpegPlayerImpl   VLCPlayerImpl   │
│           │     (Native)        (Transmux)         (Fallback)      │
│           │             │              │               │           │
│           └─────────────┼──────────────┼───────────────┘           │
│                         │              │                           │
│                         ▼              ▼                           │
│                   ┌─────────────────────────────────┐              │
│                   │    PlayerMetadataHelper         │              │
│                   │  - NowPlaying (Control Center)  │              │
│                   │  - externalMetadata (AVPlayer)  │              │
│                   │  - Remote Transport Controls    │              │
│                   └─────────────────────────────────┘              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Design Decision: RemotePlay as Coordinator (NOT VideoPlayerProtocol)

**Why NOT implement VideoPlayerProtocol:**

1. **`playerView()` is meaningless** - Remote devices don't render locally
2. **`underlyingAVPlayer` always nil** - No local AVPlayer when casting
3. **Different lifecycle** - Remote playback outlives local view lifecycle
4. **Coordination needed** - Must sync between local and remote state

**Correct Pattern: Coordinator that wraps local player**

```swift
/// RemotePlayManager coordinates between local player and remote devices.
/// It is NOT a VideoPlayerProtocol implementation - it's a higher-level
/// coordinator that can hand off playback between local and remote.
@MainActor
@Observable
class RemotePlayManager {

    // MARK: - State (mirrors VideoPlayerProtocol for UI binding)

    private(set) var isPlaying: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isBuffering: Bool = false

    // MARK: - Device Management

    private(set) var availableDevices: [RemoteDevice] = []
    private(set) var connectedDevice: RemoteDevice?
    var isConnected: Bool { connectedDevice != nil }

    // MARK: - Local Player Reference (weak - doesn't own)

    weak var localPlayer: (any VideoPlayerProtocol)?

    // MARK: - Content Reference

    private var currentSession: TransmuxServer.Session?
    private var currentMetadata: MetadataResult?

    // MARK: - State Source

    enum PlaybackSource {
        case local       // Local player is active
        case chromecast  // Chromecast is active
        case dlna        // DLNA device is active
    }
    private(set) var source: PlaybackSource = .local
}
```

### Metadata Sharing Pattern

Reuse `MetadataResult` with protocol-specific adapters:

```swift
// MARK: - Cast Metadata Adapter

enum CastMetadataAdapter {
    static func buildGCKMetadata(from metadata: MetadataResult) -> GCKMediaMetadata {
        let gck = GCKMediaMetadata()

        // Title logic mirrors PlayerMetadataHelper.setNowPlayingInfo
        let displayTitle: String
        if metadata.mediaType == .episode, let showTitle = metadata.showTitle {
            let s = metadata.seasonNumber ?? 1
            let e = metadata.episodeNumber ?? 1
            let ep = metadata.episodeTitle ?? metadata.title
            displayTitle = "\(showTitle) - S\(String(format: "%02d", s))E\(String(format: "%02d", e)) - \(ep)"
        } else {
            displayTitle = metadata.title
        }
        gck.setString(displayTitle, forKey: kGCKMetadataKeyTitle)

        // Subtitle
        let subtitle = metadata.mediaType == .movie
            ? (metadata.director ?? "")
            : (metadata.showTitle ?? "")
        gck.setString(subtitle, forKey: kGCKMetadataKeySubtitle)

        // Artwork
        if let posterURL = metadata.posterURL.flatMap(URL.init(string:)) {
            gck.addImage(GCKImage(url: posterURL, width: 480, height: 720))
        }

        // Duration will be set from GCKMediaInformation

        return gck
    }

    static func buildGCKMediaInfo(
        url: URL,
        metadata: MetadataResult,
        duration: Double
    ) -> GCKMediaInformation {
        GCKMediaInformation(
            contentID: url.absoluteString,
            streamType: .buffered,
            contentType: "application/x-mpegURL",  // HLS from TransmuxServer
            metadata: buildGCKMetadata(from: metadata),
            streamDuration: duration,
            mediaTracks: nil,
            textTrackStyle: nil,
            customData: nil
        )
    }
}

// MARK: - DLNA Metadata Adapter

enum DLNAMetadataAdapter {
    static func buildDIDLLite(from metadata: MetadataResult, url: URL) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">
            <item id="0" parentID="-1" restricted="1">
                <dc:title>\(metadata.title.xmlEscaped)</dc:title>
                <upnp:class>object.item.videoItem.movieItem</upnp:class>
                <res protocolInfo="http-get:*:application/x-mpegURL:*">\(url.absoluteString)</res>
                \(metadata.director.map { "<upnp:director>\($0.xmlEscaped)</upnp:director>" } ?? "")
                \(metadata.year.map { "<dc:date>\($0)</dc:date>" } ?? "")
            </item>
        </DIDL-Lite>
        """
    }
}
```

### UI Integration in MKSPlayerView

Add Remote Play button as an overlay:

```swift
// MKSPlayerView.swift - Add to body

struct MKSPlayerView: View {
    // ... existing properties ...

    /// Remote play manager (injected from environment or parent)
    @EnvironmentObject var remotePlay: RemotePlayManager

    /// Current transmux session (for URL handoff)
    var transmuxSession: TransmuxServer.Session?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            playerSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onTapGesture(count: 3) {
                    showDebugOverlay.toggle()
                }

            // ... existing debug overlay ...

            // MARK: - Remote Play Button (fullscreen mode only)
            if presentationMode == .fullscreen {
                remotePlayOverlay
            }

            // ... rest of existing overlays ...
        }
    }

    // MARK: - Remote Play Overlay

    @ViewBuilder
    private var remotePlayOverlay: some View {
        VStack {
            HStack {
                Spacer()
                remotePlayMenuButton
            }
            Spacer()
        }
        .padding()
        #if os(macOS)
        .opacity(macOSOverlayVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: macOSOverlayVisible)
        #endif
    }

    @ViewBuilder
    private var remotePlayMenuButton: some View {
        Menu {
            // Connected device section
            if let device = remotePlay.connectedDevice {
                Section {
                    Label(device.name, systemImage: device.type.icon)

                    if remotePlay.isPlaying {
                        Button {
                            Task { try? await remotePlay.pause() }
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                    } else {
                        Button {
                            Task { try? await remotePlay.play() }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        Task { await remotePlay.disconnect() }
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }

            // Available devices section
            Section("Cast to Device") {
                if remotePlay.isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                }

                ForEach(remotePlay.availableDevices) { device in
                    Button {
                        Task {
                            await handoffToDevice(device)
                        }
                    } label: {
                        Label(device.name, systemImage: device.type.icon)
                    }
                }

                if remotePlay.availableDevices.isEmpty && !remotePlay.isDiscovering {
                    Text("No devices found")
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Image(systemName: remotePlay.connectedDevice != nil ? "tv.fill" : "tv")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(remotePlay.connectedDevice != nil ? .cyan : .white)
        }
        .adaptiveGlass(in: Circle())
    }

    // MARK: - Handoff Logic

    private func handoffToDevice(_ device: RemoteDevice) async {
        guard let session = transmuxSession,
              let localPlayer = player as? any VideoPlayerProtocol else {
            return
        }

        do {
            try await remotePlay.handoffToRemote(
                device: device,
                session: session,
                metadata: metadata,
                localPlayer: localPlayer
            )
        } catch {
            print("[MKSPlayerView] Handoff failed: \(error)")
        }
    }
}
```

### State Synchronization Pattern

Bidirectional sync between local and remote:

```swift
// RemotePlaybackState.swift

/// Unified playback state that both local and remote contribute to.
/// Used to keep UI in sync regardless of playback source.
@MainActor
@Observable
class RemotePlaybackState {

    // MARK: - Playback State

    var isPlaying: Bool = false
    var currentTime: Double = 0
    var duration: Double = 0
    var playbackRate: Float = 1.0
    var isBuffering: Bool = false

    // MARK: - Source Tracking

    enum Source: Equatable {
        case local
        case chromecast(deviceId: String)
        case dlna(deviceId: String)
    }
    var source: Source = .local

    // MARK: - Sync Methods

    /// Called by RemotePlayManager when remote state changes
    func syncFromRemote(
        time: Double,
        isPlaying: Bool,
        rate: Float,
        isBuffering: Bool
    ) {
        guard !source.isLocal else { return }
        self.currentTime = time
        self.isPlaying = isPlaying
        self.playbackRate = rate
        self.isBuffering = isBuffering
    }

    /// Called by local player time observer
    func syncFromLocal(
        time: Double,
        isPlaying: Bool,
        rate: Float,
        isBuffering: Bool
    ) {
        guard source.isLocal else { return }
        self.currentTime = time
        self.isPlaying = isPlaying
        self.playbackRate = rate
        self.isBuffering = isBuffering
    }

    /// Switch source (triggers UI update)
    func switchSource(to newSource: Source) {
        self.source = newSource
    }
}

extension RemotePlaybackState.Source {
    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}
```

### Handoff Pattern

Position-preserving handoff between local and remote:

```swift
// RemotePlayManager+Handoff.swift

extension RemotePlayManager {

    // MARK: - Local → Remote Handoff

    /// Transfer playback from local player to remote device.
    /// Preserves position and playback state.
    func handoffToRemote(
        device: RemoteDevice,
        session: TransmuxServer.Session,
        metadata: MetadataResult?,
        localPlayer: any VideoPlayerProtocol
    ) async throws {
        // 1. Capture current state BEFORE any changes
        let position = localPlayer.currentTime
        let wasPlaying = localPlayer.isPlaying
        let rate = localPlayer.rate

        logHandoff("local → \(device.name)", position: position, wasPlaying: wasPlaying)

        // 2. Pause local player (keep loaded for potential handoff back)
        localPlayer.pause()

        // 3. Connect to remote device
        try await connect(to: device)

        // 4. Load content with position
        try await load(
            url: session.localURL,
            metadata: metadata,
            position: position
        )

        // 5. Restore playback state
        if wasPlaying {
            try await play()
        }

        // 6. Update state source for UI
        state.switchSource(to: device.sourceType)

        // 7. Store references for potential handoff back
        self.localPlayer = localPlayer
        self.currentSession = session
        self.currentMetadata = metadata

        logHandoffComplete(device.name, position: position)
    }

    // MARK: - Remote → Local Handoff

    /// Transfer playback from remote device back to local player.
    func handoffToLocal() async throws {
        guard let localPlayer = localPlayer,
              let session = currentSession else {
            throw RemotePlayError.noLocalPlayer
        }

        // 1. Capture remote state
        let position = state.currentTime
        let wasPlaying = state.isPlaying
        let rate = state.playbackRate

        logHandoff("\(connectedDevice?.name ?? "remote") → local", position: position, wasPlaying: wasPlaying)

        // 2. Stop remote playback
        try await stop()

        // 3. Disconnect from remote
        await disconnect()

        // 4. Seek local player to captured position
        if position > 0 {
            localPlayer.seek(to: position)
        }

        // 5. Restore playback state
        if wasPlaying {
            localPlayer.play()
        }
        localPlayer.rate = rate

        // 6. Update state source
        state.switchSource(to: .local)

        logHandoffComplete("local", position: position)
    }

    // MARK: - Logging

    private func logHandoff(_ direction: String, position: Double, wasPlaying: Bool) {
        print("[RemotePlay] Handoff: \(direction) at \(String(format: "%.1f", position))s, playing: \(wasPlaying)")
    }

    private func logHandoffComplete(_ destination: String, position: Double) {
        print("[RemotePlay] Handoff complete → \(destination) at \(String(format: "%.1f", position))s")
    }
}
```

### Integration with MediaDetailSheet

The parent view passes the transmux session to MKSPlayerView:

```swift
// MediaDetailSheet.swift

struct MediaDetailSheet: View {
    @StateObject private var remotePlay = RemotePlayManager.shared
    @State private var transmuxSession: TransmuxServer.Session?

    var body: some View {
        // ... content ...

        MKSPlayerView(
            player: playerManager.currentPlayer!,
            metadata: metadata,
            presentationMode: .fullscreen,
            transmuxSession: transmuxSession
        )
        .environmentObject(remotePlay)

        // ... rest of view ...
    }

    // When FFmpeg transmux starts, capture the session
    private func onTransmuxStarted(_ session: TransmuxServer.Session) {
        self.transmuxSession = session
    }
}
```

---

## References

- [Google Cast SDK Documentation](https://developers.google.com/cast)
- [UPnP Device Architecture 2.0](https://openconnectivity.org/developer/specifications/upnp-resources/upnp/)
- [DLNA Guidelines](https://www.dlna.org/guidelines)
- [SSDP Specification](https://tools.ietf.org/html/draft-cai-ssdp-v1-03)
- [TransmuxServer Architecture](./TransmuxCore/CLAUDE.md)
- [PlayerProtocol.swift](./mks-multiplatform-iptv/IPTVDownloader/Core/Player/PlayerProtocol.swift)
- [MKSPlayerView.swift](./mks-multiplatform-iptv/IPTVDownloader/Features/Player/MKSPlayerView.swift)
- [AVPlayerImplementation.swift](./mks-multiplatform-iptv/IPTVDownloader/Core/Player/AVPlayerImplementation.swift)

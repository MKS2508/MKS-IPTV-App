// swift-tools-version:5.9
//
// IPTVPlayer — Player layer for MKS-IPTV apps (iOS, macOS, tvOS).
//
// Contains player protocol abstractions and implementations:
//   - AVPlayerImplementation (native, all platforms)
//   - FFmpegPlayerImplementation (transmux pipeline via TransmuxCore, all platforms)
//   - VLCPlayerImplementation (#if !os(tvOS), iOS+macOS only)
//   - PlayerFactory (auto-selects best player per format/platform)
//   - NativePlayerRepresentable (SwiftUI wrappers)
//   - PlayerWindowManager (#if os(macOS), window management)
//   - GlitchDetector + GlitchTypes (real-time playback anomaly detection)
//   - StreamProxyAdapter, TransmuxResourceLoader (AVAssetResourceLoader bridges)
//   - FFmpegMetadataWriter (#if canImport(CFFmpegHelper))
//
// Depends on IPTVCore (data layer) + TransmuxCore (FFmpeg transmux engine).
//

import PackageDescription

let package = Package(
    name: "IPTVPlayer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "IPTVPlayer",
            targets: ["IPTVPlayer"]
        )
    ],
    dependencies: [
        .package(path: "../IPTVCore"),
        .package(path: "../TransmuxCore")
    ],
    targets: [
        .target(
            name: "IPTVPlayer",
            dependencies: [
                .product(name: "IPTVCore", package: "IPTVCore"),
                .product(name: "TransmuxCore", package: "TransmuxCore")
            ],
            path: "Sources/IPTVPlayer"
        )
    ]
)

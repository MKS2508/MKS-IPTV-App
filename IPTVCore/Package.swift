// swift-tools-version:5.9
//
// IPTVCore — Shared core for MKS-IPTV apps (iOS, macOS, tvOS).
//
// Contains data models, services, networking, EPG, metadata enrichment,
// watch history, sync, configuration, and utility helpers.
//
// Does NOT include the player layer (see IPTVPlayer SPM, which depends on
// IPTVCore + TransmuxCore).
//

import PackageDescription

let package = Package(
    name: "IPTVCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "IPTVCore",
            targets: ["IPTVCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "IPTVCore",
            path: "Sources/IPTVCore"
        )
    ]
)

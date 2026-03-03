// swift-tools-version:5.9
import PackageDescription

// NOTE: This CLI is legacy. Use TransmuxCore/transmux-cli instead.
let package = Package(
    name: "transmux-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../TransmuxCore"),
    ],
    targets: [
        .executableTarget(
            name: "transmux-cli",
            dependencies: [
                .product(name: "TransmuxCore", package: "TransmuxCore"),
            ],
            path: "Sources"
        ),
    ]
)

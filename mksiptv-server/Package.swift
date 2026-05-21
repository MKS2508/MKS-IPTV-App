// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mksiptv-server",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
        .tvOS(.v16)
    ],
    dependencies: [
        // Vapor 4.x HTTP framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
        // JWT for OIDC token validation
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
        // IPTVCore - Shared models and services
        .package(path: "../IPTVCore"),
        // TransmuxCore - FFmpeg transmuxing service
        .package(path: "../TransmuxCore"),
    ],
    targets: [
        // Main server executable
        .executableTarget(
            name: "mksiptv-server",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "IPTVCore", package: "IPTVCore"),
                .product(name: "TransmuxCore", package: "TransmuxCore"),
            ],
            path: "Sources/mksiptv-server"
        ),
        // Tests
        .testTarget(
            name: "mksiptv-server-tests",
            dependencies: [
                .target(name: "mksiptv-server"),
            ],
            path: "Tests/mksiptv-server-tests"
        ),
    ]
)

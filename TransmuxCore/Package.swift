// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TransmuxCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "TransmuxCore",
            targets: ["TransmuxCore", "CFFmpegHelper"]
        ),
        .executable(
            name: "transmux-cli",
            targets: ["transmux-cli"]
        )
    ],
    targets: [
        .target(
            name: "CFFmpegHelper",
            path: "Sources/CFFmpegHelper",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/FFmpegKit.xcframework/macos-arm64/FFmpegKit.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavcodec.xcframework/macos-arm64_x86_64/libavcodec.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavformat.xcframework/macos-arm64_x86_64/libavformat.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavutil.xcframework/macos-arm64_x86_64/libavutil.framework/Headers")
            ]
        ),
        .target(
            name: "TransmuxCore",
            dependencies: ["CFFmpegHelper"],
            path: "Sources/TransmuxCore",
            cSettings: [
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/FFmpegKit.xcframework/macos-arm64/FFmpegKit.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavcodec.xcframework/macos-arm64_x86_64/libavcodec.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavformat.xcframework/macos-arm64_x86_64/libavformat.framework/Headers"),
                .headerSearchPath("../../mks-multiplatform-iptv/Frameworks/libavutil.xcframework/macos-arm64_x86_64/libavutil.framework/Headers")
            ],
            linkerSettings: [
                .linkedFramework("FFmpegKit"),
                .linkedFramework("libavcodec"),
                .linkedFramework("libavformat"),
                .linkedFramework("libavutil"),
                .unsafeFlags([
                    "-F", "../../mks-multiplatform-iptv/Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .executableTarget(
            name: "transmux-cli",
            dependencies: ["TransmuxCore"],
            path: "Sources/transmux-cli"
        ),
        .testTarget(
            name: "TransmuxCoreTests",
            dependencies: ["TransmuxCore"],
            path: "Tests/TransmuxCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)

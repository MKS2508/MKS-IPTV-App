// swift-tools-version:5.9
import PackageDescription
import Foundation

// MARK: - FFmpeg Configuration

let packageDir = URL(fileURLWithPath: #file).deletingLastPathComponent().path
let ffmpegRoot = "Frameworks/FFmpeg"

/// Header search paths for FFmpeg includes. Required because the C wrapper
/// (`Sources/CTransmuxFFI`) uses `#include <libavformat/avformat.h>` style
/// includes — these resolve via the search path, not via the XCFramework's
/// own bundled headers (XCFrameworks here ship binaries only). Headers live
/// at `Frameworks/FFmpeg/include/` and are platform-independent.
let ffmpegHeaderSearchPaths: [CSetting] = [
    .headerSearchPath("../../\(ffmpegRoot)/include"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libavcodec"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libavformat"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libavutil"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libswresample"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libswscale"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libavfilter"),
    .headerSearchPath("../../\(ffmpegRoot)/include/libavdevice")
]

/// System dependencies required by FFmpeg.
let systemDependencies: [LinkerSetting] = [
    .linkedLibrary("z"),
    .linkedLibrary("bz2"),
    .linkedLibrary("iconv"),
    .linkedFramework("VideoToolbox"),
    .linkedFramework("AudioToolbox"),
    .linkedFramework("CoreMedia"),
    .linkedFramework("CoreVideo"),
    .linkedFramework("CoreFoundation"),
    .linkedFramework("Security"),
]

/// FFmpeg static libraries shipped as XCFramework binary targets. Each XCFramework
/// contains 5 slices: macos-arm64, ios-arm64, ios-arm64_x86_64-simulator,
/// tvos-arm64, tvos-arm64-simulator. xcodebuild auto-resolves the correct slice
/// per consumer's platform/arch — no `unsafeFlags -L` needed per platform.
let ffmpegBinaryDeps: [Target.Dependency] = [
    "Avformat", "Avcodec", "Avutil",
    "Swresample", "Swscale", "Avfilter", "Avdevice"
]

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
            targets: ["TransmuxCore", "CTransmuxFFI"]
        ),
        .executable(
            name: "transmux-cli",
            targets: ["transmux-cli"]
        )
    ],
    targets: [
        // MARK: - FFmpeg XCFramework binary targets
        .binaryTarget(name: "Avformat",   path: "Frameworks/FFmpeg/xcframeworks/Avformat.xcframework"),
        .binaryTarget(name: "Avcodec",    path: "Frameworks/FFmpeg/xcframeworks/Avcodec.xcframework"),
        .binaryTarget(name: "Avutil",     path: "Frameworks/FFmpeg/xcframeworks/Avutil.xcframework"),
        .binaryTarget(name: "Swresample", path: "Frameworks/FFmpeg/xcframeworks/Swresample.xcframework"),
        .binaryTarget(name: "Swscale",    path: "Frameworks/FFmpeg/xcframeworks/Swscale.xcframework"),
        .binaryTarget(name: "Avfilter",   path: "Frameworks/FFmpeg/xcframeworks/Avfilter.xcframework"),
        .binaryTarget(name: "Avdevice",   path: "Frameworks/FFmpeg/xcframeworks/Avdevice.xcframework"),

        // MARK: - CTransmuxFFI (C FFI library wrapping FFmpeg 8.0.1)
        .target(
            name: "CTransmuxFFI",
            dependencies: ffmpegBinaryDeps,
            path: "Sources/CTransmuxFFI",
            publicHeadersPath: "include",
            cSettings: ffmpegHeaderSearchPaths,
            linkerSettings: systemDependencies
        ),
        // MARK: - TransmuxCore (Swift library)
        .target(
            name: "TransmuxCore",
            dependencies: ["CTransmuxFFI"] + ffmpegBinaryDeps,
            path: "Sources/TransmuxCore",
            cSettings: ffmpegHeaderSearchPaths,
            linkerSettings: systemDependencies
        ),
        // MARK: - transmux-cli (Command-line tool)
        .executableTarget(
            name: "transmux-cli",
            dependencies: ["TransmuxCore"],
            path: "Sources/transmux-cli",
            linkerSettings: systemDependencies
        ),
        // MARK: - Tests
        .testTarget(
            name: "TransmuxCoreTests",
            dependencies: ["TransmuxCore"],
            path: "Tests/TransmuxCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)

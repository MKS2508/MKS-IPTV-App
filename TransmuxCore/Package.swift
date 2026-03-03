// swift-tools-version:5.9
import PackageDescription

// MARK: - FFmpeg Configuration

/// FFmpeg headers and libraries root (relative to package directory)
let ffmpegRoot = "Frameworks/FFmpeg"

/// Header search paths for FFmpeg includes
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

/// FFmpeg static libraries to link
let ffmpegLinkedLibraries: [LinkerSetting] = [
    .linkedLibrary("avformat"),
    .linkedLibrary("avcodec"),
    .linkedLibrary("avutil"),
    .linkedLibrary("swresample"),
    .linkedLibrary("swscale"),
    .linkedLibrary("avfilter"),
    .linkedLibrary("avdevice"),
]

/// System dependencies required by FFmpeg
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

/// Platform-specific library search paths
/// macOS: native arm64 build
/// iOS: separate builds for arm64 device and x86_64 simulator
let librarySearchPaths: [LinkerSetting] = [
    .unsafeFlags(["-L", "\(ffmpegRoot)/macos/arm64"], .when(platforms: [.macOS])),
    .unsafeFlags(["-L", "\(ffmpegRoot)/ios/arm64"], .when(platforms: [.iOS])),
    .unsafeFlags(["-L", "\(ffmpegRoot)/ios/arm64"], .when(platforms: [.tvOS])),
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
            targets: ["TransmuxCore", "CFFmpegHelper"]
        ),
        .executable(
            name: "transmux-cli",
            targets: ["transmux-cli"]
        )
    ],
    targets: [
        // MARK: - CFFmpegHelper (C wrapper for FFmpeg)
        .target(
            name: "CFFmpegHelper",
            path: "Sources/CFFmpegHelper",
            publicHeadersPath: "include",
            cSettings: ffmpegHeaderSearchPaths
        ),
        // MARK: - TransmuxCore (Swift library)
        .target(
            name: "TransmuxCore",
            dependencies: ["CFFmpegHelper"],
            path: "Sources/TransmuxCore",
            cSettings: ffmpegHeaderSearchPaths,
            linkerSettings: ffmpegLinkedLibraries + systemDependencies + librarySearchPaths
        ),
        // MARK: - transmux-cli (Command-line tool)
        .executableTarget(
            name: "transmux-cli",
            dependencies: ["TransmuxCore"],
            path: "Sources/transmux-cli",
            linkerSettings: ffmpegLinkedLibraries + systemDependencies + librarySearchPaths
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

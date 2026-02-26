// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "transmux-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "/Users/mks/Library/Developer/Xcode/DerivedData/mks-multiplatform-iptv-gcedrffrfjscjfeevtoxyyjifzlr/SourcePackages/checkouts/FFmpegKit"),
    ],
    targets: [
        .executableTarget(
            name: "transmux-cli",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit"),
            ],
            path: "Sources"
        ),
    ]
)

# Building TransmuxCore

## Prerequisites

TransmuxCore requires FFmpeg libraries (Libavformat, Libavcodec, Libavutil) to be available during compilation. These are provided by KSPlayer's FFmpegKit.xcframework in the main app.

## Setup for Standalone Build

To build TransmuxCore as a standalone package, you need to make FFmpeg headers available to Swift Package Manager:

### Option 1: Symlink Frameworks (Recommended)

```bash
cd TransmuxCore
mkdir -p Frameworks
ln -s ../mks-multiplatform-iptv/Frameworks/FFmpegKit.xcframework Frameworks/
ln -s ../mks-multiplatform-iptv/Frameworks/libavcodec.xcframework Frameworks/
ln -s ../mks-multiplatform-iptv/Frameworks/libavformat.xcframework Frameworks/
ln -s ../mks-multiplatform-iptv/Frameworks/libavutil.xcframework Frameworks/
```

Then update `Package.swift` header search paths to use local `Frameworks/` directory.

### Option 2: Build as Part of Xcode Project

The cleanest approach is to add TransmuxCore as a local Swift Package dependency in the main Xcode project:

1. Open `mks-multiplatform-iptv.xcodeproj`
2. File > Add Package Dependencies > Add Local...
3. Select the `TransmuxCore/` folder
4. Add `TransmuxCore` library to app target

Xcode will handle FFmpeg framework linking automatically since they're already part of the project.

## Building

### Via Xcode (Recommended)

Once added as a local package dependency in Xcode:

```bash
xcodebuild -project ../mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplatform-iptv \
  -configuration Debug
```

### Via Swift CLI (Requires FFmpeg Setup)

After completing Option 1 above:

```bash
cd TransmuxCore
swift build
swift build --product transmux-cli
```

## Testing the CLI

```bash
# Basic test with local file
.build/debug/transmux-cli ~/Movies/sample.mkv

# Test seeking functionality
.build/debug/transmux-cli ~/Movies/sample.mkv --seek 300 --duration 20 --verbose

# Monitor logs
tail -f /tmp/mks-iptv-transmux.log
```

## Integration in App

Replace usages of the original `TransmuxingService` with the package version:

```swift
// Before (app's original code):
let session = try await TransmuxingService.shared.startTransmux(from: url)

// After (using TransmuxCore package):
import TransmuxCore

let service = TransmuxingService(streamProxy: StreamProxyAdapter())
let session = try await service.startTransmux(from: url)
```

## Troubleshooting

### "Libavformat/avformat.h file not found"

The FFmpeg headers are not accessible to SPM. Follow Option 1 or Option 2 above.

### "Undefined symbols for architecture arm64"

FFmpeg frameworks are not being linked. When using as a local package in Xcode, ensure:
- FFmpegKit.xcframework is in the project
- Framework is linked to the app target
- Framework search paths include the Frameworks directory

### "Non-monotonic DTS" errors in logs

This is the issue the AC3 init phase fix addresses. Ensure you're using the adapted `TransmuxingService.swift` with the truncation/reset code after lines 505-546.

## Next Steps

1. Add TransmuxCore as local package to Xcode project
2. Update `FFmpegPlayerImplementation` to use `StreamProxyAdapter()`
3. Remove old `TransmuxingService.swift` from app
4. Build and test with AC3 audio content
5. Verify seeking works correctly

## Package Structure

```
TransmuxCore/
├── Package.swift                  # SPM manifest
├── Sources/
│   ├── CFFmpegHelper/            # C helper target
│   │   ├── FFmpegStreamHelper.c
│   │   └── include/
│   │       └── FFmpegStreamHelper.h
│   ├── TransmuxCore/             # Main library
│   │   ├── Core/
│   │   │   ├── TransmuxingService.swift
│   │   │   ├── HLSSegmenter.swift
│   │   │   ├── TransmuxServer.swift
│   │   │   ├── ActiveTransmux.swift
│   │   │   └── TransmuxLog.swift
│   │   ├── Protocols/
│   │   │   └── StreamProxyProtocol.swift
│   │   └── TransmuxCore.swift
│   └── transmux-cli/             # CLI executable
│       └── main.swift
├── Tests/
│   └── TransmuxCoreTests/
└── README.md
```

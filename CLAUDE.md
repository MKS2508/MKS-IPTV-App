# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MKS-IPTV-App is a native Apple multiplatform IPTV streaming client built with Swift 6 and SwiftUI, targeting iOS 26 Beta, macOS 26 Beta, and tvOS 26 Beta with Liquid Glass design patterns.

## Build Commands

### macOS Development Build
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplatform-iptv \
  -configuration Debug
```

### iOS Archive and Export
```bash
# Create archive
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplatform-iptv \
  -configuration Release \
  -archivePath build/ios/mks-iptv.xcarchive archive

# Export IPA
xcodebuild -exportArchive \
  -archivePath build/ios/mks-iptv.xcarchive \
  -exportPath build/export/ios \
  -exportOptionsPlist ExportOptions.plist
```

### tvOS Development Build
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplataforma-tvos-iptv \
  -configuration Debug
```

## High-Level Architecture

### Project Structure
- **IPTVDownloader/**: Main application code organized by feature modules
  - **Core/**: Infrastructure including Configuration, Networking, and Player implementations
  - **Features/**: Feature modules (Downloads, LiveChannels, Movies, Series, TouchBar)
  - **Models/**: Data models (Movie, Series, LiveChannel)
  - **Services/**: API services and networking layer
  - **Utils/**: HTTP servers and streaming utilities
- **mks-multiplataforma-tvos-iptv/**: tvOS-specific target
- **build/**: Build outputs and distribution files
- **docs/**: Documentation and screenshots

### Key Architectural Components

1. **StreamManager**: Handles live stream management and URL resolution with HTTP proxy servers for AVPlayer compatibility
2. **DownloadManager**: Reactive download system with real-time progress tracking and queue management
3. **HTTPStreamServer**: Local HTTP server for streaming downloaded content
4. **PlatformNavigationView**: Adaptive navigation that switches between sidebar (macOS), split view (iPad), and tab bar (iPhone)
5. **TouchBarManager**: Native macOS TouchBar integration for media controls

### Technical Stack
- **Language**: Swift 6.0 with modern concurrency (async/await, Actor model)
- **UI Framework**: SwiftUI with platform-specific adaptations
- **Architecture Pattern**: MVVM with clear separation of concerns
- **Video Playback**: AVKit with AVPlayer, HTTP proxy for IPTV compatibility
- **Networking**: Native Network framework with custom HTTP proxy implementation

### Platform-Specific Features
- **iOS**: Liquid Glass navigation, adaptive layouts for iPhone/iPad
- **macOS**: TouchBar support, native window management
- **tvOS**: Focus-based navigation optimized for Apple TV

### Content Management
- Four main modules: Movies, Series, Live TV, Downloads
- Gallery views with search and filtering capabilities
- Per-content actions: Stream, Download, External Player, Copy Link
- MOV format conversion for optimal AirPlay and Apple TV integration

## Development Notes

### Current Repository State
The repository currently contains build outputs and documentation. The actual Swift source code files are not present in the repository, which suggests the codebase might be in a separate location or not yet committed.

### GitHub Pages Documentation
The documentation site is hosted at: https://MKS2508.github.io/MKS-IPTV-App/
- Configuration: `docs/_config.yml` with Jekyll and Hacker theme
- Main pages: index.md, download.md, installation.md, screenshots.md
- Custom CSS: Cyberpunk/synthwave styling in `docs/assets/css/`

### Required Development Environment
- Xcode 16 Beta (for iOS/macOS/tvOS 26 Beta support)
- macOS 15 Beta or later
- Swift 6.0
- Apple Developer Account for device deployment

### Code Signing
The project requires proper code signing configuration. Ensure developer certificates and provisioning profiles are correctly set up in Xcode.

### Testing
No test infrastructure is currently visible in the repository. When implementing tests, consider:
- Unit tests for ViewModels and business logic
- UI tests for critical user flows
- Integration tests for streaming and download functionality
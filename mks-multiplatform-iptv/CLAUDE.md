# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MKS-IPTV is a native Apple multiplatform IPTV streaming client built with Swift 6 and SwiftUI, targeting iOS, macOS, and tvOS. The app connects to IPTV servers using the Xtream Codes API protocol to stream movies, series, and live TV channels.

## Build Commands

### macOS Development Build
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplatform-iptv \
  -configuration Debug
```

### iOS Build
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplatform-iptv \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### tvOS Build
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
  -scheme mks-multiplataforma-tvos-iptv \
  -configuration Debug
```

### Install CocoaPods Dependencies
```bash
pod install
```

## Project Structure

```
mks-multiplatform-iptv/
├── IPTVDownloader/              # Main application code
│   ├── Core/                    # Infrastructure layer
│   │   ├── Configuration/       # IPTVProfile, IPTVProfilesManager
│   │   ├── Networking/          # VideoStreamer, ImageCache, VideoDownloader, CacheManager
│   │   └── Player/              # Multi-player abstraction (AVPlayer, KSPlayer, VLC, FFmpeg)
│   ├── Features/                # Feature modules (MVVM)
│   │   ├── Download/            # Download management with progress tracking
│   │   ├── LiveChannelsList/    # Live TV streaming
│   │   ├── MovieList/           # Movies and Series gallery
│   │   ├── Player/              # Universal player view
│   │   ├── Profile/             # IPTV profile management
│   │   ├── Settings/            # App preferences
│   │   ├── TouchBar/            # macOS TouchBar integration
│   │   └── Debug/               # Development tools
│   ├── Models/                  # Data models (Movie, Serie, LiveChannel, etc.)
│   ├── Services/                # API layer (MovieService actor)
│   └── Utils/                   # HTTP servers, FFmpeg utilities, logging
├── Assets.xcassets/             # App assets
├── PlatformNavigationView.swift # Platform-adaptive navigation
└── mks_multiplatform_iptvApp.swift # App entry point
```

## Architecture

### MVVM Pattern
Each feature module follows MVVM:
- **Views**: SwiftUI views in `Views/` subdirectories
- **ViewModels**: Observable classes handling UI state in `ViewModels/`
- **Models**: Data structures in `IPTVDownloader/Models/`

### Key Components

#### IPTVProfile & IPTVProfilesManager
User credentials and server configuration stored in `IPTVProfile`. `IPTVProfilesManager.shared` manages multiple profiles with one active at a time. All API calls require the active profile.

#### MovieService (Actor)
Thread-safe API service in `Services/MovieService.swift` that communicates with IPTV servers via the Xtream Codes API (`/player_api.php` endpoints). Handles fetching movies, series, live channels, and their details.

#### DownloadManager
Reactive download system in `Features/Download/ViewModels/DownloadManager.swift` that:
- Manages concurrent downloads with pause/resume/cancel
- Tracks real-time progress, speed, and ETA via Combine publishers
- Supports MOV conversion for AirPlay/Apple TV compatibility

#### Player Abstraction
Multi-player system in `Core/Player/` with protocol `VideoPlayerProtocol`:
- **AVPlayer**: Native Apple player (limited format support)
- **KSPlayer**: Preferred for MKV with PiP/AirPlay support
- **VLCKit**: Wide format support (via CocoaPods)
- **FFmpeg**: Transmuxing fallback

`PlayerFactory` auto-selects the best player based on format and features.

#### StreamManager
Live stream URL resolution in `Features/Download/ViewModels/StreamManager.swift` that handles redirects and custom headers for IPTV stream compatibility.

#### HTTPStreamServer
Local HTTP proxy server in `Utils/HTTPStreamServer.swift` that transmuxes MKV to MP4 for AVPlayer compatibility using FFmpeg.

#### PlatformNavigationView
Adaptive navigation in `PlatformNavigationView.swift`:
- **macOS/iPad**: `NavigationSplitView` with sidebar
- **iPhone**: `TabView` with bottom tabs

### Platform-Specific Features

- **macOS**: TouchBar integration via `TouchBarManager`, native window commands
- **iOS**: Adaptive layouts for iPhone/iPad, Liquid Glass styling
- **tvOS**: Focus-based navigation (separate target `mks-multiplataforma-tvos-iptv`)

## Dependencies

- **VLCKit 3.6.0** (via CocoaPods): Alternative video player with broad format support

## IPTV API Endpoints

The app uses Xtream Codes API pattern:
- `/player_api.php?action=get_vod_streams` - Movies list
- `/player_api.php?action=get_series` - Series list
- `/player_api.php?action=get_live_streams` - Live channels
- `/player_api.php?action=get_vod_categories` - Movie categories
- `/player_api.php?action=get_series_categories` - Series categories
- `/player_api.php?action=get_live_categories` - Live channel categories
- `/player_api.php?action=get_vod_info&vod_id=X` - Movie details
- `/player_api.php?action=get_series_info&series_id=X` - Series details

Stream URLs: `{baseURL}/{movie|series|live}/{username}/{password}/{id}.{extension}`

## Environment Requirements

- Xcode 16+ (for Swift 6 and latest SwiftUI features)
- macOS 15+ (Sequoia)
- CocoaPods for VLCKit dependency

## Code Conventions

- Use `async/await` for asynchronous operations
- Prefer `@StateObject` for ViewModel ownership
- Use `EnvironmentObject` for shared services (DownloadManager, IPTVProfile)
- Conditional compilation with `#if os(macOS)` / `#if os(iOS)` for platform-specific code
- Actor isolation for thread-safe services (MovieService)

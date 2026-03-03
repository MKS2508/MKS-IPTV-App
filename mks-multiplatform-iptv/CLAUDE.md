# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 🎯 PRIMARY MISSION: PERFECT VOD SEEKING

**THE ENTIRE REASON THIS APP EXISTS IS TO ACHIEVE PERFECT SEEKING IN VOD PLAYBACK.**

All other IPTV apps have broken or slow seeking on VOD content. This app's sole purpose is to solve that problem with a flawless transmux pipeline that enables:

- **Instant seeking** (<2 seconds to any position in multi-hour movies)
- **Frame-accurate positioning** (no timestamp desync or A/V drift)
- **Zero stuttering** (smooth playback after seeks)
- **Full AVPlayer native integration** (AirPlay, PiP, native UI)

When making ANY decision about the transmux system (`TransmuxingService`, `HLSSegmenter`, `TransmuxServer`):

1. **Seeking performance is the #1 priority** - sacrificing any other feature to improve seeking is acceptable
2. **Test with multi-hour movies** - short clips hide seeking problems
3. **Verify A/V sync after seeks** - timestamp rebasing must be perfect
4. **Support all codecs** - H.264/H.265 video, AAC/AC3/EAC3/DTS audio, all containers (MKV, MP4, AVI)

The transmux architecture uses:
- **Progressive fMP4 output** with fragmented moof+mdat boxes
- **Static VOD playlist** (full duration known upfront, enables instant seeking)
- **GLOBAL OFFSET timestamp rebasing** (single video keyframe determines offset for ALL streams, preserving A/V sync)
- **Audio packet buffering** (no data loss during seek transitions)
- **Fullness gate in TransmuxServer** (only serves segments when data is complete)

**If seeking is broken, the app has no reason to exist.**

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

### SPM Dependencies
Dependencies (TransmuxCore local, VLCKitSPM) are managed via Swift Package Manager.
Add new packages via Xcode: File > Add Package Dependencies.

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
- **AVPlayer**: Native Apple player (MP4/MOV/HLS)
- **FFmpeg Transmux**: Primary player for non-native formats. Uses FFmpeg 8.0.1 C API via TransmuxCore to remux MKV/AVI/TS to HLS/fMP4, then plays through AVPlayer for AirPlay + PiP support.
- **VLCKit**: Wide format fallback (via VLCKitSPM Swift Package)

`PlayerFactory` auto-selects the best player based on format, features, and AirPlay requirements.

#### TransmuxingService
Actor-based service in `Core/Player/TransmuxingService.swift` that remuxes non-native containers (MKV, AVI, etc.) to HLS/fMP4 using FFmpeg 8.0.1 C API (via TransmuxCore) without re-encoding.

#### TransmuxServer
NWListener-based HTTP server in `Utils/TransmuxServer.swift` that serves transmuxed HLS segments to AVPlayer for AirPlay compatibility.

#### StreamManager
Live stream URL resolution in `Features/Download/ViewModels/StreamManager.swift` that handles redirects and custom headers for IPTV stream compatibility.

#### PlatformNavigationView
Adaptive navigation in `PlatformNavigationView.swift`:
- **macOS/iPad**: `NavigationSplitView` with sidebar
- **iPhone**: `TabView` with bottom tabs

### Platform-Specific Features

- **macOS**: TouchBar integration via `TouchBarManager`, native window commands
- **iOS**: Adaptive layouts for iPhone/iPad, Liquid Glass styling
- **tvOS**: Focus-based navigation (separate target `mks-multiplataforma-tvos-iptv`)

## Dependencies

- **TransmuxCore** (local SPM): FFmpeg 8.0.1 transmux pipeline — remuxes MKV/AVI/TS to HLS/fMP4 for AVPlayer. Includes CFFmpegHelper (C wrapper) and static FFmpeg libs for macOS/iOS/tvOS.
- **VLCKitSPM** (via SPM): VLC fallback player — `https://github.com/tylerjonesio/vlckit-spm.git`

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

## Code Conventions

- Use `async/await` for asynchronous operations
- Prefer `@StateObject` for ViewModel ownership
- Use `EnvironmentObject` for shared services (DownloadManager, IPTVProfile)
- Conditional compilation with `#if os(macOS)` / `#if os(iOS)` for platform-specific code
- Actor isolation for thread-safe services (MovieService)

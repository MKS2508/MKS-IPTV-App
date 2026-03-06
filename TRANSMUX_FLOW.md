# Transmux Flow - Architecture Diagram

## Overview

This document describes the complete data flow from user pressing "Play" to video playback through the FFmpeg transmux pipeline.

## High-Level Flow

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              USER PRESSES PLAY                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  UI LAYER                                                                        │
│  ─────────                                                                       │
│  • MediaDetailSheet.swift          - Movie/series detail with play button       │
│  • LiveChannelsGridView.swift      - Live TV channel selection                  │
│  • DebugStreamingView.swift        - Debug player interface                     │
│                                                                                  │
│  Calls: PlayerFactory.shared.createPlayer(url, metadata)                        │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  PLAYER FACTORY                                                                  │
│  ──────────────                                                                  │
│  📁 mks-multiplatform-iptv/IPTVDownloader/Core/Player/PlayerFactory.swift        │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  createPlayer(for: url, metadata:)                                       │    │
│  │                                                                          │    │
│  │  1. detectFormat(from: url)     → "mkv", "mp4", "m3u8", etc.            │    │
│  │  2. nativeFormats.contains()    → AVPlayer (mp4, m4v, mov, m3u8, ts)    │    │
│  │  3. transmuxFormats.contains()  → FFmpegPlayerImplementation (mkv, etc) │    │
│  │  4. fallback                    → VLC or AVPlayer                        │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  For MKV files → FFmpegPlayerImplementation.load(url, metadata)                 │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  FFMPEG PLAYER IMPLEMENTATION                                                    │
│  ─────────────────────────────                                                   │
│  📁 mks-multiplatform-iptv/IPTVDownloader/Core/Player/FFmpegPlayerImplementation │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │  load(url:, metadata:)                                                   │    │
│  │                                                                          │    │
│  │  1. StreamPreflight.check(url)         → Validate stream reachable      │    │
│  │  2. TransmuxingService.shared.startTransmux(from: url)                  │    │
│  │     ↓                                                                    │    │
│  │     └─→ [TRANSMUXCORE LAYER - See Below]                                │    │
│  │     ↓                                                                    │    │
│  │  3. TransmuxServer.shared.start(...)   → Start HTTP server              │    │
│  │  4. AVPlayerImplementation.load(hlsURL, metadata)                       │    │
│  │  5. avPlayer?.play()                    → Start playback                │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  State: isTransmuxing, pendingMetadata, transmuxSessionID                       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
┌───────────────────────────────────┐  ┌───────────────────────────────────────────┐
│  TRANSMUXING SERVICE (Swift)      │  │  AVPLAYER IMPLEMENTATION                  │
│  ─────────────────────────        │  │  ───────────────────────────              │
│  📁 TransmuxCore/Sources/         │  │  📁 mks-.../Core/Player/                  │
│      TransmuxCore/Core/           │  │      AVPlayerImplementation.swift         │
│      TransmuxingService.swift     │  │                                           │
│                                   │  │  • Creates AVPlayer with HLS URL          │
│  • Opens FFmpeg input stream      │  │  • Sets up time observer (0.1s interval)  │
│  • Maps video + audio streams     │  │  • Monitors buffering state               │
│  • Creates HLSSegmenter           │  │  • Handles seek requests                  │
│  • Calls C wrapper for remux      │  │  • Reports progress via Publisher         │
│                                   │  │                                           │
│  Returns:                         │  │  Output:                                  │
│  • sessionID                      │  │  • Video surface to SwiftUI               │
│  • outputPath (fMP4 file)         │  │  • underlyingAVPlayer for native controls │
│  • playlistPath (m3u8)            │  │  • bufferingDetail for debug overlay      │
│  • segmenter (HLSSegmenter)       │  │                                           │
│  • seekHandle (for seek signals)  │  │                                           │
└───────────────────────────────────┘  └───────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  CFFMPEG HELPER (C Bridge)                                                       │
│  ─────────────────────────                                                       │
│  📁 TransmuxCore/Sources/CFFmpegHelper/                                          │
│      FFmpegStreamHelper.c      - C implementation                                │
│      include/FFmpegStreamHelper.h - Header with Swift-callable functions         │
│                                                                                  │
│  Key Functions:                                                                  │
│  • mks_open_input()            - avformat_open_input wrapper                     │
│  • mks_get_stream_info()       - avformat_find_stream_info wrapper               │
│  • mks_stream_offsets          - Runtime offset detection for structs            │
│  • mks_subtitle_collector_*    - In-band subtitle extraction                     │
│                                                                                  │
│  Reads from: IPTV URL (http://...)                                               │
│  Writes to: fMP4 file (stream.mp4)                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  FFMPEG REMUX LOOP (C - inside TransmuxingService)                               │
│  ───────────────────────────────────────                                         │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  while (av_read_frame(inCtx, &pkt) >= 0) {                                │   │
│  │                                                                           │   │
│  │      1. Check for seek signal (via ActiveTransmux.seekHandle)            │   │
│  │         └─→ av_seek_frame() + rebase timestamps                          │   │
│  │                                                                           │   │
│  │      2. Feed subtitle collector (if subtitle stream)                     │   │
│  │         └─→ mks_subtitle_collector_feed() → WebVTT files                  │   │
│  │                                                                           │   │
│  │      3. Rescale timestamps (input timebase → output timebase)            │   │
│  │                                                                           │   │
│  │      4. av_interleaved_write_frame(outCtx, &pkt)                         │   │
│  │         └─→ Writes moof+mdat fragments to fMP4                           │   │
│  │                                                                           │   │
│  │      5. Notify HLSSegmenter of new data                                  │   │
│  │         └─→ segmenter.scanForNewSegments()                               │   │
│  │  }                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Output: Progressive fMP4 file with fragmented moof+mdat boxes                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  HLS SEGMENTER                                                                   │
│  ─────────────                                                                   │
│  📁 TransmuxCore/Sources/TransmuxCore/Core/HLSSegmenter.swift                    │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  Parses fMP4 boxes in real-time:                                          │   │
│  │                                                                           │   │
│  │  ┌──────┐ ┌──────┐ ┌────────┐ ┌────────┐ ┌────────┐                       │   │
│  │  │ ftyp │ │ moov │ │ moof_1 │ │ mdat_1 │ │ moof_2 │ ...                   │   │
│  │  └──────┘ └──────┘ └────────┘ └────────┘ └────────┘                       │   │
│  │     │       │         │          │          │                              │   │
│  │     │       │         └──────────┴──────────┘                              │   │
│  │     │       │              ↓                                               │   │
│  │     │       │         Virtual Segment (byte range)                        │   │
│  │     │       │              ↓                                               │   │
│  │     │       │         #EXT-X-BYTERANGE in m3u8                             │   │
│  │     │       │                                                              │   │
│  │     │       └─→ Contains track info (timescales, durations)               │   │
│  │     │                                                                      │   │
│  │     └─→ Init segment (first N bytes, contains ftyp+moov)                  │   │
│  │                                                                           │   │
│  │  Generates:                                                               │   │
│  │  • VOD playlist with #EXT-X-ENDLIST                                       │   │
│  │  • Virtual segments (6 second each by default)                            │   │
│  │  • #EXT-X-BYTERANGE for each segment                                      │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Output: stream.m3u8 (VOD playlist with 877 segments for 5258s movie)           │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  TRANSMUX SERVER (HTTP)                                                          │
│  ─────────────────────────                                                       │
│  📁 TransmuxCore/Sources/TransmuxCore/Core/TransmuxServer.swift                  │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  NWListener on localhost:8100 (or next available port)                    │   │
│  │                                                                           │   │
│  │  Endpoints:                                                               │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │   │
│  │  │ GET /stream.m3u8                                                    │  │   │
│  │  │     → Returns HLS VOD playlist                                      │  │   │
│  │  │     → Content-Type: application/vnd.apple.mpegurl                   │  │   │
│  │  ├─────────────────────────────────────────────────────────────────────┤  │   │
│  │  │ GET /init.mp4                                                       │  │   │
│  │  │     → Returns ftyp+moov (init segment)                              │  │   │
│  │  │     → Content-Type: video/mp4                                       │  │   │
│  │  ├─────────────────────────────────────────────────────────────────────┤  │   │
│  │  │ GET /seg_XXX                                                        │  │   │
│  │  │     → Returns byte range of fMP4 for segment XXX                    │  │   │
│  │  │     → Handles Range: bytes=START-END header                         │  │   │
│  │  │     → Fullness gate: waits until segment data is complete           │  │   │
│  │  ├─────────────────────────────────────────────────────────────────────┤  │   │
│  │  │ GET /sub_XX.m3u8                                                    │  │   │
│  │  │     → Returns subtitle playlist                                     │  │   │
│  │  ├─────────────────────────────────────────────────────────────────────┤  │   │
│  │  │ GET /sub_XX.vtt                                                     │  │   │
│  │  │     → Returns WebVTT subtitle file                                  │  │   │
│  │  └─────────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                           │   │
│  │  Key Features:                                                            │   │
│  │  • Fullness gate: Waits for segment to be complete before serving        │   │
│  │  • Seek redirect: Handles seeks to untransmuxed regions                  │   │
│  │  • Timeout handling: 404 if segment not available in time                │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Logs to: TransmuxLog → /tmp/mks-iptv-transmux.log                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  AVPLAYER (Apple Native)                                                         │
│  ─────────────────────────                                                       │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  AVPlayerItem(url: "http://localhost:8100/stream.m3u8")                   │   │
│  │                                                                           │   │
│  │  1. Fetches master.m3u8 (or stream.m3u8 directly)                        │   │
│  │  2. Parses #EXT-X-VERSION, #EXT-X-TARGETDURATION, etc.                   │   │
│  │  3. Requests init.mp4 (ftyp+moov)                                        │   │
│  │  4. Requests seg_000, seg_001, seg_002... progressively                  │   │
│  │  5. Decodes H.264/H.265 video, AAC/AC3/EAC3 audio                        │   │
│  │  6. Renders to CAMetalLayer / AVPlayerLayer                              │   │
│  │                                                                           │   │
│  │  On Seek:                                                                 │   │
│  │  1. Calculates target segment (e.g., seg_275 for 1650s)                  │   │
│  │  2. Requests seg_275 from TransmuxServer                                 │   │
│  │  3. Server may trigger SEEK-REDIRECT if not yet transmuxed               │   │
│  │  4. FFmpeg seeks, transmuxes, server serves                              │   │
│  │  5. AVPlayer resumes playback                                            │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  Output: Video frames to screen, Audio to speakers                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  UI LAYER (SwiftUI)                                                              │
│  ───────────────────                                                             │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  NativeAVPlayerViewController (iOS/tvOS)                                 │   │
│  │  NativeAVPlayerView (macOS)                                              │   │
│  │  📁 mks-.../Core/Player/NativePlayerRepresentable.swift                  │   │
│  │                                                                           │   │
│  │  • Provides native transport controls (play/pause/seek)                  │   │
│  │  • Shows scrubber, volume, AirPlay, PiP buttons                          │   │
│  │  • iOS 26+: Liquid Glass controls                                        │   │
│  │  • Handles subtitle/audio track selection                                │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  MKSPlayerView                                                            │   │
│  │  📁 mks-.../Features/Player/MKSPlayerView.swift                          │   │
│  │                                                                           │   │
│  │  • Unified player component (inline + fullscreen modes)                  │   │
│  │  • Debug overlay (triple-tap to toggle)                                  │   │
│  │  • Metadata overlay (title, rating, etc.)                                │   │
│  │  • Dismiss button, fullscreen button                                     │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────┐   │
│  │  PlayerDebugOverlay                                                       │   │
│  │  📁 mks-.../Features/Player/PlayerDebugOverlay.swift                     │   │
│  │                                                                           │   │
│  │  Shows: Buffer ahead, Bitrate, Stalls, Status, Rate, Time                │   │
│  │  TODO: Glitch detection, A/V sync, seek latency                          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## File Reference Summary

### Swift App Layer
| File | Purpose |
|------|---------|
| `mks-.../Core/Player/PlayerProtocol.swift` | VideoPlayerProtocol, PlayerError, PlayerType, PlayerConfiguration |
| `mks-.../Core/Player/PlayerFactory.swift` | Player creation, format detection, best player selection |
| `mks-.../Core/Player/AVPlayerImplementation.swift` | Native AVPlayer wrapper, time observer, buffering monitoring |
| `mks-.../Core/Player/FFmpegPlayerImplementation.swift` | Transmux pipeline orchestration, AVPlayer wrapper |
| `mks-.../Core/Player/VLCPlayerImplementation.swift` | VLC fallback player |
| `mks-.../Core/Player/NativePlayerRepresentable.swift` | SwiftUI wrappers for AVPlayerViewController/AVPlayerView |
| `mks-.../Features/Player/MKSPlayerView.swift` | Unified player UI component |
| `mks-.../Features/Player/PlayerDebugOverlay.swift` | Debug metrics display |
| `mks-.../Features/Player/FullscreenPlayerPresenter.swift` | Fullscreen presentation modifier |

### TransmuxCore Layer
| File | Purpose |
|------|---------|
| `TransmuxCore/.../Core/TransmuxingService.swift` | Main transmux orchestration, FFmpeg Swift wrapper |
| `TransmuxCore/.../Core/TransmuxServer.swift` | HTTP server for HLS/fMP4 serving |
| `TransmuxCore/.../Core/HLSSegmenter.swift` | fMP4 box parsing, m3u8 generation |
| `TransmuxCore/.../Core/ActiveTransmux.swift` | Session handle, seek signaling |
| `TransmuxCore/.../Core/TransmuxLog.swift` | Structured file logging |

### C Bridge Layer
| File | Purpose |
|------|---------|
| `TransmuxCore/.../CFFmpegHelper/FFmpegStreamHelper.c` | FFmpeg C API wrapper |
| `TransmuxCore/.../CFFmpegHelper/include/FFmpegStreamHelper.h` | Header for Swift interop |
| `TransmuxCore/.../CFFmpegHelper/include/module.modulemap` | Module map for C import |

## Key Data Flows

### 1. Play Flow
```
User Play → PlayerFactory → FFmpegPlayerImplementation
    → TransmuxingService.startTransmux()
        → CFFmpegHelper (avformat_open_input)
        → HLSSegmenter created
    → TransmuxServer.start()
    → AVPlayerImplementation.load(hlsURL)
    → AVPlayer.play()
```

### 2. Segment Request Flow
```
AVPlayer requests seg_XXX
    → TransmuxServer handles GET /seg_XXX
    → Fullness gate checks if segment data complete
    → If complete: serve byte range from fMP4
    → If not: wait with polling until transmux catches up
    → Return 206 Partial Content
```

### 3. Seek Flow
```
User drags scrubber to 1650s
    → AVPlayer requests seg_275 (1650/6 = 275)
    → TransmuxServer detects seg_275 > latestTransmuxed
    → SEEK-REDIRECT triggered
    → Signal sent to ActiveTransmux.seekHandle
    → TransmuxingService receives seek signal
    → av_seek_frame() in CFFmpegHelper
    → Timestamps rebased with global offset
    → Transmux continues from new position
    → TransmuxServer serves seg_275 when ready
```

### 4. Glitch Detection Points (TODO)
```
┌─────────────────────────────────────────────────────────────────────────────┐
│  GLITCH DETECTION OPPORTUNITIES                                             │
│                                                                             │
│  [A] Video Freeze:                                                          │
│      Monitor: currentTime not advancing while isPlaying=true                │
│      Location: AVPlayerImplementation time observer                         │
│                                                                             │
│  [B] Buffer Underrun:                                                       │
│      Monitor: loadedTimeRanges < threshold while playing                    │
│      Location: AVPlayerImplementation time observer                         │
│                                                                             │
│  [C] Seek Latency:                                                          │
│      Monitor: Time from seek() call to completion callback                  │
│      Location: AVPlayerImplementation.seek(to:)                             │
│                                                                             │
│  [D] Segment Timeout:                                                       │
│      Monitor: TIMEOUT 404 in TransmuxServer logs                            │
│      Location: TransmuxServer segment serving                               │
│                                                                             │
│  [E] A/V Desync:                                                            │
│      Monitor: DTS/PTS drift between video and audio tracks                  │
│      Location: TransmuxingService remux loop (needs implementation)         │
│                                                                             │
│  [F] Segment Gap:                                                           │
│      Monitor: Non-sequential segment requests from AVPlayer                 │
│      Location: TransmuxServer request handling                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Log Files

| Log File | Source | Content |
|----------|--------|---------|
| `/tmp/mks-iptv-transmux.log` | TransmuxLog | Server events, segment serves, seeks, timeouts |
| `/tmp/mks-iptv-player.log` | PlayerLog (TODO) | Client-side glitches, buffering, seeks |

## Next Steps

1. Implement `PlayerLog.swift` for structured client-side logging
2. Implement `GlitchDetector` for real-time anomaly detection
3. Enhance `PlayerDebugOverlay` with glitch history
4. Add seek latency tracking to `AVPlayerImplementation`
5. Add A/V sync monitoring to `TransmuxingService`

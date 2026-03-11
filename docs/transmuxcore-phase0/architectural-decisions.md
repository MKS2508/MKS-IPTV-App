# TransmuxCore v3 — Architectural Decisions

This document records all architectural decisions for the Tier 2/3 video transcoding implementation. Each decision includes context, options considered, choice made, and rationale.

---

## AD-01: C Library Naming

**Context**: The existing C target is called `CFFmpegHelper`. We're expanding it from 1 file to 10 modules with FFI-friendly API.

**Options**:
1. Keep `CFFmpegHelper` (backward compatible)
2. Rename to `CTransmuxFFI` (reflects FFI purpose)
3. Rename to `CTransmuxCore` (mirrors Swift target)

**Choice**: `CTransmuxFFI`

**Rationale**: The "FFI" suffix signals that this is a standalone C library usable from any language (Swift, Python, Kotlin). This enables future reuse beyond the Swift app. `CTransmuxCore` would create confusion with the Swift `TransmuxCore` target.

---

## AD-02: C Architecture — 10 Modular Files

**Context**: `FFmpegStreamHelper.c` is 1601 lines containing all C functionality. Adding MKSVideoTranscoder would push it to ~2200+ lines.

**Options**:
1. Continue adding to monolithic file
2. Split into focused modules

**Choice**: Split into 10 modules

**Modules**:
- `mks_common.c` — Error codes, logging
- `mks_format.c` — Format context management
- `mks_stream.c` — Stream inspection with layout detection
- `mks_packet.c` — Packet helpers
- `mks_seek.c` — Seeking
- `mks_bsf.c` — Bitstream filters (incl. dts2pts)
- `mks_audio_transcoder.c` — Audio transcode (extracted from lines 982-1368)
- `mks_video_transcoder.c` — Video transcode (NEW)
- `mks_subtitle.c` — Subtitle extraction (extracted from lines 786-976)
- `mks_tier.c` — Tier detection
- `mks_diagnostics.c` — Runtime layout detection

**Rationale**: Separation of concerns. Each module is independently testable. New developers can understand one module without reading 2000+ lines. FFI consumers can link only what they need.

---

## AD-03: Video Transcoder in C (not Swift)

**Context**: Should MKSVideoTranscoder be implemented in C or Swift?

**Options**:
1. C implementation (like MKSAudioTranscoder)
2. Swift implementation using FFmpeg C APIs directly

**Choice**: C implementation

**Rationale**: MKSAudioTranscoder (lines 982-1368 in FFmpegStreamHelper.c) is a proven pattern. FFmpeg struct access requires runtime layout detection that works in C. Swift's ClangImporter sometimes generates incorrect bindings for complex FFmpeg structs. The `void*` pattern for passing FFmpeg pointers to Swift is already established and working.

---

## AD-04: Encoder API — FFmpeg's h264/hevc_videotoolbox

**Context**: Two approaches to VideoToolbox hardware encoding:
1. Use FFmpeg's `h264_videotoolbox` / `hevc_videotoolbox` encoder wrappers
2. Use VTCompressionSession directly via Apple's framework

**Choice**: FFmpeg's h264/hevc_videotoolbox

**Rationale**:
- Consistent with existing codebase (all FFmpeg APIs)
- FFmpeg's wrapper is thin (~500 LOC in FFmpeg source) with negligible overhead
- Same performance as raw VTCompressionSession
- Handles edge cases (pixel format negotiation, session recovery) that we'd otherwise implement manually
- New FFmpeg 7-8 options (spatialaq, power_efficient, qmin/qmax) are exposed through av_opt_set
- KSPlayer uses raw VTDecompressionSession for decode; we use FFmpeg for both decode and encode, simpler architecture

---

## AD-05: Bitrate Strategy — VBR with qmin/qmax (NOT CRF)

**Context**: How to control output quality/size for transcoded video.

**Options**:
1. CRF (Constant Rate Factor) — common for x264/x265
2. CBR (Constant Bitrate) — fixed output rate
3. VBR with qmin/qmax — variable with quality bounds

**Choice**: VBR with qmin/qmax

**Rationale**: **CRF is IGNORED by VideoToolbox hardware encoder**. This is a critical finding that many projects get wrong. VT hardware doesn't support CRF mode. VBR with qmin/qmax (FFmpeg 7-8 feature) gives quality bounds while allowing the encoder to optimize bitrate allocation. CBR wastes bits on simple scenes. Resolution-based bitrate caps (2-20 Mbps) prevent excessive output size.

---

## AD-06: VT Encoder Options — spatialaq + power_efficient

**Context**: FFmpeg 7-8 added new VideoToolbox encoder options not available in FFmpeg 6.x (and therefore not in KSPlayer).

**Choice**: Enable `spatialaq=1` always, `power_efficient=1` on battery

**Rationale**:
- `spatialaq` (spatial adaptive quantization) improves perceptual quality by allocating more bits to complex regions. No meaningful performance cost.
- `power_efficient` tells the VT encoder to prefer power-saving encoding paths. Essential for mobile (iPhone/iPad on battery).
- These are FFmpeg 7-8 exclusive features that KSPlayer (on 6.1.3) cannot use.

---

## AD-07: Transcode Timing — Real-time During Remux Loop

**Context**: When should video transcoding happen?

**Options**:
1. Pre-transcode entire file before playback
2. Real-time transcode during the remux loop (progressive)

**Choice**: Real-time during remux loop

**Rationale**: Matches existing progressive fMP4 architecture. Playback starts immediately (no waiting for full transcode). Seeking triggers flush+re-encode from new position. Same pattern as MKSAudioTranscoder integration. HLSSegmenter generates VOD playlist as segments arrive.

---

## AD-08: Seek Handling — Flush + Reset PTS

**Context**: How to handle seeking during active video transcoding.

**Choice**: Flush decoder + encoder, reset PTS counters, rebase timestamps

**Rationale**: Identical to MKSAudioTranscoder seek pattern (already proven in production). Steps:
1. Signal seek via ActiveTransmux
2. `av_seek_frame` on input
3. `mks_video_transcoder_reset()` — flushes both decoder and encoder buffers
4. Reset global offset for timestamp rebasing
5. Continue remux loop from new position

---

## AD-09: Memory — 2 Pre-allocated Frames

**Context**: How much memory does video transcoding need?

**Choice**: 2 pre-allocated AVFrames per session (~6-8MB at 1080p)

**Rationale**: The pipeline is synchronous: decode -> convert -> encode. Only 2 frames are ever needed simultaneously:
- `decodedFrame`: output from decoder
- `convertedFrame`: input to encoder (NV12 format)

No ring buffer needed (unlike KSPlayer's CircularBuffer with NSCondition). Frames are allocated once in `create()` and reused via `av_frame_make_writable()`.

---

## AD-10: Output Codec — H.264 Default, H.265 for 4K/HDR

**Context**: What codec should the VideoToolbox encoder produce?

**Choice**: H.264 by default, H.265 for 4K and HDR content

**Rationale**:
- H.264: Universal compatibility, lower encode latency, all Apple devices
- H.265: Better compression efficiency at high resolutions, required for HDR metadata passthrough

**Selection logic**:
- 4K (>=2160p): H.265 always
- 1440p: H.265 always
- 1080p with HDR: H.265
- Everything else: H.264

---

## AD-11: PTS Fixing — dts2pts BSF

**Context**: IPTV streams frequently have PTS reordering issues causing playback stuttering.

**Choice**: Use `dts2pts` bitstream filter (FFmpeg 7+) when IPTV PTS issues are detected

**Rationale**: This BSF was introduced in FFmpeg 7 specifically to fix PTS reordering problems. KSPlayer on FFmpeg 6.1.3 cannot use it. The BSF corrects DTS-to-PTS mapping, ensuring monotonically increasing presentation timestamps. Applied automatically when `TierDecisionEngine` detects IPTV stream characteristics.

---

## AD-12: fMP4 Flags — CMAF Movflag

**Context**: Current code uses verbose `frag_keyframe+empty_moov+default_base_moof` for fMP4 fragmentation.

**Choice**: Use `cmaf` movflag (FFmpeg 7+ shorthand)

**Rationale**: `cmaf` is a single flag that combines all three. Cleaner code, same output. CMAF (Common Media Application Format) is the industry standard for fragmented MP4.

---

## AD-13: Thread Model — Swift Actors + os_unfair_lock

**Context**: KSPlayer uses NSCondition for thread synchronization (heavyweight, Objective-C).

**Choice**: Swift actors for Swift-side concurrency, os_unfair_lock for C-side critical sections

**Rationale**:
- Swift actors provide compile-time thread safety guarantees
- os_unfair_lock is the lightest kernel lock on Apple platforms
- NSCondition involves Objective-C message dispatch overhead on every lock/unlock
- Our synchronous pipeline minimizes lock contention (sequential decode->encode)

---

## AD-14: Swift Architecture — Protocol-Oriented, ~30 Files

**Context**: KSPlayer uses god objects (KSOptions 680 LOC, MEPlayerItem 881 LOC). Our TransmuxingService is 2437 LOC.

**Choice**: Split into ~30 files organized by domain

**Domains**:
- `API/` — Public re-exports, options, session types
- `Protocols/` — Transcoder, AVSync, StreamProxy protocols
- `FFmpeg/` — Type-safe Swift wrappers over CTransmuxFFI
- `Tier/` — Decision engine, bitrate calculator, codec capabilities
- `Pipeline/` — TransmuxingService (modified), packet processor
- `Serving/` — HTTP server, route handlers
- `HLS/` — Segmenter, box parser, live proxy
- `Seek/` — Seek controller, timestamp rebaser
- `Cache/` — Segment cache
- `Logging/` — Structured logger
- `Session/` — Active transmux handle

**Rationale**: Each file has a single responsibility. New developers can navigate by domain. Protocols enable testing with mocks. Extracted logic (PacketProcessor, TimestampRebaser) eliminates code duplication between audio and video transcoding paths.

---

## AD-15: HDR Passthrough — av_frame_copy_props + Color Properties

**Context**: VideoToolbox transcoding converts pixel format to NV12 but HDR metadata must be preserved separately.

**Choice**: Copy frame properties and color info after sws_scale in convert_to_nv12()

**Rationale**:
- `av_frame_copy_props()` copies all side data (HDR10 metadata, Dolby Vision, content light level)
- Explicit color property copy ensures VideoToolbox encoder receives correct color space info
- Without this, HDR content appears washed out in SDR color space

**Implementation** (`mks_video.c:convert_to_nv12()`):
```c
av_frame_copy_props(ctx->nv12Frame, ctx->decodedFrame);
ctx->nv12Frame->color_primaries = ctx->decodedFrame->color_primaries;
ctx->nv12Frame->color_trc = ctx->decodedFrame->color_trc;
ctx->nv12Frame->colorspace = ctx->decodedFrame->colorspace;
ctx->nv12Frame->color_range = ctx->decodedFrame->color_range;
```

---

## AD-16: VT Error Recovery — 3-Error Threshold + Software Fallback

**Context**: VideoToolbox encoder can fail (session invalidated, resources exhausted). KSPlayer implements retry + fallback. We had `allow_sw=1` but no error tracking.

**Choice**: Track consecutive VT errors, fall back to software encoder after 3 failures

**Rationale**:
- `AVERROR_EXTERNAL` signals VT-specific failures
- Transient errors may resolve; persistent errors indicate systemic issue
- Software encoder (libx264/libx265) is reliable fallback
- `allow_sw=1` was configured but never triggered without explicit tracking

**Implementation** (`mks_video.c`):
- `vtErrorCount` — tracks consecutive VT encoder errors
- `usingSwFallback` — prevents repeated fallback attempts
- `find_sw_encoder()` — locates libx264/libx265 encoder
- Retry with SW encoder in `drain_decoded_frame()` after 3 VT errors

---

## AD-17: A/V Sync Controller — KSPlayer 3-Tier Escalation

**Context**: Tier 2/3 video transcode requires explicit A/V sync management. AVPlayer handles sync natively for passthrough, but transcoded streams need drift detection.

**Choice**: Extract KSPlayer's sync algorithm into `AVSyncController` protocol with 3-tier escalation

**Rationale**:
- KSPlayer's algorithm is battle-tested across many content types
- Protocol-based design allows different implementations per tier
- Thresholds calibrated for transcode scenarios (not live capture)

**Thresholds**:
- Normal: drift < 4 frames (~133ms at 30fps)
- Light correction: 4-8 frames → drop 1 frame
- Heavy correction: 8 frames to 8 seconds → drop to keyframe
- Catastrophic: > 8 seconds → seek to audio position

**Implementation** (`AVSyncController.swift`):
- `SyncAction` enum: present, dropFrame, dropToKeyframe, seekToAudio
- `TranscodeAVSyncController` — for Tier 2/3 (active sync management)
- `PassthroughAVSyncController` — for Tier 0/1 (no-op, AVPlayer handles)
- `AVSyncControllerFactory` — creates appropriate controller per tier

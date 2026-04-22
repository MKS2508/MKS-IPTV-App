# Stremio Addon Codecs & VideoToolbox Advances Research

> Research conducted: March 2026

---

## Topic 1: Stremio Addon Codec Usage

### 1.1 Container Formats

Stremio addons (primarily Torrentio and similar torrent-based addons) serve content from the torrent ecosystem. The most common container formats are:

| Container | Prevalence | Notes |
|-----------|------------|-------|
| **MKV (Matroska)** | ~70-80% | Dominant format for high-quality releases; supports multiple audio/subtitle tracks |
| **MP4** | ~15-20% | Common for web-optimized content, YTS releases |
| **MKV** | ~5-10% | WebM is NOT supported (confirmed Stremio bug #900) |

**Key Insight**: MKV is overwhelmingly dominant because it:
- Supports unlimited audio tracks (important for multi-language releases)
- Supports ASS/SSA subtitles (stylized subtitles)
- Handles high-bitrate content better
- Is the de facto standard for P2P releases

### 1.2 Video Codecs

| Codec | Prevalence | Notes |
|-------|------------|-------|
| **H.264 (AVC)** | ~50-60% | Most compatible; widely seeded |
| **H.265 (HEVC)** | ~25-35% | Growing, especially for 4K/HDR content |
| **x264** | Included in H.264 | Software-encoded H.264 |
| **x265** | Included in HEVC | Software-encoded HEVC |
| **VP9** | ~5% | Limited presence in torrents |
| **AV1** | <5% | Emerging but rare in torrent ecosystem |
| **MPEG-2** | Rare | Old DVDs; practically nonexistent |

#### VP9 Deep Dive

**In Torrents/Stremio**:
- ~5% of torrent content uses VP9
- Primarily found in: YouTube-dl exports, some WEB-DL content
- Container usually MKV or WebM
- Audio: Often Opus or Vorbis
- 10-bit VP9 profiles available but rare

**Why VP9 is Rare in Torrents**:
1. **Hardware decoder adoption**: Limited compared to H.264/H.265
2. **Encoding speed**: Slower than H.264, no major advantage over x265
3. **No BD/UHD disc source**: All commercial disc content uses H.264/HEVC
4. **YouTube-focused**: Main source is YouTube rips
5. **Compatibility concerns**: Older devices don't support VP9

**VP9 Profiles**:
- Profile 0: 8-bit,YCbCr 4:2:0
- Profile 1: 8-bit, YCbCr 4:2:2/4:4:4
- Profile 2: 10-bit/12-bit, 4:2:0
- Profile 3: 10-bit/12-bit, 4:2:2/4:4:4

**Streaming Usage** (Contrast):
- YouTube: VP9 dominant (~60-70% of 4K content)
- Netflix: H.264, H.265, AV1 (no VP9)
- Amazon Prime: H.264, H.265
- Web: VP9 used in Chrome/Firefox for royalty-free option

**Resolution Distribution** (approximate):
- 1080p: ~60-70%
- 720p: ~15-20%
- 4K/UHD: ~10-15%
- 480p/SDr: ~5%

**Quality Labels Common in Torrent Names**:
- `BluRay` / `Blu-ray` / `BRRIP`
- `WEB-DL` / `WEBRip`
- `HDRip` / `HDTV`
- `HDR` / `HDR10` / `Dolby Vision`
- `Remux` (full quality, remuxed from disc)
- `Encode` (re-encoded)
- `YIFY` / `YTS` (specific release groups)

### 1.3 Audio Codecs

| Codec | Prevalence | Notes |
|-------|------------|-------|
| **AAC** | ~40-50% | Most common; good quality/size balance |
| **AC3 (Dolby Digital)** | ~25-30% | Standard for 5.1 surround |
| **EAC3 (Dolby Digital Plus)** | ~10-15% | Growing; used in Blu-rays |
| **DTS** | ~5-10% | Legacy; being phased out |
| **DTS-HD MA** | ~5% | High-quality Blu-ray audio |
| **TrueHD** | ~3-5% | Lossless; Blu-ray premium audio |
| **FLAC** | ~5-8% | Lossless; increasingly popular |
| **Opus** | Rare | Mostly in WebM files |
| **Vorbis** | Rare | Older WebM files |

**Audio Channels**:
- Stereo (2.0): ~30-40%
- 5.1 Surround: ~50-60%
- 7.1 Surround: ~5-10%

### 1.4 Subtitle Formats

| Format | Prevalence | Notes |
|--------|------------|-------|
| **SRT** | ~50-60% | Most universal; simple text |
| **ASS/SSA** | ~25-35% | Advanced styling; common in anime |
| **PGS (Presentation Graphics Stream)** | ~10-15% | Blu-ray "hardcoded" subtitles |
| **VobSub** | ~5% | Older format; being phased out |
| **SUB** | ~3-5% | Generic subtitle format |
| **WebVTT** | Rare | Web-native; not common in torrents |

**Important**: Stremio handles external subtitles well but has issues with:
- PGS/VobSub (must be extracted/burned)
- WebM containers (not supported at all per bug #900)
- HEVC on Chromium browsers (bug #644 - black screen)

### 1.5 Codec Distribution by Source

**YTS (YIFY)**:
- Container: MP4
- Video: H.264
- Audio: AAC stereo
- Target: Small file size, wide compatibility

**RARBG**:
- Container: MKV (majority), MP4
- Video: H.264, H.265 (growing)
- Audio: AAC, AC3, EAC3, FLAC
- Quality: Generally higher than YTS

**Public Trackers (1337x, TPB, etc.)**:
- Mixed content
- MKV dominant
- All codecs represented

### 1.6 Edge Cases & Unusual Combinations

### 1.7 Typical Torrent Combinations (Lo Más Común)

**Las combinaciones más frecuentes que encontrarás en torrents:**

| Escenario | Contenedor | Video | Audio | Subtitulos | Notas |
|-----------|------------|-------|-------|------------|-------|
| **Película 1080p estándar** | MKV | H.264 | AAC 2.0 / AC3 5.1 | SRT | El 50% de los torrents |
| **Película 1080p alta calidad** | MKV | H.264 | EAC3 / FLAC | ASS/SSA | release de RARBG |
| **Película 4K HDR** | MKV | H.265 (HEVC) | EAC3 / TrueHD | SRT / PGS |~10-15% del total |
| **Película 4K Dolby Vision** | MKV | H.265 | TrueHD / EAC3 | SRT | requiere reproductor compatible |
| **Serie TV** | MKV / MP4 | H.264 | AAC | SRT | episodes individuales |
| **Anime** | MKV | H.264 / H.265 | AAC / FLAC | ASS/SSA | muy común en anime |
| **YTS (pequeño)** | MP4 | H.264 | AAC 2.0 | - | archivos pequeños ~700MB-2GB |
| **Remux** | MKV | H.264 / H.265 | TrueHD / DTS-HD | - | máxima calidad, archivos grands |

**Porcentajes reales aproximados:**
```
MKV + H.264 + AAC = ~35%    ← LO MÁS COMÚN
MKV + H.264 + AC3 = ~20%
MKV + H.265 + AAC = ~15%
MKV + H.265 + EAC3 = ~10%
MP4 + H.264 + AAC = ~12%    ← YTS y web
Otros = ~8%
```

**Qué buscar para mejor calidad:**
1. **Remux** → Calidad original del disco
2. **BluRay 1080p/4K** → Encode sin pérdida
3. **HDR / Dolby Vision** → Para TVs compatibles
4. **EAC3 / TrueHD / FLAC** → Mejor audio
5. **Tamaño** → Mayor tamaño = mejor calidad (generalmente)

1. **HDR + Dolby Vision**: Requires specific naming (`BluRay`, `HDR`, `DV`, `DoVi`) and HEVC encoding
2. **Anime**: Heavily ASS/SSA subtitles, often MKV + H.264
3. **Remuxes**: Direct stream copy from Blu-ray; largest files, highest quality
4. **Scene Releases**: Often have lower compatibility (specific scene naming conventions)
5. **x264/x265 vs h264/h265**: Software vs hardware encoding notation
6. **10-bit**: Common notation (`10bit`, `x265 10-bit`) for better color grading

---

## Topic 2: VideoToolbox Advances (iOS 17+ / macOS 14+)

### 2.1 VTCompressionSession New Options

**iOS 17 / macOS 14+ Key Additions**:

- **Multi-pass encoding support** (WWDC14): Improved quality through multiple encoding passes
- **Low-latency encoding**: `kVTCompressionPropertyKey_RealTime` property for live streaming
- **Temporal SVC (Scalable Video Coding)**: Layered encoding for adaptive bitrate
- **Improved profile support**: Better HEVC Main 10 profile handling

**Key Compression Properties**:
```swift
kVTCompressionPropertyKey_AverageBitRate
kVTCompressionPropertyKey_DataRateLimits
kVTCompressionPropertyKey_ExpectedFrameRate
kVTCompressionPropertyKey_RealTime
kVTCompressionPropertyKey_AllowFrameReordering // GOP structure
kVTCompressionPropertyKey_MaxKeyFrameInterval
kVTCompressionPropertyKey_ProfileLevel
```

### 2.2 VTDecompressionSession Improvements

- **Hardware-accelerated decoding** for all major codecs
- **Pixel buffer pool optimization**: Reduced memory allocation overhead
- **Metal integration**: Direct decoding to Metal textures
- **Better HDR pipeline**: Improved Dolby Vision / HDR10 handling

### 2.3 AV1 Hardware Decode Support

| Chip | AV1 Decode | AV1 Encode | Notes |
|------|------------|------------|-------|
| **A17 Pro** | Yes | No | iPhone 15 Pro (2023) |
| **A18 / A18 Pro** | Yes | No | iPhone 16 series |
| **M3 / M3 Pro / M3 Max** | Yes | No | MacBook Pro, iMac, Mac mini (2023) |
| **M4 / M4 Pro / M4 Max** | Yes | No | iPad Pro, MacBook Air (2024) |
| **M2 and earlier** | Software | Software | No hardware AV1 |
| **A16 and earlier** | Software | Software | No hardware AV1 |

#### VP9 Hardware Support (VideoToolbox)

| Chip | VP9 Decode | VP9 Encode | Notes |
|------|------------|------------|-------|
| **Apple Silicon (all M-series)** | **No** | **No** | No hardware VP9 |
| **A12 Bionic and later** | Software | Software | CoreVideo VP9 decoder |
| **Intel Macs** | QuickSync (some) | No | Limited |
| **T2 Coprocessor** | No | No | No VP9 hardware |

**Key Points**:
- Apple **never added** hardware VP9 encode/decode to any chip
- Software VP9 decoding available via `CMVideoCodecType.kCMVideoCodecType_VP9`
- VP9 decode is **not hardware-accelerated** on Apple platforms
- Energy consumption is significantly higher than H.264/HEVC
- **No hardware encoding** - must use libvpx (software)

**VP9 via VideoToolbox**:
```swift
// Available but software-only
let decoderSpecification = [
    kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: false
] as CFDictionary

// CMVideoCodecType values:
// kCMVideoCodecType_VP9 = 'vp09'
```

### 2.4 HEVC Encoding Improvements

**Quality Improvements**:
- Better rate control algorithms
- Improved grain handling
- Enhanced perceptual quality

**HEVC Profiles Supported**:
- `kVTProfileLevel_HEVC_Main_Auto`
- `kVTProfileLevel_HEVC_Main10_Auto` (10-bit)
- `kVTProfileLevel_HEVC_Main10_HDR10` (HDR10)
- `kVTProfileLevel_HEVC_Main10_HLG` (HLG)
- `kVTProfileLevel_HEVC_Main_DolbyVision` (Dolby Vision)

**Apple Silicon Advantages**:
- Hardware HEVC encode/decode on all M-series chips
- M1 Pro/Max/Ultra: Enhanced media engine
- Energy efficiency for mobile encoding

### 2.5 Low-Latency Encoding

**WWDC21 - "Explore low-latency video encoding with VideoToolbox"**:

- **Real-time property**: `kVTCompressionPropertyKey_RealTime`
- **Reduced frame buffer**: Minimizes encode delay
- **Use cases**: Video conferencing, live streaming, gaming
- **Caveat**: May sacrifice some compression efficiency

**New in iOS 26 / macOS 15.4**:
- **VTFrameProcessor API**: AI-powered video effects
- **VTLowLatencyFrameInterpolationConfiguration**: Frame interpolation
- **Super resolution**: ML-based upscaling
- **Noise filtering**: ML-based noise reduction

### 2.6 ProRes Encoding

**ProRes Capabilities via VideoToolbox**:

| ProRes Variant | Encode | Decode | Notes |
|----------------|--------|--------|-------|
| **ProRes 422** | Hardware | Hardware | Standard 422 |
| **ProRes 422 HQ** | Hardware | Hardware | High quality |
| **ProRes 422 LT** | Hardware | Hardware | Lightweight |
| **ProRes 422 Proxy** | Hardware | Hardware | Low data rate |
| **ProRes 4444** | Hardware | Hardware | Alpha channel |
| **ProRes 4444 XQ** | Hardware | Hardware | Extreme quality |

**WWDC20 - "Decode ProRes with AVFoundation and VideoToolbox"**:
- Optimal decoding pipelines
- Metal integration for display
- Afterburner card support (Intel Mac Pro)

**Apple Silicon**:
- Dedicated ProRes encode/decode engine on all M-series
- Significantly faster than Intel QuickSync

### 2.7 HDR Transcoding

**HDR10 Passthrough**:
- Supported via `kVTProfileLevel_HEVC_Main10_HDR10`
- Automatic metadata passthrough
- Mastering display metadata preserved
- Content light metadata preserved

**HLG (Hybrid Log-Gamma)**:
- Supported via `kVTProfileLevel_HEVC_Main10_HLG`
- Broadcast-standard HDR

**Dolby Vision**:
- Profile 8.1 support (most common)
- Metadata handling via `CMVideoYCbCrMatrix`
- Dynamic metadata preserved when using proper profiles
- **Known Issue**: HandBrake reports green picture with Dolby Vision on M2 Pro (fixed in 1.9.0 for most cases)

**HDR10+**:
- Supported via x265 and SVT-AV1 encoders
- VideoToolbox HEVC supports HDR10+ dynamic metadata (since ~2023)

### 2.8 Multi-Pass Encoding

**Supported via VideoToolbox**:
- Yes, multi-pass H.264 encoding is supported
- Enabled via `kVTCompressionPropertyKey_AllowMultiplePasses`
- Requires `kVTCompressionPropertyKey_MaxFrameDelay` configuration
- **WWDC14**: "Direct Access to Video Encoding and Decoding" introduced multi-pass

**Usage**:
```swift
// Enable multi-pass
VTSessionSetProperty(session, 
    key: kVTCompressionPropertyKey_AllowMultiplePasses, 
    value: kCFBooleanTrue)
```

**Limitation**: Quality improvement is modest compared to software encoders; primarily benefits bitrate efficiency

### 2.9 Constant Quality Mode (CQ/CRF)

**VideoToolbox Behavior**:

| Mode | Support | Notes |
|------|---------|-------|
| **CBR (Constant Bitrate)** | Native | Uses `kVTCompressionPropertyKey_AverageBitRate` |
| **VBR (Variable Bitrate)** | Native | Uses `DataRateLimits` |
| **CQ/CRF** | **Limited/Problematic** | Hardware doesn't truly support CRF |

**Important Discovery**:
- VideoToolbox hardware encoder **does NOT properly support CRF**
- Setting CRF values is ignored by the hardware encoder
- File sizes come out unexpectedly small (quality sacrificed)
- **Workaround**: Use bitrate-based encoding or software encoders (x264, x265) for true constant quality

**FFmpeg h264_videotoolbox**:
```bash
# CRF is ignored - use bitrate instead
ffmpeg -i input.mp4 -c:v h264_videotoolbox -b:v 5M output.mp4

# For better quality with VT
ffmpeg -i input.mp4 -c:v hevc_videotoolbox -b:v 10M -q:v 2 output.mp4
```

**Quality Setting** (`-q:v`):
- Ranges 0-100 (lower = better quality)
- Only applies to ProRes
- For H.264/HEVC: Use bitrate control

### 2.10 WWDC Sessions (2021-2025)

| Year | Session | Topic |
|------|---------|-------|
| **WWDC25** | #300 | "Enhance your app with machine-learning-based video effects" - VTFrameProcessor, super resolution, frame interpolation |
| **WWDC24** | #10088 | "Capture HDR content with ScreenCaptureKit" |
| **WWDC24** | #10113 | "Discover media performance metrics in AVFoundation" |
| **WWDC21** | #10158 | "Explore low-latency video encoding with VideoToolbox" |
| **WWDC20** | #10090 | "Decode ProRes with AVFoundation and VideoToolbox" |
| **WWDC14** | #513 | "Direct Access to Video Encoding and Decoding" (multi-pass) |

### 2.11 FFmpeg VideoToolbox Options (2024-2025)

**Common FFmpeg Encoders**:
- `h264_videotoolbox`: H.264 hardware encoding
- `hevc_videotoolbox`: HEVC (H.265) hardware encoding
- `prores_ks`: ProRes encoding

**Recommended Settings**:
```bash
# H.264 - Best quality
ffmpeg -i input.mp4 -c:v h264_videotoolbox -b:v 8M -profile:v high -level 5.1 output.mp4

# HEVC - Good quality/size balance
ffmpeg -i input.mp4 -c:v hevc_videotoolbox -b:v 5M -profile:v main10 output.mp4

# ProRes 422 HQ - Professional quality
ffmpeg -i input.mp4 -c:v prores_ks -profile:v hq -qscale:v 2 output.mov
```

**Known Limitations**:
- CRF ignored by hardware encoder
- `-preset` options don't work (only applies to software encoders)
- `-tune` options have limited effect

---

## Summary: Practical Implications

### For Stremio App Development:
1. **Transcode for compatibility**: Convert MKV → MP4, HEVC → H.264 for web
2. **Audio transcode**: AC3/EAC3 → AAC for web compatibility
3. **Subtitle handling**: Extract PGS, convert to SRT/VTT
4. **HDR passthrough**: Keep HDR metadata when possible

### For VideoToolbox Implementation:
1. **Use bitrate control**: Don't rely on CRF/CQ
2. **AV1 decode only**: Encode via software (x265, SVT-AV1)
3. **HDR**: Profile-based encoding preserves metadata
4. **ProRes**: Full hardware support on Apple Silicon
5. **Low-latency**: Use `kVTCompressionPropertyKey_RealTime` for streaming

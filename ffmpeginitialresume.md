FFmpeg Changes: From 6.x to 8.x

Based on the comprehensive API documentation and changelogs, here's a detailed overview of all the major changes from
FFmpeg 6.x through 8.x:

--------

## Version 8.x Major Changes (Latest)

### New Encoders/Decoders

• VVC Decoder - Support for Versatile Video Coding (H.266) including all SCC content:
  • IBC (Inter Block Copy)
  • Palette Mode
  • ACT (Adaptive Color Transform)
• AV1 Vulkan Encoder - Hardware-accelerated AV1 encoding
• ProRes RAW Decoder - New ProRes RAW support
• APV Codec - Animated PNG Video support (encoding via libopenapv)
• Whisper Filter - Speech recognition/transcription via Whisper model
• G.728 Codec - New audio decoder
• Enhanced FLV v2 - Multitrack audio/video support with modern codecs

### Streaming Improvements

• HLS - Continued improvements and bug fixes
• DASH - Enhanced support for modern streaming formats
• DVD-Video - New demuxer powered by libdvdnav and libdvdread for direct DVD title ingestion

### Hardware Acceleration Updates

• VVC VAAPI Decoder - VAAPI support for H.266
• VP9 Vulkan HWAccel - Vulkan hardware acceleration
• ProRes RAW Vulkan HWAccel
• D3D12VA HEVC Encoder - Direct3D 12 hardware encoding
• QSV VVC Decoding - Intel QuickSync Video support for H.266

### API Changes

• C17 Compiler Required - Minimum compiler version bumped from C11 to C17
• YASM Support Dropped - Use NASM instead
• OpenSSL 1.1.0+ Required - Dropped support for older OpenSSL
• TLS Peer Verification - Certificate verification enabled by default (will become mandatory in next major version)

### New Features

• Color Detect Filter - Automatic color detection
• Perlin Video Source - Procedural noise texture generation
• LCEVC Filter - LCEVC enhancement layer processing
• MV-HEVC Decoding - Multi-view HEVC support

--------

## Version 7.x Major Changes

### New Encoders/Decoders

• IAMF - Immersive Audio Model and Format support (demuxer/muxer, MP4)
• QOA - Quite OK Audio format decoder
• Tilt and Shift Filter - New video transformation filter
• QR Encode - QR code generation and filtering
• Quirc Filter - QR code detection

### Streaming Improvements

• HLS - Added  -fix_sub_duration_heartbeat  option for better subtitle timing
• DASH - Enhanced support and new features
• Enhanced FLV - Support for HEVC, VP9, and AV1 codecs
• RTMP - Added fourcclist support

### Hardware Acceleration Updates

• D3D12VA - Hardware accelerated decoding for:
  • H.264, HEVC, VP9, AV1
  • MPEG-2, VC-1
• Vulkan - Decode hwaccel support for H.264, HEVC, AV1
  • Vulkan filters:  color_vulkan ,  bwdif_vulkan ,  nlmeans_vulkan ,  xfade_vulkan


### API Changes

• Parallel Processing - Demuxing, decoding, filtering, encoding, and muxing now run in parallel in ffmpeg CLI
• Bitstream Filters on Input -  -bsf  option now works for both input and output
• Option Files - CLI options can now be loaded from files using  -/opt <path>  syntax

### New Features

• HEIF/AVIF Support - Still image formats with tiled still image support
• HDR10 Metadata - Pass-through support in:
  • libx264
  • libx265
  • libsvtav1
• Dolby Vision Profile 10 - Support in AV1
• Ambient Viewing Environment - Metadata support in MP4
• DNN with PyTorch - New backend for DNN filters

### CLI Improvements

• New Stats Options:
  •  -stats_enc_pre[_fmt]  - Print encoding stats before each frame
  •  -stats_enc_post[_fmt]  - Print encoding stats after each frame
  •  -stats_mux_pre[_fmt]  - Print muxing stats
• Read Rate Initial Burst -  -readrate_initial_burst  option
• Zoneplate Video Source - New test pattern generator

--------

## Version 6.x Major Changes

### Streaming Overhaul

#### HLS (HTTP Live Streaming)

• Loopback Decoders - Support for loopback in HLS
• Enhanced Options:
  •  live_start_index  - Segment index to start live streams
  •  prefer_x_start  - Prefer #EXT-X-START over live_start_index
  •  allowed_extensions  - Control allowed file extensions
  •  max_reload  - Maximum reload attempts
  •  m3u8_hold_counters  - M3U8 refresh control
  •  http_persistent  - Persistent HTTP connections (default enabled)
  •  http_multiple  - Multiple HTTP connections (default enabled)
  •  http_seekable  - HTTP partial requests for segments
  •  seg_format_options  - Set segment format options
  •  seg_max_retry  - Maximum segment retry attempts


#### DASH (Dynamic Adaptive Streaming over HTTP)

• CENC AV1 Support - Common Encryption for AV1 in MP4
• Enhanced Metadata Support

#### Enhanced FLV

• Support for Modern Codecs:
  • HEVC (H.265)
  • VP9
  • AV1
• FourCC List Support

#### RTMP

• Enhanced Protocol - Support for HEVC, VP9, AV1 fourcclist
• Better Protocol Handling

### New Encoders/Decoders

#### Video Codecs

• NVDEC/NVENC AV1 - NVIDIA hardware acceleration for AV1
• QSV AV1 - Intel QuickSync Video AV1 encoding
• MediaCodec - Encoder and decoder via NDK (Android)
• DVD-Video Demuxer - Direct DVD title ingestion
• Various New Decoders:
  • Playdate video decoder
  • RivaTuner video decoder
  • vMix video decoder
  • CRI USM demuxer
  • Essential Video Coding (EVC) parser, muxer, demuxer


#### Audio Codecs

• Audio Source Filter -  afireqsrc  - Audio impulse response source
• Audio Filters:
  •  apsnr  - Audio peak signal-to-noise ratio
  •  asisdr  - Audio signal-to-distortion ratio
• OSQ Decoder - New audio codec support

### Hardware Acceleration Updates

#### VAAPI (Video Acceleration API)

• AV1 Encoder - First VAAPI AV1 encoder implementation
• Enhanced Decoding:
  • 10/12bit 422 and 444 HEVC and VP9 support
• Windows Support - Extended VAAPI support for libva-win32 on Windows

#### Vulkan

• Decode HWAccel - Hardware accelerated decoding for:
  • H.264
  • HEVC
  • AV1
• Multiple Vulkan Filters:
  •  color_vulkan
  •  bwdif_vulkan
  •  nlmeans_vulkan
  •  overlay_vulkan
  •  scale_vulkan
  •  chromaber_vulkan


#### VideoToolbox (macOS/iOS)

• New Filters:
  •  scale_vt  - Video scaling
  •  transpose_vt  - Video transposition
• Enhanced Support

#### CUDA (NVIDIA)

• New Filters:
  •  bwdif_cuda  - Bob deinterlacing
  •  overlay_cuda  - Overlay operations


#### QSV (Intel QuickSync Video)

• OneVPL Support - New oneAPI Video Processing Library support
• Enhanced Encoding/Decoding:
  • 10/12bit 422 and 444 HEVC and VP9 support


### CLI Improvements

#### New Options

• Buffer Duration -  -shortest_buf_duration  for better stream synchronization
• Stats Options:
  •  -stats_enc_pre[_fmt]
  •  -stats_enc_post[_fmt]
  •  -stats_mux_pre[_fmt]
• Subtitle Fixes -  -fix_sub_duration_heartbeat

#### Deprecated Options

•  -top  - Deprecated in favor of  setfield  filter
•  -psnr  and  -map_channel  - Removed

### Filters Enhancements

#### Video Filters

• Stacking Filters:
  •  hstack_vaapi / vstack_vaapi / xstack_vaapi  - VAAPI-accelerated
  •  hstack_qsv / vstack_qsv / xstack_qsv  - QSV-accelerated
• Detection:
  •  cropdetect  - New mode for motion vector and edge-based crop detection
  •  showcwt  - Show closed captions (CWT)
• Analysis:
  •  ssim360  - 360° SSIM calculation
  •  corr  - Correlation analysis
  •  a3dscope  - 3D audio scope visualization
• Processing:
  •  backgroundkey  - Background color keying
  •  ddagrab  - Desktop Duplication (Windows)
  •  adrc  - Dynamic Range Control audio filter
  •  afdelaysrc  - Audio delay source


#### Audio Filters

• New Analysis Filters:
  •  apsnr  - Peak signal-to-noise ratio
  •  asisdr  - Signal-to-distortion ratio
• Processing:
  •  adrc  - Dynamic range control
  •  arls  - RLS (Recursive Least Squares) filter


### Performance Improvements

#### Multithreading

• Muxer Threading - Every muxer now runs in a separate thread
• Threading Required - ffmpeg now requires threading to be built

#### Optimizations

• AArch64 - Important HEVC decoding optimizations
• RISC-V - Optimizations for:
  • AAC, FLAC, JPEG-2000, LPC
  • RV4.0, SVQ, VC1, VP8
• Loongarch - HEVC decoding optimizations

### API Changes

#### Bitstream Filters

• DTS to PTS Reorder -  dts2pts  bitstream filter
• Media 100 Conversion -  media100_to_mjpegb  bitstream filter
• VVC Metadata - Bitstream filter for editing VVC metadata
• VVC Annex B Conversion - Bitstream filter for VVC MP4 to Annex B

#### ffprobe Enhancements

• XML Output Schema - Changed to account for multiple variable-fields elements
• Output Format Alias -  -output_format  as alias for  -of

--------

## Version 5.x Highlights (Brief)

### Major Changes

• Vulkan Support - First comprehensive Vulkan implementation
• DNN Filters - Deep Neural Network filtering with TensorFlow backend
• HDR Support - Radiance HDR image format
• WebRTC - RTP packetizer for uncompressed video (RFC 4175)
• ProRes - VideoToolbox ProRes encoder and hwaccel
• AMD AMF - Encoder support on Linux (via Vulkan)

### Streaming

• WebP Animation - Support for animated WebP encoding
• Live Streaming - Enhanced protocol support

### Codecs

• AV1 - Multiple encoding and decoding improvements
• Siren - MSN Siren audio decoder
• Speex - Speex decoder

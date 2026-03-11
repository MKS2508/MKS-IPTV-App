// CTransmuxFFI.h — Umbrella header for the CTransmuxFFI library
//
// Include this single header for the full CTransmuxFFI public API.
// Alternatively, include individual mks_*.h headers for minimal dependencies.
//
// CTransmuxFFI is a modular C library wrapping FFmpeg 8.0.1 for:
//   - Container remuxing (MKV -> fMP4/HLS) with runtime layout detection
//   - Audio transcoding (AC3/EAC3/DTS -> AAC)
//   - Subtitle extraction (7 text formats -> WebVTT)
//   - Video transcoding via VideoToolbox (planned)
//   - Tier-based codec detection (planned)
//
// Designed for FFI consumption from Swift, Python, and Kotlin.

#ifndef MKS_CTRANSMUX_FFI_H
#define MKS_CTRANSMUX_FFI_H

// Foundation: error codes, tiers, version, compiler attributes
#include "mks_common.h"

// Logging: callback-based, level-filtered
#include "mks_log.h"

// Stream inspection and output stream setup
#include "mks_stream.h"

// Packet manipulation and seek support
#include "mks_packet.h"

// Bitstream filters (aac_adtstoasc, dts2pts planned)
#include "mks_bsf.h"

// Audio transcoder (AC3/EAC3/DTS -> AAC)
#include "mks_audio.h"

// Subtitle extraction (in-band -> WebVTT)
#include "mks_subtitle.h"

// Tier detection (codec -> passthrough/audio-only/video-transcode/full)
#include "mks_tier.h"

// Video transcoder (VP9/AV1/MPEG-2 -> H.264/H.265 via VideoToolbox)
#include "mks_video.h"

// ============================================================================
// Diagnostics (kept in umbrella, not worth its own header)
// ============================================================================

#pragma clang assume_nonnull begin

/// Dump stream layout information to the log for debugging.
/// Shows layout detection shifts, codec parameters, and dimensions.
MKS_PUBLIC
void mks_debug_stream_layout(const void *fmtCtx, int streamIndex);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_H

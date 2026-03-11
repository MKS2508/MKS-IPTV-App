// mks_tier.h — Codec-to-tier detection for AVPlayer compatibility
//
// Maps FFmpeg codec IDs to MKSTranscodeTier values, determining what
// processing is needed for AVPlayer playback:
//
//   Tier 0 (passthrough):   AVPlayer-native codecs, zero CPU cost
//   Tier 1 (audio-only):    Audio needs transcode, video passthrough
//   Tier 2 (video transc.): Video needs decode+VT encode, audio may also
//   Tier 3 (full transc.):  Unknown/legacy codecs, software fallback
//
// Based on Stremio/IPTV codec distribution analysis:
//   H.264 (~50-60%) + H.265 (~25-35%) = ~85-90% → Tier 0 (zero cost)
//   VP9 (~5-8%) + AV1 (~1-3%) + MPEG-2 (~2-5%) → Tier 2
//   Legacy (<1%) → Tier 3
//
// Thread safety: All functions are pure (no state), safe from any thread.

#ifndef MKS_CTRANSMUX_FFI_TIER_H
#define MKS_CTRANSMUX_FFI_TIER_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Tier detection from format context
// ============================================================================

/// Detect the transcode tier for a video stream.
/// Reads the codec ID from the format context and maps it to a tier.
/// @param fmtCtx       Opaque AVFormatContext* of the input.
/// @param streamIndex  Index of the video stream to classify.
/// @return MKS_TIER_PASSTHROUGH for AVPlayer-native codecs,
///         MKS_TIER_VIDEO_TRANSCODE for known decodable codecs,
///         MKS_TIER_FULL_TRANSCODE for unknown codecs.
///         Returns MKS_TIER_FULL_TRANSCODE if streamIndex is out of range.
MKS_PUBLIC
MKSTranscodeTier mks_tier_detect_video(const void *fmtCtx, int streamIndex);

/// Detect the transcode tier for an audio stream.
/// @param fmtCtx       Opaque AVFormatContext* of the input.
/// @param streamIndex  Index of the audio stream to classify.
/// @return MKS_TIER_PASSTHROUGH for AVPlayer-native codecs,
///         MKS_TIER_AUDIO_ONLY for codecs needing transcode to AAC,
///         MKS_TIER_FULL_TRANSCODE for unknown codecs.
///         Returns MKS_TIER_FULL_TRANSCODE if streamIndex is out of range.
MKS_PUBLIC
MKSTranscodeTier mks_tier_detect_audio(const void *fmtCtx, int streamIndex);

// ============================================================================
// Tier detection from raw codec ID
// ============================================================================

/// Classify a video codec ID into a transcode tier.
/// Pure function, no FFmpeg context needed.
MKS_PUBLIC
MKSTranscodeTier mks_tier_classify_video_codec(int codecId);

/// Classify an audio codec ID into a transcode tier.
/// Pure function, no FFmpeg context needed.
MKS_PUBLIC
MKSTranscodeTier mks_tier_classify_audio_codec(int codecId);

// ============================================================================
// Tier utilities
// ============================================================================

/// Get a human-readable name for a transcode tier.
/// @return Static string (e.g., "passthrough", "audio-only", "video-transcode",
///         "full-transcode"). Valid for the lifetime of the process.
MKS_PUBLIC
const char *mks_tier_name(MKSTranscodeTier tier);

/// Compute the effective tier for a stream pair.
/// Returns max(videoTier, audioTier) — the highest processing needed.
MKS_PUBLIC
MKSTranscodeTier mks_tier_effective(MKSTranscodeTier videoTier,
                                     MKSTranscodeTier audioTier);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_TIER_H

// mks_tier.c — Codec-to-tier detection for AVPlayer compatibility
//
// Pure classification logic: maps FFmpeg codec IDs to MKSTranscodeTier.
// No FFmpeg decode/encode calls — just codec ID → tier lookup.
//
// Classification is based on:
//   - Apple AVPlayer codec support (AVFoundation documentation)
//   - Stremio/IPTV codec distribution analysis (see REFERENCE-OVERVIEW.md)
//   - FFmpeg 8.0.1 decoder availability
//
// Tier assignments:
//   Tier 0 (passthrough):   AVPlayer decodes natively. Zero CPU.
//   Tier 1 (audio-only):    Audio transcode needed (DTS/TrueHD → AAC).
//   Tier 2 (video transc.): FFmpeg SW decode + VT HW encode → H.264/H.265.
//   Tier 3 (full transc.):  Unknown/legacy. SW decode + SW encode fallback.
//
// Thread safety: All functions are pure (no mutable state), safe from any thread.

#define MKS_LOG_TAG "mks_tier"

#include "include/mks_tier.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libavcodec/codec_id.h>

// ============================================================================
// Video codec classification
//
// AVPlayer-native (Tier 0):
//   H.264, HEVC, ProRes, MPEG-4 Part 2, MJPEG, Apple ProRes RAW
//   These are hardware-decoded by VideoToolbox inside AVPlayer.
//
// Known FFmpeg decoders (Tier 2):
//   VP9, VP8, AV1, MPEG-2, MPEG-1, Theora, WMV3, VC-1, H.263, FLV1
//   FFmpeg can decode these; we re-encode to H.264/H.265 via VT.
//
// Unknown (Tier 3):
//   Everything else. May or may not have FFmpeg decoders.
//   Falls back to software encode if decoder exists.
// ============================================================================

MKSTranscodeTier mks_tier_classify_video_codec(int codecId) {
    switch (codecId) {
    // --- Tier 0: AVPlayer native (hardware decode via VideoToolbox) ---
    case AV_CODEC_ID_H264:
    case AV_CODEC_ID_HEVC:
    case AV_CODEC_ID_PRORES:
    case AV_CODEC_ID_MPEG4:           // MPEG-4 Part 2 (DivX, Xvid)
    case AV_CODEC_ID_MJPEG:
    case AV_CODEC_ID_MJPEGB:
        return MKS_TIER_PASSTHROUGH;

    // --- Tier 2: FFmpeg can decode, VT can re-encode ---
    // Common in Stremio/IPTV (~10-13% of content)
    case AV_CODEC_ID_VP9:             // ~5-8% of Stremio content
    case AV_CODEC_ID_AV1:             // ~1-3%, growing
    case AV_CODEC_ID_MPEG2VIDEO:      // ~2-5%, legacy DVB/cable
    case AV_CODEC_ID_MPEG1VIDEO:      // Rare, legacy
    case AV_CODEC_ID_VP8:             // Rare in modern content
    case AV_CODEC_ID_THEORA:          // Very rare
    case AV_CODEC_ID_WMV3:            // Windows Media Video 9
    case AV_CODEC_ID_VC1:             // VC-1 (Blu-ray, WMV)
    case AV_CODEC_ID_FLV1:            // Flash Video (legacy)
    case AV_CODEC_ID_H263:            // Legacy videoconferencing
    case AV_CODEC_ID_H263P:           // H.263+ variant
    case AV_CODEC_ID_MSMPEG4V2:       // MS MPEG-4 v2 (old AVI)
    case AV_CODEC_ID_MSMPEG4V3:       // MS MPEG-4 v3 (DivX 3)
    case AV_CODEC_ID_WMV1:            // WMV7
    case AV_CODEC_ID_WMV2:            // WMV8
    case AV_CODEC_ID_RV30:            // RealVideo 8
    case AV_CODEC_ID_RV40:            // RealVideo 9/10
        return MKS_TIER_VIDEO_TRANSCODE;

    // --- Tier 3: Unknown / no reliable decoder ---
    default:
        return MKS_TIER_FULL_TRANSCODE;
    }
}

// ============================================================================
// Audio codec classification
//
// AVPlayer-native (Tier 0):
//   AAC, MP3, ALAC, FLAC, Opus, Vorbis, AC3, EAC3, MP2, PCM variants
//   AVPlayer handles these directly — no processing needed.
//
// Transcode needed (Tier 1):
//   DTS, TrueHD, COOK (RealAudio)
//   Must be transcoded to AAC for AVPlayer.
//   AC3/EAC3 are Tier 0 because AVPlayer supports them natively.
//
// Unknown (Tier 3):
//   Everything else.
// ============================================================================

MKSTranscodeTier mks_tier_classify_audio_codec(int codecId) {
    switch (codecId) {
    // --- Tier 0: AVPlayer native ---
    case AV_CODEC_ID_AAC:
    case AV_CODEC_ID_MP3:
    case AV_CODEC_ID_ALAC:            // Apple Lossless
    case AV_CODEC_ID_FLAC:
    case AV_CODEC_ID_OPUS:
    case AV_CODEC_ID_VORBIS:
    case AV_CODEC_ID_AC3:             // Dolby Digital
    case AV_CODEC_ID_EAC3:            // Dolby Digital Plus
    case AV_CODEC_ID_MP2:             // MPEG Audio Layer 2
    case AV_CODEC_ID_PCM_S16LE:       // PCM variants
    case AV_CODEC_ID_PCM_S16BE:
    case AV_CODEC_ID_PCM_S24LE:
    case AV_CODEC_ID_PCM_S24BE:
    case AV_CODEC_ID_PCM_S32LE:
    case AV_CODEC_ID_PCM_S32BE:
    case AV_CODEC_ID_PCM_F32LE:
    case AV_CODEC_ID_PCM_F32BE:
    case AV_CODEC_ID_PCM_F64LE:
    case AV_CODEC_ID_PCM_ALAW:
    case AV_CODEC_ID_PCM_MULAW:
        return MKS_TIER_PASSTHROUGH;

    // --- Tier 1: Needs transcode to AAC ---
    case AV_CODEC_ID_DTS:             // DTS (common in Blu-ray rips)
    case AV_CODEC_ID_TRUEHD:          // Dolby TrueHD (lossless)
    case AV_CODEC_ID_COOK:            // RealAudio COOK
        return MKS_TIER_AUDIO_ONLY;

    // --- Tier 3: Unknown ---
    default:
        return MKS_TIER_FULL_TRANSCODE;
    }
}

// ============================================================================
// Context-based detection (reads codec ID from AVFormatContext)
// ============================================================================

MKSTranscodeTier mks_tier_detect_video(const void *fmtCtx, int streamIndex) {
    if (!fmtCtx) return MKS_TIER_FULL_TRANSCODE;

    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return MKS_TIER_FULL_TRANSCODE;

    AVCodecParameters *cp = mks_layout_get_codecpar(ctx, streamIndex);
    if (!cp) return MKS_TIER_FULL_TRANSCODE;

    int codecId = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
    MKSTranscodeTier tier = mks_tier_classify_video_codec(codecId);

    MKS_LOGD("video stream %d: codec_id=%d → %s", streamIndex, codecId, mks_tier_name(tier));
    return tier;
}

MKSTranscodeTier mks_tier_detect_audio(const void *fmtCtx, int streamIndex) {
    if (!fmtCtx) return MKS_TIER_FULL_TRANSCODE;

    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return MKS_TIER_FULL_TRANSCODE;

    AVCodecParameters *cp = mks_layout_get_codecpar(ctx, streamIndex);
    if (!cp) return MKS_TIER_FULL_TRANSCODE;

    int codecId = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
    MKSTranscodeTier tier = mks_tier_classify_audio_codec(codecId);

    MKS_LOGD("audio stream %d: codec_id=%d → %s", streamIndex, codecId, mks_tier_name(tier));
    return tier;
}

// ============================================================================
// Utilities
// ============================================================================

const char *mks_tier_name(MKSTranscodeTier tier) {
    switch (tier) {
    case MKS_TIER_PASSTHROUGH:     return "passthrough";
    case MKS_TIER_AUDIO_ONLY:      return "audio-only";
    case MKS_TIER_VIDEO_TRANSCODE: return "video-transcode";
    case MKS_TIER_FULL_TRANSCODE:  return "full-transcode";
    default:                       return "unknown-tier";
    }
}

MKSTranscodeTier mks_tier_effective(MKSTranscodeTier videoTier,
                                     MKSTranscodeTier audioTier) {
    return videoTier > audioTier ? videoTier : audioTier;
}

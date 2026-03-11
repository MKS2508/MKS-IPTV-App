// mks_video.h — Video transcoder (VP9/AV1/MPEG-2 -> H.264/H.265 via VideoToolbox)
//
// Opaque handle wrapping an FFmpeg decode -> colorspace convert -> VT encode pipeline.
// Lifecycle: create -> setup_output -> [send/receive loop] -> flush -> free
//
// Architecture:
//   AVPacket (VP9/AV1/MPEG-2/etc)
//     → avcodec_send_packet (FFmpeg software decoder)
//     → avcodec_receive_frame (decoded YUV420P/YUV422P/etc)
//     → sws_scale (colorspace convert to NV12)
//     → avcodec_send_frame (VideoToolbox hardware encoder)
//     → avcodec_receive_packet (H.264/H.265 AVPacket)
//
// Thread safety: A single MKSVideoTranscoder instance is NOT thread-safe.
// Do not call send/receive from multiple threads simultaneously.
// Create separate instances for concurrent transcoding.
//
// References:
//   - AD-03: Video Transcoder in C (not Swift)
//   - AD-04: Encoder API — FFmpeg's h264/hevc_videotoolbox
//   - AD-05: Bitrate Strategy — VBR with qmin/qmax (NOT CRF)
//   - AD-06: VT Encoder Options — spatialaq + power_efficient

#ifndef MKS_CTRANSMUX_FFI_VIDEO_H
#define MKS_CTRANSMUX_FFI_VIDEO_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Opaque type
// ============================================================================

/// Opaque video transcoder handle.
/// The internal struct is defined in mks_video.c (not visible to consumers).
typedef struct MKSVideoTranscoder MKSVideoTranscoder;

// ============================================================================
// Configuration struct
// ============================================================================

/// Configuration options for video transcoder creation.
/// Provides explicit control over encoder behavior without exposing FFmpeg internals.
typedef struct MKSVideoConfig {
    /// Target codec: AV_CODEC_ID_H264 or AV_CODEC_ID_HEVC.
    /// Use AV_CODEC_ID_H264 for maximum compatibility.
    int targetCodecId;

    /// Target bitrate in bits/second (0 = auto-calculated from resolution).
    /// Recommended values: 2-4 Mbps (720p), 6-8 Mbps (1080p), 12-20 Mbps (4K).
    int targetBitrate;

    /// Enable power-efficient encoding (reduces quality slightly, saves battery).
    /// Recommended: true on iOS/macOS when on battery power.
    int powerEfficient;

    /// Enable spatial adaptive quantization (improves perceptual quality).
    /// Recommended: true always (negligible performance cost).
    int spatialAQ;

    /// Maximum B-frame count (0-4).
    /// H.264: 0-3, H.265: 0-4. Higher values improve compression but increase latency.
    /// For streaming/live: 0-1. For VOD: 2-3.
    int maxBFrames;

    /// Real-time mode (live content).
    /// When true, prioritizes low latency over compression efficiency.
    int realtime;

    /// Profile for H.264: 66 (Baseline), 77 (Main), 100 (High).
    /// Profile for H.265: 1 (Main), 2 (Main10 for HDR).
    /// Use 0 for auto-select based on source.
    int profile;
} MKSVideoConfig;

/// Default configuration values.
/// H.264, auto bitrate, power-efficient, spatial AQ, 2 B-frames, VOD mode.
#define MKS_VIDEO_CONFIG_DEFAULT (MKSVideoConfig){ \
    .targetCodecId = 0,      /* auto: H.264 for <=1080p, H.265 for 4K+ */ \
    .targetBitrate = 0,      /* auto: based on resolution */ \
    .powerEfficient = 1,     /* enabled */ \
    .spatialAQ = 1,          /* enabled */ \
    .maxBFrames = 2,         /* good for VOD */ \
    .realtime = 0,           /* VOD mode */ \
    .profile = 0             /* auto */ \
}

// ============================================================================
// Lifecycle
// ============================================================================

/// Create a video transcoder for VP9/AV1/MPEG-2/etc -> H.264/H.265 conversion.
///
/// @param inputFmtCtx      Opaque AVFormatContext* of the input.
/// @param inputStreamIndex Index of the video stream to transcode.
/// @param config           Encoder configuration (use MKS_VIDEO_CONFIG_DEFAULT for defaults).
/// @return A new transcoder handle, or NULL on failure.
///
/// @note The transcoder does NOT take ownership of inputFmtCtx.
///       The caller must ensure inputFmtCtx outlives the transcoder.
MKS_PUBLIC MKS_WARN_UNUSED
MKSVideoTranscoder * _Nullable mks_video_transcoder_create(
    const void *inputFmtCtx,
    int inputStreamIndex,
    MKSVideoConfig config);

/// Configure an output AVStream with the transcoder's codec parameters.
/// Must be called before writing the output header.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED
MKSError mks_video_transcoder_setup_output(MKSVideoTranscoder *ctx,
                                            void *outputStream);

/// Free a video transcoder and all associated FFmpeg resources.
/// Passing NULL is a safe no-op (libcurl convention).
MKS_PUBLIC
void mks_video_transcoder_free(MKSVideoTranscoder * _Nullable ctx);

// ============================================================================
// Processing
// ============================================================================

/// Send an input packet (VP9/AV1/MPEG-2/etc) to the transcoder for decoding.
/// After sending, call mks_video_transcoder_receive() in a loop to
/// retrieve encoded H.264/H.265 packets.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED MKS_HOT
MKSError mks_video_transcoder_send(MKSVideoTranscoder *ctx,
                                    const void *inputPacket);

/// Receive an encoded H.264/H.265 packet from the transcoder.
/// Call in a loop after send() until MKS_ERROR_EAGAIN is returned.
/// @return MKS_OK with data in outputPacket,
///         MKS_ERROR_EAGAIN when no more packets available,
///         negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED MKS_HOT
MKSError mks_video_transcoder_receive(MKSVideoTranscoder *ctx,
                                       void *outputPacket);

/// Flush remaining frames through the transcoder pipeline.
/// Call when no more input packets will be sent (e.g., end of stream).
/// After flushing, continue calling receive() until EAGAIN.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED
MKSError mks_video_transcoder_flush(MKSVideoTranscoder *ctx);

// ============================================================================
// Control
// ============================================================================

/// Reset the transcoder after a seek operation.
/// Flushes decoder, encoder, and colorspace converter buffers. Resets PTS counter.
MKS_PUBLIC
void mks_video_transcoder_reset(MKSVideoTranscoder *ctx);

/// Get the encoder time base as a fraction (num/den).
MKS_PUBLIC
void mks_video_transcoder_get_time_base(MKSVideoTranscoder *ctx,
                                         int *num, int *den);

/// Get the output codec ID (AV_CODEC_ID_H264 or AV_CODEC_ID_HEVC).
MKS_PUBLIC
int mks_video_transcoder_get_output_codec_id(const MKSVideoTranscoder *ctx);

/// Get the output width in pixels.
MKS_PUBLIC
int mks_video_transcoder_get_width(const MKSVideoTranscoder *ctx);

/// Get the output height in pixels.
MKS_PUBLIC
int mks_video_transcoder_get_height(const MKSVideoTranscoder *ctx);

// ============================================================================
// Error context (SQLite pattern)
// ============================================================================

/// Get the last FFmpeg AVERROR code that caused the most recent error
/// on this transcoder handle. Returns 0 if no FFmpeg error is recorded.
MKS_PUBLIC
int mks_video_transcoder_last_averror(const MKSVideoTranscoder *ctx);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_VIDEO_H

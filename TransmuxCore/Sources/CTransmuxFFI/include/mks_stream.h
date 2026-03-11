// mks_stream.h — Stream inspection and output stream setup
//
// Read codec parameters, dimensions, metadata from AVFormatContext streams.
// All functions take opaque void* pointers (FFmpeg types not exposed to consumers).

#ifndef MKS_CTRANSMUX_FFI_STREAM_H
#define MKS_CTRANSMUX_FFI_STREAM_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Stream inspection
// ============================================================================

/// Get the codec type (AVMEDIA_TYPE_VIDEO, AVMEDIA_TYPE_AUDIO, etc.)
/// for the stream at the given index.
MKS_PUBLIC MKS_HOT
int mks_stream_get_codec_type(const void *fmtCtx, int streamIndex);

/// Get the codec ID (AV_CODEC_ID_H264, AV_CODEC_ID_AAC, etc.)
/// for the stream at the given index.
MKS_PUBLIC MKS_HOT
int mks_stream_get_codec_id(const void *fmtCtx, int streamIndex);

/// Get the disposition flags for the stream (AV_DISPOSITION_DEFAULT, etc.).
MKS_PUBLIC
int mks_stream_get_disposition(const void *fmtCtx, int streamIndex);

/// Get the time base for the stream as a fraction (num/den).
MKS_PUBLIC
void mks_stream_get_time_base(const void *fmtCtx, int streamIndex,
                               int *num, int *den);

/// Get video width in pixels. Returns 0 for non-video streams.
MKS_PUBLIC
int mks_stream_get_width(const void *fmtCtx, int streamIndex);

/// Get video height in pixels. Returns 0 for non-video streams.
MKS_PUBLIC
int mks_stream_get_height(const void *fmtCtx, int streamIndex);

/// Get the average frame rate as a fraction (num/den).
/// Returns 0/1 for non-video streams or if unknown.
MKS_PUBLIC
void mks_stream_get_frame_rate(const void *fmtCtx, int streamIndex,
                                int *num, int *den);

/// Get the number of streams in the format context.
MKS_PUBLIC
int mks_format_get_nb_streams(const void *fmtCtx);

// ============================================================================
// Output stream setup
// ============================================================================

/// Copy codec parameters from a source stream to a destination output stream.
/// Handles layout detection and provides a raw memcpy fallback.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED
MKSError mks_stream_copy_codecpar(void *dstStream,
                                   const void *srcFmtCtx,
                                   int srcStreamIndex);

/// Clear the codec tag on a stream (required for container remux).
MKS_PUBLIC
void mks_stream_clear_codec_tag(void *stream);

/// Set the frame_size field on a stream's codec parameters.
MKS_PUBLIC
void mks_stream_set_frame_size(void *fmtCtx, int streamIndex, int frameSize);

/// Check whether the stream has extradata (codec config bytes).
/// @return 1 if extradata is present and non-empty, 0 otherwise.
MKS_PUBLIC
int mks_stream_has_extradata(const void *fmtCtx, int streamIndex);

// ============================================================================
// Stream metadata
// ============================================================================

/// Read the "language" metadata tag for a stream.
/// @return 0 on success, -1 if not found or error.
MKS_PUBLIC MKS_WARN_UNUSED
int mks_stream_get_language(const void *fmtCtx, int streamIndex,
                            char *buf, int bufSize);

/// Read the "title" metadata tag for a stream.
/// @return 0 on success, -1 if not found or error.
MKS_PUBLIC MKS_WARN_UNUSED
int mks_stream_get_title(const void *fmtCtx, int streamIndex,
                         char *buf, int bufSize);

/// Get the number of audio channels for a stream.
MKS_PUBLIC
int mks_stream_get_channels(const void *fmtCtx, int streamIndex);

/// Get the audio sample rate in Hz.
MKS_PUBLIC
int mks_stream_get_sample_rate(const void *fmtCtx, int streamIndex);

/// Get the stream bitrate in bits/second (from codec parameters).
/// Returns 0 if unknown or stream is invalid.
MKS_PUBLIC
int64_t mks_stream_get_bit_rate(const void *fmtCtx, int streamIndex);

/// Get the codec ID for a subtitle stream.
/// Returns 0 if the stream is not a subtitle stream.
MKS_PUBLIC
int mks_stream_get_subtitle_codec_id(const void *fmtCtx, int streamIndex);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_STREAM_H

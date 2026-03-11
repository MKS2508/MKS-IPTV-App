// mks_audio.h — Audio transcoder (AC3/EAC3/DTS -> AAC)
//
// Opaque handle wrapping an FFmpeg decode -> resample -> encode pipeline.
// Lifecycle: create -> setup_output -> [send/receive loop] -> flush -> free
//
// Thread safety: A single MKSAudioTranscoder instance is NOT thread-safe.
// Do not call send/receive from multiple threads simultaneously.
// Create separate instances for concurrent transcoding.
//
// References:
//   - Vulkan vkCreate*/vkDestroy* lifecycle pattern
//   - SQLite per-handle error context

#ifndef MKS_CTRANSMUX_FFI_AUDIO_H
#define MKS_CTRANSMUX_FFI_AUDIO_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Opaque type
// ============================================================================

/// Opaque audio transcoder handle.
/// The internal struct is defined in mks_audio.c (not visible to consumers).
typedef struct MKSAudioTranscoder MKSAudioTranscoder;

// ============================================================================
// Lifecycle
// ============================================================================

/// Create an audio transcoder for AC3/EAC3/DTS -> AAC conversion.
///
/// @param inputFmtCtx      Opaque AVFormatContext* of the input.
/// @param inputStreamIndex Index of the audio stream to transcode.
/// @param targetBitrate    Target AAC bitrate in bits/sec (e.g., 192000).
/// @param targetSampleRate Target sample rate in Hz (0 = same as source).
/// @param targetChannels   Target channel count (0 = same as source).
/// @return A new transcoder handle, or NULL on failure.
///
/// @note The transcoder does NOT take ownership of inputFmtCtx.
///       The caller must ensure inputFmtCtx outlives the transcoder.
MKS_PUBLIC MKS_WARN_UNUSED
MKSAudioTranscoder * _Nullable mks_audio_transcoder_create(
    const void *inputFmtCtx,
    int inputStreamIndex,
    int targetBitrate,
    int targetSampleRate,
    int targetChannels);

/// Configure an output AVStream with the transcoder's AAC codec parameters.
/// Must be called before writing the output header.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED
MKSError mks_audio_transcoder_setup_output(MKSAudioTranscoder *ctx,
                                            void *outputStream);

/// Free an audio transcoder and all associated FFmpeg resources.
/// Passing NULL is a safe no-op (libcurl convention).
MKS_PUBLIC
void mks_audio_transcoder_free(MKSAudioTranscoder * _Nullable ctx);

// ============================================================================
// Processing
// ============================================================================

/// Send an input packet (AC3/EAC3/DTS) to the transcoder for decoding.
/// After sending, call mks_audio_transcoder_receive() in a loop to
/// retrieve encoded AAC packets.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED MKS_HOT
MKSError mks_audio_transcoder_send(MKSAudioTranscoder *ctx,
                                    const void *inputPacket);

/// Receive an encoded AAC packet from the transcoder.
/// Call in a loop after send() until MKS_ERROR_EAGAIN is returned.
/// @return MKS_OK with data in outputPacket,
///         MKS_ERROR_EAGAIN when no more packets available,
///         negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED MKS_HOT
MKSError mks_audio_transcoder_receive(MKSAudioTranscoder *ctx,
                                       void *outputPacket);

/// Flush remaining frames through the transcoder pipeline.
/// Call when no more input packets will be sent (e.g., end of stream).
/// After flushing, continue calling receive() until EAGAIN.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED
MKSError mks_audio_transcoder_flush(MKSAudioTranscoder *ctx);

// ============================================================================
// Control
// ============================================================================

/// Reset the transcoder after a seek operation.
/// Flushes decoder, encoder, and resampler buffers. Resets PTS counter.
MKS_PUBLIC
void mks_audio_transcoder_reset(MKSAudioTranscoder *ctx);

/// Get the encoder time base as a fraction (num/den).
MKS_PUBLIC
void mks_audio_transcoder_get_time_base(MKSAudioTranscoder *ctx,
                                         int *num, int *den);

// ============================================================================
// Error context (SQLite pattern)
// ============================================================================

/// Get the last FFmpeg AVERROR code that caused the most recent error
/// on this transcoder handle. Returns 0 if no FFmpeg error is recorded.
MKS_PUBLIC
int mks_audio_transcoder_last_averror(const MKSAudioTranscoder *ctx);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_AUDIO_H

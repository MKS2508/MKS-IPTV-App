// mks_packet.h — Packet field access, timestamp operations, seek support
//
// All functions take opaque void* pointers to AVPacket/AVFormatContext.

#ifndef MKS_CTRANSMUX_FFI_PACKET_H
#define MKS_CTRANSMUX_FFI_PACKET_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Packet field access
// ============================================================================

/// Get the stream index of a packet.
MKS_PUBLIC MKS_HOT
int mks_packet_get_stream_index(const void *pkt);

/// Set the stream index of a packet.
MKS_PUBLIC MKS_HOT
void mks_packet_set_stream_index(void *pkt, int index);

/// Clear the position field of a packet (set to -1).
MKS_PUBLIC
void mks_packet_clear_pos(void *pkt);

/// Check whether a packet has the keyframe flag set.
/// @return 1 if keyframe, 0 otherwise.
MKS_PUBLIC MKS_HOT
int mks_packet_is_keyframe(const void *pkt);

// ============================================================================
// Timestamp operations
// ============================================================================

/// Rescale packet timestamps from source stream timebase to output stream
/// timebase. Uses av_packet_rescale_ts internally with layout-corrected
/// time_base values.
MKS_PUBLIC MKS_HOT
void mks_packet_rescale_ts(void *pkt,
                            const void *srcFmtCtx, int srcStreamIndex,
                            const void *dstFmtCtx, int dstStreamIndex);

/// Adjust both DTS and PTS by a signed offset.
/// Used for global timestamp rebasing after seek.
MKS_PUBLIC MKS_HOT
void mks_packet_adjust_ts(void *pkt, int64_t dtsOffset);

/// Get the DTS (decode timestamp) of a packet.
/// Returns AV_NOPTS_VALUE if the packet has no DTS.
MKS_PUBLIC MKS_HOT
int64_t mks_packet_get_dts(const void *pkt);

/// Get the PTS (presentation timestamp) of a packet.
/// Returns AV_NOPTS_VALUE if the packet has no PTS.
MKS_PUBLIC MKS_HOT
int64_t mks_packet_get_pts(const void *pkt);

/// Set the DTS of a packet.
MKS_PUBLIC
void mks_packet_set_dts(void *pkt, int64_t dts);

// ============================================================================
// Seek support
// ============================================================================

/// Flush the format context's internal buffers after a seek.
/// Wraps avformat_flush().
MKS_PUBLIC
void mks_format_flush_input(void *fmtCtx);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_PACKET_H

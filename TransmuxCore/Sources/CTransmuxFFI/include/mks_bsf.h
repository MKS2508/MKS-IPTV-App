// mks_bsf.h — Bitstream filter management
//
// Wraps FFmpeg AVBSFContext lifecycle for:
//   - aac_adtstoasc: ADTS -> ASC conversion for fMP4 AAC output
//   - dts2pts: PTS reordering fix for IPTV streams (FFmpeg 7+, planned)

#ifndef MKS_CTRANSMUX_FFI_BSF_H
#define MKS_CTRANSMUX_FFI_BSF_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// aac_adtstoasc bitstream filter
// ============================================================================

/// Create an aac_adtstoasc BSF for the specified audio stream.
/// @return Opaque BSF handle, or NULL on failure.
MKS_PUBLIC MKS_WARN_UNUSED
void * _Nullable mks_bsf_create_aac_adtstoasc(const void *fmtCtx,
                                                int audioStreamIndex);

/// Send a packet through a BSF and receive the filtered result in-place.
/// @return MKS_OK on success, negative MKSError on failure.
MKS_PUBLIC MKS_WARN_UNUSED MKS_HOT
MKSError mks_bsf_filter_packet(void *bsfCtx, void *pkt);

/// Free a BSF context. Passing NULL is a safe no-op.
MKS_PUBLIC
void mks_bsf_free(void * _Nullable bsfCtx);

/// Flush a BSF after a seek operation.
/// Resets BSF to initial state without putting it into permanent EOF.
/// Passing NULL is a safe no-op.
MKS_PUBLIC
void mks_bsf_flush(void * _Nullable bsfCtx);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_BSF_H

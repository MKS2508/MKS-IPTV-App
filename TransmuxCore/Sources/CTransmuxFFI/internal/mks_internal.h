// mks_internal.h — CTransmuxFFI shared internal helpers
//
// PRIVATE header. Not exposed to consumers (not in include/).
// Provides:
//   - Runtime AVStream/AVCodecParameters layout detection
//   - Shift-corrected field readers/writers
//   - AVERROR -> MKSError mapping
//
// The layout detection mechanism exists as a safety net for detecting
// +-8 byte offset mismatches between compiled headers and FFmpeg binary.
// With our own FFmpeg 8.0.1 build, shifts are 0/0 (perfect match),
// but the mechanism guards against future header/binary mismatches.
//
// References:
//   - Original FFmpegStreamHelper.c validation-based detection
//   - FFmpeg 8.0.1 AVStream/AVCodecParameters layout

#ifndef MKS_CTRANSMUX_FFI_INTERNAL_H
#define MKS_CTRANSMUX_FFI_INTERNAL_H

// Public header — resolved via SPM publicHeadersPath (-I include/)
#include "mks_common.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/error.h>
#include <stddef.h>

// ============================================================================
// AVERROR -> MKSError mapping
// ============================================================================

/// Map an FFmpeg AVERROR code to the corresponding MKSError.
/// This provides a consistent error interface to consumers while
/// preserving the ability to retrieve the raw AVERROR when needed.
static inline MKSError mks_error_from_averror(int averror) {
    if (averror == 0)               return MKS_OK;
    if (averror == AVERROR(ENOMEM)) return MKS_ERROR_NOMEM;
    if (averror == AVERROR(EINVAL)) return MKS_ERROR_INVALID_PARAM;
    if (averror == AVERROR_EOF)     return MKS_ERROR_EOF;
    if (averror == AVERROR(EAGAIN)) return MKS_ERROR_EAGAIN;
    if (averror == AVERROR_EXTERNAL)return MKS_ERROR_VT_SESSION;
    // Default: map to I/O error
    return MKS_ERROR_IO;
}

// ============================================================================
// Layout detection (implemented in mks_layout.c)
//
// Thread safety: mks_layout_detect() uses pthread_once internally.
// All readers are safe to call from any thread after detection.
// ============================================================================

/// Detect AVStream/AVCodecParameters layout shifts by probing raw memory.
/// Idempotent: uses pthread_once internally, safe to call repeatedly.
/// Must be called after avformat_find_stream_info().
void mks_layout_detect(const AVFormatContext *ctx);

// --- Shift-corrected field readers (AVStream) ---

void     *mks_layout_read_stream_ptr(const AVStream *s, size_t header_offset);
int       mks_layout_read_stream_int(const AVStream *s, size_t header_offset);
AVRational mks_layout_read_stream_rational(const AVStream *s, size_t header_offset);

// --- Shift-corrected field readers/writers (AVCodecParameters) ---

int       mks_layout_read_cp_int(const AVCodecParameters *cp, size_t header_offset);
int64_t   mks_layout_read_cp_int64(const AVCodecParameters *cp, size_t header_offset);
uint32_t  mks_layout_read_cp_uint32(const AVCodecParameters *cp, size_t header_offset);
void     *mks_layout_read_cp_ptr(const AVCodecParameters *cp, size_t header_offset);

void mks_layout_write_cp_int(AVCodecParameters *cp, size_t header_offset, int val);
void mks_layout_write_cp_uint32(AVCodecParameters *cp, size_t header_offset, uint32_t val);
void mks_layout_write_cp_ptr(AVCodecParameters *cp, size_t header_offset, void *val);

// --- Corrected codecpar access ---

/// Get AVCodecParameters* for a stream, corrected for layout shift.
/// Returns NULL if index is out of range or ctx is NULL.
AVCodecParameters *mks_layout_get_codecpar(const AVFormatContext *ctx, int idx);

/// Get AVCodecParameters* from an AVStream*, corrected for layout shift.
/// Returns NULL if s is NULL.
AVCodecParameters *mks_layout_get_stream_codecpar(const AVStream *s);

// --- Shift query (for diagnostics) ---

int mks_layout_get_stream_shift(void);
int mks_layout_get_cp_shift(void);

#endif // MKS_CTRANSMUX_FFI_INTERNAL_H

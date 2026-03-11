// mks_layout.c — Runtime AVStream/AVCodecParameters layout detection
//
// Detects +-8 byte offset mismatches between compiled headers and binary.
// With our own FFmpeg 8.0.1 build, shifts are 0/0 (perfect match).
// Kept as safety net for future header/binary mismatches.
//
// Thread safety: mks_layout_detect() uses pthread_once internally.
// All shift-corrected readers are safe after detection.

#define MKS_LOG_TAG "mks_layout"

#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <pthread.h>

// ============================================================================
// Layout shift state (set once via pthread_once, read-only thereafter)
// ============================================================================

static int s_stream_shift = 0;
static int s_cp_shift     = 0;

static pthread_once_t  s_detect_once = PTHREAD_ONCE_INIT;
static const AVFormatContext *s_detect_ctx = NULL;

// ============================================================================
// Validation
// ============================================================================

static int validate_codecpar(const unsigned char *raw, size_t ct_off,
                             const char *label) {
    int ct = *(const int *)(raw + ct_off);
    int ci = *(const int *)(raw + ct_off + 4);

    MKS_LOGD("validate_codecpar(%s): ct_off=%zu codec_type=%d codec_id=%d",
             label, ct_off, ct, ci);

    return (ct >= 0 && ct <= 5 && ci > 0 && ci < 200000);
}

// ============================================================================
// Detection (pthread_once callback)
// ============================================================================

static void detect_layout_impl(void) {
    const AVFormatContext *ctx = s_detect_ctx;
    s_stream_shift = 0;
    s_cp_shift = 0;

    if (!ctx || ctx->nb_streams == 0) return;

    size_t header_cp_offset = offsetof(AVStream, codecpar);
    size_t header_ct_offset = offsetof(AVCodecParameters, codec_type);

    MKS_LOGD("nb_streams=%u header codecpar_off=%zu codec_type_off=%zu",
             ctx->nb_streams, header_cp_offset, header_ct_offset);

    for (unsigned i = 0; i < ctx->nb_streams; i++) {
        AVStream *s = ctx->streams[i];
        if (!s) continue;

        const unsigned char *stream_raw = (const unsigned char *)s;

        // Try header offset and header-8 offset for codecpar pointer
        size_t candidate_offsets[2] = { header_cp_offset, header_cp_offset - 8 };
        int    candidate_shifts[2]  = { 0, 8 };
        const char *candidate_labels[2] = { "header", "shifted(-8)" };

        for (int c = 0; c < 2; c++) {
            size_t off = candidate_offsets[c];
            void *candidate = *(void **)(stream_raw + off);

            MKS_LOGD("AVStream[%u] ptr at off %zu (%s) = %p",
                     i, off, candidate_labels[c], candidate);

            if (!candidate || (uintptr_t)candidate < 4096) continue;

            const unsigned char *cp_raw = (const unsigned char *)candidate;

            // Try cp_shift = 0
            if (validate_codecpar(cp_raw, header_ct_offset, "cp_shift=0")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = 0;
                MKS_LOGI("DETECTED via %s: stream_shift=%d cp_shift=%d",
                         candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }

            // Try cp_shift = 8
            if (header_ct_offset >= 8 &&
                validate_codecpar(cp_raw, header_ct_offset - 8, "cp_shift=8")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = 8;
                MKS_LOGI("DETECTED via %s: stream_shift=%d cp_shift=%d",
                         candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }

            // Try cp_shift = -8
            if (validate_codecpar(cp_raw, header_ct_offset + 8, "cp_shift=-8")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = -8;
                MKS_LOGI("DETECTED via %s: stream_shift=%d cp_shift=%d",
                         candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }
        }
    }

    MKS_LOGW("could not detect layout from any stream, using header offsets (0/0)");
}

void mks_layout_detect(const AVFormatContext *ctx) {
    s_detect_ctx = ctx;
    pthread_once(&s_detect_once, detect_layout_impl);
}

// ============================================================================
// Shift-corrected field readers (AVStream)
// ============================================================================

void *mks_layout_read_stream_ptr(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(void **)(raw + header_offset - s_stream_shift);
}

int mks_layout_read_stream_int(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(const int *)(raw + header_offset - s_stream_shift);
}

AVRational mks_layout_read_stream_rational(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(const AVRational *)(raw + header_offset - s_stream_shift);
}

// ============================================================================
// Shift-corrected field readers/writers (AVCodecParameters)
// ============================================================================

int mks_layout_read_cp_int(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(const int *)(raw + header_offset - s_cp_shift);
}

int64_t mks_layout_read_cp_int64(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(const int64_t *)(raw + header_offset - s_cp_shift);
}

uint32_t mks_layout_read_cp_uint32(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(const uint32_t *)(raw + header_offset - s_cp_shift);
}

void *mks_layout_read_cp_ptr(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(void **)(raw + header_offset - s_cp_shift);
}

void mks_layout_write_cp_int(AVCodecParameters *cp, size_t header_offset, int val) {
    unsigned char *raw = (unsigned char *)cp;
    *(int *)(raw + header_offset - s_cp_shift) = val;
}

void mks_layout_write_cp_uint32(AVCodecParameters *cp, size_t header_offset, uint32_t val) {
    unsigned char *raw = (unsigned char *)cp;
    *(uint32_t *)(raw + header_offset - s_cp_shift) = val;
}

void mks_layout_write_cp_ptr(AVCodecParameters *cp, size_t header_offset, void *val) {
    unsigned char *raw = (unsigned char *)cp;
    *(void **)(raw + header_offset - s_cp_shift) = val;
}

// ============================================================================
// Corrected codecpar access
// ============================================================================

AVCodecParameters *mks_layout_get_codecpar(const AVFormatContext *ctx, int idx) {
    if (!ctx || idx < 0 || (unsigned)idx >= ctx->nb_streams)
        return NULL;

    mks_layout_detect(ctx);

    AVStream *s = ctx->streams[idx];
    if (!s) return NULL;

    return (AVCodecParameters *)mks_layout_read_stream_ptr(s, offsetof(AVStream, codecpar));
}

AVCodecParameters *mks_layout_get_stream_codecpar(const AVStream *s) {
    if (!s) return NULL;
    return (AVCodecParameters *)mks_layout_read_stream_ptr(s, offsetof(AVStream, codecpar));
}

int mks_layout_get_stream_shift(void) { return s_stream_shift; }
int mks_layout_get_cp_shift(void)     { return s_cp_shift; }

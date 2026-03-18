// FFmpegStreamHelper.c
//
// Pure C accessors for FFmpeg structs with runtime layout detection.
//
// PROBLEM: KSPlayer's FFmpegKit 6.1.3 distributes xcframework headers that
// may include `const AVClass *av_class` as the first field of structs, but
// the compiled binary may have been built with a DIFFERENT layout.
// The mismatch can go EITHER direction:
//   - AVStream: headers HAVE av_class, binary DOESN'T → shift = +8
//   - AVCodecParameters: headers DON'T have av_class, binary DOES → shift = -8
// This shifts field offsets by ±8 bytes in each struct independently.
//
// FIX: At runtime, probe raw memory to detect whether each struct's actual
// layout matches the headers using validation-based detection. Instead of
// relying on NULL checks (which confuse AVStream.codec with AVStream.codecpar),
// we validate that the pointed-to struct has codec_type and codec_id at the
// expected consecutive offsets with sane values. This distinguishes
// AVCodecParameters (consecutive 4-byte ints) from AVCodecContext (12+ bytes
// apart). Track separate shifts for AVStream and AVCodecParameters. Use raw
// memcpy as a fallback for codecpar copy when avcodec_parameters_copy fails.

#import <libavformat/avformat.h>
#import <libavcodec/avcodec.h>
#import <libavcodec/bsf.h>
#import <libavutil/avutil.h>

#include "FFmpegStreamHelper.h"
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

// --- Logging shim (delegates to CTransmuxFFI's mks_log_impl) ---
//
// CTransmuxFFI owns the log file handle, FFmpeg av_log callback, and
// thread-safe formatting. This module just forward-declares the symbol
// (resolved at link time) and maps level strings to MKSLogLevel ints.
//
// MKSLogLevel values (from mks_log.h):
//   MKS_LOG_ERROR=16, MKS_LOG_WARNING=24, MKS_LOG_INFO=32, MKS_LOG_DEBUG=48

extern void mks_log_impl(const char *tag, int level, const char *fmt, ...);

/// Map level abbreviation string to MKSLogLevel numeric value.
static int level_from_str(const char *level) {
    if (strcmp(level, "ERR") == 0) return 16;  // MKS_LOG_ERROR
    if (strcmp(level, "WRN") == 0) return 24;  // MKS_LOG_WARNING
    if (strcmp(level, "DBG") == 0) return 48;  // MKS_LOG_DEBUG
    return 32;                                  // MKS_LOG_INFO
}

/// Write a log entry via the centralized CTransmuxFFI logging system.
static void log_to_file(const char *tag, const char *level, const char *fmt, ...) {
    char msg[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    mks_log_impl(tag, level_from_str(level), "%s", msg);
}

// --- Runtime layout detection ---

// Shift for AVStream fields (codecpar, time_base, disposition, etc.)
static int s_stream_shift = 0;
// Shift for AVCodecParameters fields (codec_type, codec_id, width, height, etc.)
static int s_cp_shift = 0;
static int s_detected = 0;

/// Validate whether a candidate pointer looks like AVCodecParameters by
/// checking that codec_type and codec_id are at the expected consecutive
/// offsets with sane values. Returns 1 if valid, 0 otherwise.
///
/// In AVCodecParameters, codec_type (enum AVMediaType, 4 bytes) and
/// codec_id (enum AVCodecID, 4 bytes) are always consecutive.
/// In AVCodecContext (the wrong struct), they are 12+ bytes apart.
/// This is the key distinguishing signal.
///
/// @param raw      Raw bytes of the candidate struct
/// @param ct_off   Offset of codec_type from raw (0 for no av_class, 8 for av_class)
/// @param label    Description for logging
static int validate_codecpar(const unsigned char *raw, size_t ct_off,
                             const char *label) {
    int ct = *(int *)(raw + ct_off);
    int ci = *(int *)(raw + ct_off + 4);

    log_to_file("CHelper", "DBG", "validate_codecpar(%s): ct_off=%zu codec_type=%d codec_id=%d",
                label, ct_off, ct, ci);

    // codec_type must be in [0..5] (AVMEDIA_TYPE_VIDEO..AVMEDIA_TYPE_NB-1)
    // codec_id must be positive and reasonable (0 = AV_CODEC_ID_NONE is invalid for a real stream)
    return (ct >= 0 && ct <= 5 && ci > 0 && ci < 200000);
}

/// Probe raw memory to detect av_class mismatches in both AVStream and
/// AVCodecParameters. Called once on first use with a populated context
/// (after avformat_find_stream_info).
///
/// Uses validation-based detection instead of NULL checks. The old approach
/// checked which pointer slot in AVStream was non-NULL, but at offset 16
/// AVStream.codec (deprecated AVCodecContext*) is also non-NULL, causing
/// the detector to pick the wrong pointer before checking offset 8 where
/// the real codecpar lives.
///
/// New approach: for each candidate pointer at both the header offset and
/// header_offset - 8, dereference it and check whether the pointed-to
/// memory looks like a valid AVCodecParameters (codec_type and codec_id
/// consecutive with sane values). This handles all 4 combinations of
/// AVStream x AVCodecParameters with/without av_class.
static void detect_field_shifts(const AVFormatContext *ctx) {
    if (s_detected) return;
    s_detected = 1;
    s_stream_shift = 0;
    s_cp_shift = 0;

    if (!ctx || ctx->nb_streams == 0) return;

    size_t header_cp_offset = offsetof(AVStream, codecpar);
    size_t header_ct_offset = offsetof(AVCodecParameters, codec_type);

    log_to_file("CHelper", "DBG", "detect_field_shifts: nb_streams=%u "
                "header codecpar_off=%zu codec_type_off=%zu",
                ctx->nb_streams, header_cp_offset, header_ct_offset);

    for (unsigned i = 0; i < ctx->nb_streams; i++) {
        AVStream *s = ctx->streams[i];
        if (!s) continue;

        const unsigned char *stream_raw = (const unsigned char *)s;

        // Try candidate pointers at two AVStream offsets:
        //   header_cp_offset     — headers match binary (stream_shift=0)
        //   header_cp_offset - 8 — binary lacks av_class (stream_shift=8)
        size_t candidate_offsets[2] = { header_cp_offset, header_cp_offset - 8 };
        int    candidate_shifts[2]  = { 0, 8 };
        const char *candidate_labels[2] = { "header", "shifted(-8)" };

        for (int c = 0; c < 2; c++) {
            size_t off = candidate_offsets[c];
            void *candidate = *(void **)(stream_raw + off);

            log_to_file("CHelper", "DBG", "AVStream[%u] ptr at off %zu (%s) = %p",
                        i, off, candidate_labels[c], candidate);

            // Skip NULL or clearly invalid pointers (< 4096 = first page, never a heap alloc)
            if (!candidate || (uintptr_t)candidate < 4096) continue;

            const unsigned char *cp_raw = (const unsigned char *)candidate;

            // Dump first 32 bytes for diagnostics
            char hexbuf[128];
            int pos = 0;
            for (int b = 0; b < 32 && pos < (int)sizeof(hexbuf) - 4; b++) {
                pos += snprintf(hexbuf + pos, sizeof(hexbuf) - pos, "%02x", cp_raw[b]);
                if (b % 8 == 7 && pos < (int)sizeof(hexbuf) - 2) {
                    pos += snprintf(hexbuf + pos, sizeof(hexbuf) - pos, " ");
                }
            }
            log_to_file("CHelper", "DBG", "candidate raw: %s", hexbuf);

            // Layout A: no av_class in AVCodecParameters binary
            //   codec_type at raw offset header_ct_offset - header_ct_offset = 0? No.
            //   If headers have av_class: header_ct_offset = 8, actual at raw+0 → cp_shift = 8
            //   If headers lack av_class: header_ct_offset = 0, actual at raw+0 → cp_shift = 0
            // Layout B: av_class present in AVCodecParameters binary
            //   codec_type at raw+8 if headers lack av_class → cp_shift = -8
            //   codec_type at raw+8 if headers have av_class → cp_shift = 0

            // Try: codec_type at raw + header_ct_offset (cp_shift = 0)
            if (validate_codecpar(cp_raw, header_ct_offset, "cp_shift=0")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = 0;
                log_to_file("CHelper", "INF", "DETECTED via %s: stream_shift=%d cp_shift=%d",
                            candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }

            // Try: codec_type at raw + header_ct_offset - 8 (binary lacks av_class, cp_shift = 8)
            if (header_ct_offset >= 8 &&
                validate_codecpar(cp_raw, header_ct_offset - 8, "cp_shift=8")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = 8;
                log_to_file("CHelper", "INF", "DETECTED via %s: stream_shift=%d cp_shift=%d",
                            candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }

            // Try: codec_type at raw + header_ct_offset + 8 (binary has av_class, headers don't, cp_shift = -8)
            if (validate_codecpar(cp_raw, header_ct_offset + 8, "cp_shift=-8")) {
                s_stream_shift = candidate_shifts[c];
                s_cp_shift = -8;
                log_to_file("CHelper", "INF", "DETECTED via %s: stream_shift=%d cp_shift=%d",
                            candidate_labels[c], s_stream_shift, s_cp_shift);
                return;
            }
        }
    }

    log_to_file("CHelper", "WRN", "could not detect layout from any stream, "
                "using header offsets (shift=0/0)");
}

// --- Raw field readers (apply detected shifts) ---

/// Read a pointer field from AVStream at a header-defined offset.
static void *read_stream_ptr(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(void **)(raw + header_offset - s_stream_shift);
}

/// Read an int field from AVStream at a header-defined offset.
static int read_stream_int(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(int *)(raw + header_offset - s_stream_shift);
}

/// Read an AVRational from AVStream at a header-defined offset.
static AVRational read_stream_rational(const AVStream *s, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)s;
    return *(AVRational *)(raw + header_offset - s_stream_shift);
}

/// Read an int field from AVCodecParameters at a header-defined offset.
static int read_cp_int(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(int *)(raw + header_offset - s_cp_shift);
}

/// Read a uint32 field from AVCodecParameters at a header-defined offset.
static uint32_t read_cp_uint32(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(uint32_t *)(raw + header_offset - s_cp_shift);
}

/// Write a uint32 field to AVCodecParameters at a header-defined offset.
static void write_cp_uint32(AVCodecParameters *cp, size_t header_offset, uint32_t val) {
    unsigned char *raw = (unsigned char *)cp;
    *(uint32_t *)(raw + header_offset - s_cp_shift) = val;
}

/// Read a pointer field from AVCodecParameters at a header-defined offset.
static void *read_cp_ptr(const AVCodecParameters *cp, size_t header_offset) {
    const unsigned char *raw = (const unsigned char *)cp;
    return *(void **)(raw + header_offset - s_cp_shift);
}

/// Write a pointer field to AVCodecParameters at a header-defined offset.
static void write_cp_ptr(AVCodecParameters *cp, size_t header_offset, void *val) {
    unsigned char *raw = (unsigned char *)cp;
    *(void **)(raw + header_offset - s_cp_shift) = val;
}

/// Write an int field to AVCodecParameters at a header-defined offset.
static void write_cp_int(AVCodecParameters *cp, size_t header_offset, int val) {
    unsigned char *raw = (unsigned char *)cp;
    *(int *)(raw + header_offset - s_cp_shift) = val;
}

// --- Corrected codecpar access ---

static AVCodecParameters *get_codecpar(const AVFormatContext *ctx, int idx) {
    if (!ctx || idx < 0 || (unsigned)idx >= ctx->nb_streams)
        return NULL;

    detect_field_shifts(ctx);

    AVStream *s = ctx->streams[idx];
    if (!s) return NULL;

    return (AVCodecParameters *)read_stream_ptr(s, offsetof(AVStream, codecpar));
}

static AVCodecParameters *get_stream_codecpar(const AVStream *s) {
    if (!s) return NULL;
    return (AVCodecParameters *)read_stream_ptr(s, offsetof(AVStream, codecpar));
}

// --- Stream inspection ---

int mks_stream_get_codec_type(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return AVMEDIA_TYPE_UNKNOWN;
    return read_cp_int(cp, offsetof(AVCodecParameters, codec_type));
}

int mks_stream_get_codec_id(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return AV_CODEC_ID_NONE;
    return read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
}

int mks_stream_get_disposition(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return 0;

    detect_field_shifts(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) return 0;

    return read_stream_int(s, offsetof(AVStream, disposition));
}

void mks_stream_get_time_base(const void *fmtCtx, int streamIndex,
                               int *num, int *den) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams) {
        *num = 0; *den = 1;
        return;
    }

    detect_field_shifts(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) { *num = 0; *den = 1; return; }

    AVRational tb = read_stream_rational(s, offsetof(AVStream, time_base));
    *num = tb.num;
    *den = tb.den;
}

int mks_stream_get_width(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return read_cp_int(cp, offsetof(AVCodecParameters, width));
}

int mks_stream_get_height(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return read_cp_int(cp, offsetof(AVCodecParameters, height));
}

int mks_format_get_nb_streams(const void *fmtCtx) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx) return 0;
    return (int)ctx->nb_streams;
}

// --- Output stream setup ---

int mks_stream_copy_codecpar(void *dstStream,
                              const void *srcFmtCtx,
                              int srcStreamIndex) {
    AVStream *dst = (AVStream *)dstStream;
    const AVFormatContext *ctx = (const AVFormatContext *)srcFmtCtx;

    AVCodecParameters *srcPar = get_codecpar(ctx, srcStreamIndex);
    AVCodecParameters *dstPar = get_stream_codecpar(dst);

    if (!srcPar || !dstPar) {
        log_to_file("CHelper", "ERR", "copy_codecpar FAILED: src=%p dst=%p",
                    (void *)srcPar, (void *)dstPar);
        return -1;
    }

    // Diagnostic: verify output stream codecpar location
    const unsigned char *dst_stream_raw = (const unsigned char *)dst;
    void *cp_at_8  = *(void **)(dst_stream_raw + 8);
    void *cp_at_16 = *(void **)(dst_stream_raw + 16);
    log_to_file("CHelper", "DBG", "output AVStream codecpar: at_off8=%p at_off16=%p resolved=%p",
                cp_at_8, cp_at_16, (void *)dstPar);

    // Log source codec info using shift-corrected reads
    int src_ct = read_cp_int(srcPar, offsetof(AVCodecParameters, codec_type));
    int src_ci = read_cp_int(srcPar, offsetof(AVCodecParameters, codec_id));
    log_to_file("CHelper", "DBG", "copy_codecpar: src=%p dst=%p src_type=%d src_id=%d "
                "stream_shift=%d cp_shift=%d",
                (void *)srcPar, (void *)dstPar, src_ct, src_ci,
                s_stream_shift, s_cp_shift);

    // --- Method 1: Try avcodec_parameters_copy ---
    // This may fail if symbol conflicts cause it to resolve to a different
    // FFmpeg build with incompatible AVCodecParameters layout.
    int ret = avcodec_parameters_copy(dstPar, srcPar);
    log_to_file("CHelper", "DBG", "avcodec_parameters_copy returned %d", ret);

    if (ret >= 0) {
        // Verify: read codec_type and codec_id from dst using corrected offsets
        int dst_ct = read_cp_int(dstPar, offsetof(AVCodecParameters, codec_type));
        int dst_ci = read_cp_int(dstPar, offsetof(AVCodecParameters, codec_id));
        log_to_file("CHelper", "DBG", "post-copy verify: dst_type=%d dst_id=%d",
                    dst_ct, dst_ci);

        if (dst_ct >= 0 && dst_ct <= 5 && dst_ci != 0) {
            log_to_file("CHelper", "INF", "avcodec_parameters_copy verified OK");
            // Clear codec_tag for output container compatibility
            write_cp_uint32(dstPar, offsetof(AVCodecParameters, codec_tag), 0);
            return 0;
        }
        log_to_file("CHelper", "WRN", "avcodec_parameters_copy produced bad result, "
                    "trying raw memcpy fallback");
    }

    // --- Method 2: Raw memcpy fallback ---
    // Both srcPar and dstPar are real pointers to AVCodecParameters allocated
    // by the same avformat library (avformat_find_stream_info / avformat_new_stream).
    // A raw memcpy transfers all fields at their correct binary offsets,
    // bypassing avcodec_parameters_copy which may resolve to a different library.
    size_t copy_size = sizeof(AVCodecParameters);
    log_to_file("CHelper", "INF", "raw memcpy fallback: %zu bytes src=%p -> dst=%p",
                copy_size, (void *)srcPar, (void *)dstPar);

    // Step 1: Read source extradata info BEFORE memcpy (using corrected offsets)
    void *src_extradata = read_cp_ptr(srcPar, offsetof(AVCodecParameters, extradata));
    int src_extradata_size = read_cp_int(srcPar, offsetof(AVCodecParameters, extradata_size));
    log_to_file("CHelper", "DBG", "src extradata=%p size=%d",
                src_extradata, src_extradata_size);

    // Step 2: Free destination's existing extradata (if any)
    void *old_dst_extradata = read_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata));
    if (old_dst_extradata) {
        av_free(old_dst_extradata);
    }

    // Step 3: Raw memcpy of the struct
    // sizeof from headers may be ~8 bytes smaller than real struct if headers
    // lack av_class. This is safe — we just miss trailing padding/fields.
    memcpy(dstPar, srcPar, copy_size);

    // Step 4: Duplicate extradata to avoid shared pointer (double-free on cleanup)
    if (src_extradata && src_extradata_size > 0) {
        void *new_extradata = av_malloc(src_extradata_size + AV_INPUT_BUFFER_PADDING_SIZE);
        if (new_extradata) {
            memcpy(new_extradata, src_extradata, src_extradata_size);
            memset((uint8_t *)new_extradata + src_extradata_size, 0,
                   AV_INPUT_BUFFER_PADDING_SIZE);
            write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), new_extradata);
        } else {
            log_to_file("CHelper", "WRN", "extradata av_malloc failed");
            write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), NULL);
            write_cp_int(dstPar, offsetof(AVCodecParameters, extradata_size), 0);
        }
    } else {
        write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), NULL);
        write_cp_int(dstPar, offsetof(AVCodecParameters, extradata_size), 0);
    }

    // Step 5: Clear codec_tag for output container compatibility
    write_cp_uint32(dstPar, offsetof(AVCodecParameters, codec_tag), 0);

    // Verify memcpy result
    int dst_ct2 = read_cp_int(dstPar, offsetof(AVCodecParameters, codec_type));
    int dst_ci2 = read_cp_int(dstPar, offsetof(AVCodecParameters, codec_id));
    log_to_file("CHelper", "INF", "memcpy done: dst_type=%d dst_id=%d", dst_ct2, dst_ci2);

    return 0;
}

void mks_stream_set_frame_size(void *fmtCtx, int streamIndex, int frameSize) {
    AVCodecParameters *cp = get_codecpar((AVFormatContext *)fmtCtx, streamIndex);
    if (cp) {
        write_cp_int(cp, offsetof(AVCodecParameters, frame_size), frameSize);
        log_to_file("CHelper", "INF", "set frame_size=%d on stream %d",
                    frameSize, streamIndex);
    }
}

int mks_stream_has_extradata(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    void *extradata = read_cp_ptr(cp, offsetof(AVCodecParameters, extradata));
    int extradata_size = read_cp_int(cp, offsetof(AVCodecParameters, extradata_size));
    return (extradata != NULL && extradata_size > 0) ? 1 : 0;
}

void mks_stream_clear_codec_tag(void *stream) {
    AVStream *s = (AVStream *)stream;
    AVCodecParameters *cp = get_stream_codecpar(s);
    if (cp)
        write_cp_uint32(cp, offsetof(AVCodecParameters, codec_tag), 0);
}

// --- Packet helpers ---

int mks_packet_get_stream_index(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return -1;
    return p->stream_index;
}

void mks_packet_set_stream_index(void *pkt, int index) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->stream_index = index;
}

void mks_packet_rescale_ts(void *pkt,
                            const void *srcFmtCtx, int srcStreamIndex,
                            const void *dstFmtCtx, int dstStreamIndex) {
    AVPacket *p = (AVPacket *)pkt;
    const AVFormatContext *src = (const AVFormatContext *)srcFmtCtx;
    const AVFormatContext *dst = (const AVFormatContext *)dstFmtCtx;
    if (!p || !src || !dst) return;
    if (srcStreamIndex < 0 || (unsigned)srcStreamIndex >= src->nb_streams) return;
    if (dstStreamIndex < 0 || (unsigned)dstStreamIndex >= dst->nb_streams) return;

    detect_field_shifts(src);

    AVStream *srcStream = src->streams[srcStreamIndex];
    AVStream *dstStream = dst->streams[dstStreamIndex];
    if (!srcStream || !dstStream) return;

    AVRational srcTB = read_stream_rational(srcStream, offsetof(AVStream, time_base));
    AVRational dstTB = read_stream_rational(dstStream, offsetof(AVStream, time_base));

    av_packet_rescale_ts(p, srcTB, dstTB);
}

void mks_packet_clear_pos(void *pkt) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->pos = -1;
}

// --- Bitstream filter (BSF) ---

void *mks_bsf_create_aac_adtstoasc(const void *fmtCtx, int audioStreamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || audioStreamIndex < 0 || (unsigned)audioStreamIndex >= ctx->nb_streams)
        return NULL;

    detect_field_shifts(ctx);

    const AVBitStreamFilter *filter = av_bsf_get_by_name("aac_adtstoasc");
    if (!filter) {
        log_to_file("CHelper", "ERR", "aac_adtstoasc BSF not found in this FFmpeg build");
        return NULL;
    }

    AVBSFContext *bsfCtx = NULL;
    int ret = av_bsf_alloc(filter, &bsfCtx);
    if (ret < 0 || !bsfCtx) {
        log_to_file("CHelper", "ERR", "av_bsf_alloc failed: %d", ret);
        return NULL;
    }

    // Copy codec parameters from the input audio stream to the BSF input.
    // Both pointers are resolved through C code which sees the correct layout.
    AVCodecParameters *srcPar = get_codecpar(ctx, audioStreamIndex);
    if (!srcPar) {
        log_to_file("CHelper", "ERR", "Cannot get codecpar for audio stream %d",
                    audioStreamIndex);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    ret = avcodec_parameters_copy(bsfCtx->par_in, srcPar);
    if (ret < 0) {
        log_to_file("CHelper", "ERR", "avcodec_parameters_copy to BSF par_in failed: %d", ret);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    // Set input time_base from the audio stream
    AVStream *s = ctx->streams[audioStreamIndex];
    bsfCtx->time_base_in = read_stream_rational(s, offsetof(AVStream, time_base));

    ret = av_bsf_init(bsfCtx);
    if (ret < 0) {
        log_to_file("CHelper", "ERR", "av_bsf_init failed: %d", ret);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    log_to_file("CHelper", "INF", "aac_adtstoasc BSF created for stream %d",
                audioStreamIndex);
    return bsfCtx;
}

int mks_bsf_filter_packet(void *bsfCtx, void *pkt) {
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    AVPacket *p = (AVPacket *)pkt;
    if (!ctx || !p) return -1;

    int ret = av_bsf_send_packet(ctx, p);
    if (ret < 0) return ret;

    ret = av_bsf_receive_packet(ctx, p);
    return ret;
}

void mks_bsf_free(void *bsfCtx) {
    if (!bsfCtx) return;
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    av_bsf_free(&ctx);
    log_to_file("CHelper", "INF", "BSF freed");
}

// --- Seek support ---

void mks_format_flush_input(void *fmtCtx) {
    AVFormatContext *ctx = (AVFormatContext *)fmtCtx;
    if (!ctx) return;

    int ret = avformat_flush(ctx);
    log_to_file("CHelper", "DBG", "avformat_flush returned %d", ret);
}

void mks_bsf_flush(void *bsfCtx) {
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    if (!ctx) return;

    // av_bsf_flush resets the BSF to its initial state, ready for new packets.
    // DO NOT use av_bsf_send_packet(NULL) — that puts the BSF into permanent
    // EOF/drain mode, causing all subsequent audio packets to be rejected with
    // "A non-NULL packet sent after an EOF".
    av_bsf_flush(ctx);

    log_to_file("CHelper", "INF", "BSF flushed after seek");
}

int mks_packet_is_keyframe(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return 0;
    return (p->flags & AV_PKT_FLAG_KEY) ? 1 : 0;
}

void mks_packet_adjust_ts(void *pkt, int64_t dtsOffset) {
    AVPacket *p = (AVPacket *)pkt;
    if (!p) return;

    if (p->dts != AV_NOPTS_VALUE) {
        p->dts += dtsOffset;
    }
    if (p->pts != AV_NOPTS_VALUE) {
        p->pts += dtsOffset;
    }
}

int64_t mks_packet_get_dts(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return AV_NOPTS_VALUE;
    return p->dts;
}

int64_t mks_packet_get_pts(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return AV_NOPTS_VALUE;
    return p->pts;
}

void mks_packet_set_dts(void *pkt, int64_t dts) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->dts = dts;
}

// --- Stream metadata ---

/// Read a metadata tag from a stream's AVDictionary.
/// AVStream.metadata is accessed via shift-corrected offset (same as codecpar, time_base, etc.)
static int read_stream_metadata(const AVFormatContext *ctx, int streamIndex,
                                 const char *key, char *buf, int bufSize) {
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams || !buf || bufSize <= 0)
        return -1;

    detect_field_shifts(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) return -1;

    // Read metadata dictionary via shift-corrected offset
    AVDictionary *meta = (AVDictionary *)read_stream_ptr(s, offsetof(AVStream, metadata));
    if (!meta) {
        buf[0] = '\0';
        return -1;
    }

    AVDictionaryEntry *entry = av_dict_get(meta, key, NULL, 0);
    if (!entry || !entry->value) {
        buf[0] = '\0';
        return -1;
    }

    snprintf(buf, bufSize, "%s", entry->value);
    return 0;
}

int mks_stream_get_language(const void *fmtCtx, int streamIndex,
                            char *buf, int bufSize) {
    return read_stream_metadata((const AVFormatContext *)fmtCtx, streamIndex,
                                 "language", buf, bufSize);
}

int mks_stream_get_title(const void *fmtCtx, int streamIndex,
                         char *buf, int bufSize) {
    return read_stream_metadata((const AVFormatContext *)fmtCtx, streamIndex,
                                 "title", buf, bufSize);
}

int mks_stream_get_channels(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;

    // AVChannelLayout { enum AVChannelOrder order (4 bytes); int nb_channels (4 bytes); ... }
    // nb_channels is at ch_layout + 4 bytes offset.
    // read_cp_int already applies s_cp_shift, so we add 4 to the header offset.
    int nb_channels = read_cp_int(cp, offsetof(AVCodecParameters, ch_layout) + 4);

    if (nb_channels > 0 && nb_channels < 64) return nb_channels;

    return 0;
}

int mks_stream_get_sample_rate(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return read_cp_int(cp, offsetof(AVCodecParameters, sample_rate));
}

int mks_stream_get_subtitle_codec_id(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return 0;

    int codec_type = mks_stream_get_codec_type(fmtCtx, streamIndex);
    if (codec_type != AVMEDIA_TYPE_SUBTITLE) return 0;

    return mks_stream_get_codec_id(fmtCtx, streamIndex);
}

// --- Subtitle extraction ---

/// Format a timestamp as HH:MM:SS.mmm for WebVTT
static void format_vtt_timestamp(char *buf, size_t bufsize, int64_t ms) {
    if (ms < 0) ms = 0;
    int h  = (int)(ms / 3600000);
    int m  = (int)((ms % 3600000) / 60000);
    int s  = (int)((ms % 60000) / 1000);
    int mm = (int)(ms % 1000);
    snprintf(buf, bufsize, "%02d:%02d:%02d.%03d", h, m, s, mm);
}

// --- Subtitle collector (in-band, fed during remux loop) ---
// IPTV servers block concurrent connections, so we collect subtitle packets
// from the SAME av_read_frame loop used for A/V remux — zero extra connections.

#define MAX_SUB_STREAMS 16

struct MKSSubtitleCollector {
    int streamCount;
    int streamIndices[MAX_SUB_STREAMS];
    AVCodecContext *decoders[MAX_SUB_STREAMS];
    FILE *files[MAX_SUB_STREAMS];
    AVRational timeBases[MAX_SUB_STREAMS];
    int cueCounts[MAX_SUB_STREAMS];
    int activeCount;
};

MKSSubtitleCollector *mks_subtitle_collector_create(
    const void *fmtCtx,
    int streamCount,
    const int *streamIndices,
    const char *const *outputPaths)
{
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamCount <= 0 || streamCount > MAX_SUB_STREAMS ||
        !streamIndices || !outputPaths)
        return NULL;

    MKSSubtitleCollector *c = calloc(1, sizeof(MKSSubtitleCollector));
    if (!c) return NULL;

    c->streamCount = streamCount;
    c->activeCount = 0;

    for (int i = 0; i < streamCount; i++) {
        c->streamIndices[i] = streamIndices[i];
        c->cueCounts[i] = 0;
        c->decoders[i] = NULL;
        c->files[i] = NULL;

        int idx = streamIndices[i];
        if (idx < 0 || (unsigned)idx >= ctx->nb_streams) {
            log_to_file("CHelper", "WRN", "sub collector: stream %d out of range", idx);
            continue;
        }

        AVCodecParameters *cp = get_codecpar(ctx, idx);
        if (!cp) continue;

        int codec_id = read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
        const AVCodec *decoder = avcodec_find_decoder(codec_id);
        if (!decoder) {
            log_to_file("CHelper", "WRN", "sub collector: no decoder for stream %d (codec_id=%d)", idx, codec_id);
            continue;
        }

        AVCodecContext *dc = avcodec_alloc_context3(decoder);
        if (!dc) continue;

        avcodec_parameters_to_context(dc, cp);
        int ret = avcodec_open2(dc, decoder, NULL);
        if (ret < 0) {
            log_to_file("CHelper", "WRN", "sub collector: open2 failed stream %d (ret=%d)", idx, ret);
            avcodec_free_context(&dc);
            continue;
        }

        FILE *f = fopen(outputPaths[i], "w");
        if (!f) { avcodec_free_context(&dc); continue; }
        fprintf(f, "WEBVTT\n\n");

        c->decoders[i] = dc;
        c->files[i] = f;

        AVStream *st = ctx->streams[idx];
        c->timeBases[i] = read_stream_rational(st, offsetof(AVStream, time_base));
        if (c->timeBases[i].den == 0) { c->timeBases[i].num = 1; c->timeBases[i].den = 1000; }

        c->activeCount++;
        log_to_file("CHelper", "INF", "sub collector: stream %d ready (codec_id=%d, tb=%d/%d)",
                    idx, codec_id, c->timeBases[i].num, c->timeBases[i].den);
    }

    if (c->activeCount == 0) {
        log_to_file("CHelper", "WRN", "sub collector: no decodable subtitle streams");
        free(c);
        return NULL;
    }

    log_to_file("CHelper", "INF", "sub collector: created with %d/%d active streams",
                c->activeCount, streamCount);
    return c;
}

void mks_subtitle_collector_feed(MKSSubtitleCollector *collector, const void *rawPkt) {
    if (!collector || !rawPkt) return;
    const AVPacket *pkt = (const AVPacket *)rawPkt;

    // Find matching slot
    int slot = -1;
    for (int i = 0; i < collector->streamCount; i++) {
        if (pkt->stream_index == collector->streamIndices[i] &&
            collector->decoders[i] && collector->files[i]) {
            slot = i;
            break;
        }
    }
    if (slot < 0) return;

    AVSubtitle sub;
    int gotSub = 0;
    int ret = avcodec_decode_subtitle2(collector->decoders[slot], &sub, &gotSub,
                                        (AVPacket *)rawPkt);
    if (ret < 0 || !gotSub) return;

    int64_t pts_ms = 0;
    if (pkt->pts != AV_NOPTS_VALUE) {
        pts_ms = av_rescale_q(pkt->pts, collector->timeBases[slot], (AVRational){1, 1000});
    }
    int64_t start_ms = pts_ms + sub.start_display_time;
    int64_t end_ms   = pts_ms + sub.end_display_time;
    if (end_ms <= start_ms) end_ms = start_ms + 5000;

    FILE *f = collector->files[slot];
    for (unsigned r = 0; r < sub.num_rects; r++) {
        AVSubtitleRect *rect = sub.rects[r];
        const char *text = NULL;

        if (rect->type == SUBTITLE_TEXT && rect->text) {
            text = rect->text;
        } else if (rect->type == SUBTITLE_ASS && rect->ass) {
            text = rect->ass;
            int commas = 0;
            while (*text && commas < 8) { if (*text == ',') commas++; text++; }
        }

        if (text && text[0] != '\0') {
            int cc = collector->cueCounts[slot];
            char startTS[16], endTS[16];
            format_vtt_timestamp(startTS, sizeof(startTS), start_ms);
            format_vtt_timestamp(endTS, sizeof(endTS), end_ms);
            fprintf(f, "%d\n%s --> %s\n", cc + 1, startTS, endTS);

            const char *p = text;
            int inOverride = 0;
            while (*p) {
                if (*p == '{' && *(p+1) == '\\') { inOverride = 1; p++; continue; }
                if (inOverride) { if (*p == '}') inOverride = 0; p++; continue; }
                if (*p == '\\' && (*(p+1) == 'N' || *(p+1) == 'n')) { fprintf(f, "\n"); p += 2; continue; }
                fputc(*p, f);
                p++;
            }
            fprintf(f, "\n\n");
            fflush(f);  // Flush so TransmuxServer can serve partial VTT
            collector->cueCounts[slot] = cc + 1;
        }
    }
    avsubtitle_free(&sub);
}

void mks_subtitle_collector_finish(MKSSubtitleCollector *collector, int *cueCounts) {
    if (!collector) return;

    int totalCues = 0;
    for (int i = 0; i < collector->streamCount; i++) {
        if (collector->files[i]) fclose(collector->files[i]);
        if (collector->decoders[i]) avcodec_free_context(&collector->decoders[i]);
        if (cueCounts) cueCounts[i] = collector->cueCounts[i];
        totalCues += collector->cueCounts[i];
        if (collector->cueCounts[i] > 0) {
            log_to_file("CHelper", "INF", "sub collector: stream %d -> %d cues",
                        collector->streamIndices[i], collector->cueCounts[i]);
        }
    }
    log_to_file("CHelper", "INF", "sub collector: finished, %d total cues from %d streams",
                totalCues, collector->activeCount);
    free(collector);
}

#undef MAX_SUB_STREAMS

// --- Audio Transcoder Implementation (AC3/EAC3/DTS → AAC) ---

#import <libswresample/swresample.h>

struct MKSAudioTranscoder {
    AVCodecContext *decoderCtx;
    AVCodecContext *encoderCtx;
    struct SwrContext *swrCtx;
    AVFrame *decodedFrame;
    AVFrame *resampledFrame;
    int64_t nextPts;  // running PTS counter for encoder (in encoder time_base)
};

MKSAudioTranscoder *mks_audio_transcoder_create(
    const void *inputFmtCtx,
    int inputStreamIndex,
    int targetBitrate,
    int targetSampleRate,
    int targetChannels)
{
    const AVFormatContext *inCtx = (const AVFormatContext *)inputFmtCtx;
    if (!inCtx || inputStreamIndex < 0 || (unsigned)inputStreamIndex >= inCtx->nb_streams) {
        log_to_file("Transcode", "ERR", "invalid input context or stream index %d", inputStreamIndex);
        return NULL;
    }

    detect_field_shifts(inCtx);

    AVCodecParameters *srcPar = get_codecpar(inCtx, inputStreamIndex);
    if (!srcPar) {
        log_to_file("Transcode", "ERR", "cannot get codecpar for stream %d", inputStreamIndex);
        return NULL;
    }

    int srcCodecId = read_cp_int(srcPar, offsetof(AVCodecParameters, codec_id));

    // Only transcode AC3 (86019), EAC3 (86056), DTS (86076)
    if (srcCodecId != AV_CODEC_ID_AC3 &&
        srcCodecId != AV_CODEC_ID_EAC3 &&
        srcCodecId != AV_CODEC_ID_DTS) {
        log_to_file("Transcode", "WRN", "codec_id %d is not AC3/EAC3/DTS, no transcoding needed", srcCodecId);
        return NULL;
    }

    const char *codecName = srcCodecId == AV_CODEC_ID_AC3 ? "AC3" :
                            srcCodecId == AV_CODEC_ID_EAC3 ? "EAC3" : "DTS";

    // --- Set up decoder ---
    const AVCodec *decoder = avcodec_find_decoder(srcCodecId);
    if (!decoder) {
        log_to_file("Transcode", "ERR", "no decoder found for %s (id=%d)", codecName, srcCodecId);
        return NULL;
    }

    AVCodecContext *decCtx = avcodec_alloc_context3(decoder);
    if (!decCtx) {
        log_to_file("Transcode", "ERR", "failed to allocate decoder context");
        return NULL;
    }

    int ret = avcodec_parameters_to_context(decCtx, srcPar);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "avcodec_parameters_to_context failed: %d", ret);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // Set decoder time_base from input stream
    AVStream *inStream = inCtx->streams[inputStreamIndex];
    decCtx->pkt_timebase = read_stream_rational(inStream, offsetof(AVStream, time_base));

    ret = avcodec_open2(decCtx, decoder, NULL);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "avcodec_open2 decoder failed: %d", ret);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    int srcSampleRate = decCtx->sample_rate;
    int srcChannels = decCtx->ch_layout.nb_channels;
    if (srcSampleRate <= 0) srcSampleRate = 48000;
    if (srcChannels <= 0) srcChannels = 2;

    int outSampleRate = targetSampleRate > 0 ? targetSampleRate : srcSampleRate;
    int outChannels = targetChannels > 0 ? targetChannels : srcChannels;

    log_to_file("Transcode", "INF", "decoder opened: %s %dch %dHz → target AAC %dch %dHz %dkbps",
                codecName, srcChannels, srcSampleRate, outChannels, outSampleRate, targetBitrate / 1000);

    // --- Set up AAC encoder ---
    const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!encoder) {
        log_to_file("Transcode", "ERR", "no AAC encoder found in FFmpeg build");
        avcodec_free_context(&decCtx);
        return NULL;
    }

    AVCodecContext *encCtx = avcodec_alloc_context3(encoder);
    if (!encCtx) {
        log_to_file("Transcode", "ERR", "failed to allocate encoder context");
        avcodec_free_context(&decCtx);
        return NULL;
    }

    encCtx->sample_fmt = AV_SAMPLE_FMT_FLTP;  // FFmpeg native AAC requires planar float
    encCtx->sample_rate = outSampleRate;
    encCtx->bit_rate = targetBitrate;
    av_channel_layout_default(&encCtx->ch_layout, outChannels);
    encCtx->time_base = (AVRational){1, outSampleRate};
    encCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;  // extradata in codecpar, not in-band

    ret = avcodec_open2(encCtx, encoder, NULL);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "avcodec_open2 encoder failed: %d", ret);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    log_to_file("Transcode", "INF", "AAC encoder opened: %dch %dHz %dkbps frame_size=%d",
                outChannels, outSampleRate, targetBitrate / 1000, encCtx->frame_size);

    // --- Set up resampler ---
    struct SwrContext *swr = NULL;
    ret = swr_alloc_set_opts2(&swr,
                               &encCtx->ch_layout,      // output layout
                               AV_SAMPLE_FMT_FLTP,      // output format
                               outSampleRate,            // output rate
                               &decCtx->ch_layout,       // input layout
                               decCtx->sample_fmt,       // input format
                               srcSampleRate,             // input rate
                               0, NULL);
    if (ret < 0 || !swr) {
        log_to_file("Transcode", "ERR", "swr_alloc_set_opts2 failed: %d", ret);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    ret = swr_init(swr);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "swr_init failed: %d", ret);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // --- Allocate frames ---
    AVFrame *decodedFrame = av_frame_alloc();
    AVFrame *resampledFrame = av_frame_alloc();
    if (!decodedFrame || !resampledFrame) {
        log_to_file("Transcode", "ERR", "failed to allocate frames");
        if (decodedFrame) av_frame_free(&decodedFrame);
        if (resampledFrame) av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // Pre-configure resampled frame for the encoder
    resampledFrame->format = AV_SAMPLE_FMT_FLTP;
    resampledFrame->sample_rate = outSampleRate;
    av_channel_layout_copy(&resampledFrame->ch_layout, &encCtx->ch_layout);
    resampledFrame->nb_samples = encCtx->frame_size;

    ret = av_frame_get_buffer(resampledFrame, 0);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "av_frame_get_buffer failed: %d", ret);
        av_frame_free(&decodedFrame);
        av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // --- Create transcoder struct ---
    MKSAudioTranscoder *tc = calloc(1, sizeof(MKSAudioTranscoder));
    if (!tc) {
        av_frame_free(&decodedFrame);
        av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    tc->decoderCtx = decCtx;
    tc->encoderCtx = encCtx;
    tc->swrCtx = swr;
    tc->decodedFrame = decodedFrame;
    tc->resampledFrame = resampledFrame;
    tc->nextPts = 0;

    log_to_file("Transcode", "INF", "audio transcoder created: %s → AAC (%dch %dHz %dkbps)",
                codecName, outChannels, outSampleRate, targetBitrate / 1000);
    return tc;
}

int mks_audio_transcoder_setup_output(MKSAudioTranscoder *ctx, void *outputStream) {
    if (!ctx || !outputStream) return -1;

    AVStream *outStream = (AVStream *)outputStream;
    AVCodecParameters *outPar = get_stream_codecpar(outStream);
    if (!outPar) {
        log_to_file("Transcode", "ERR", "cannot get output stream codecpar");
        return -1;
    }

    int ret = avcodec_parameters_from_context(outPar, ctx->encoderCtx);
    if (ret < 0) {
        log_to_file("Transcode", "ERR", "avcodec_parameters_from_context failed: %d", ret);
        return ret;
    }

    // Clear codec_tag for container compatibility
    write_cp_uint32(outPar, offsetof(AVCodecParameters, codec_tag), 0);

    log_to_file("Transcode", "INF", "output stream configured: AAC %dch %dHz",
                ctx->encoderCtx->ch_layout.nb_channels, ctx->encoderCtx->sample_rate);
    return 0;
}

/// Internal: drain decoded frames through resampler + encoder.
/// Called after avcodec_send_packet() to process all available decoded frames.
static int transcode_drain_decoded(MKSAudioTranscoder *ctx) {
    int ret;

    while (1) {
        ret = avcodec_receive_frame(ctx->decoderCtx, ctx->decodedFrame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            return 0;  // need more input or decoder fully drained
        }
        if (ret < 0) {
            log_to_file("Transcode", "ERR", "avcodec_receive_frame failed: %d", ret);
            return ret;
        }

        // Resample decoded frame → encoder-compatible frame
        // swr_convert processes all samples from decodedFrame. If it produces
        // enough for a full encoder frame (frame_size samples), we send it.
        // Otherwise samples are buffered internally by SwrContext.
        int samplesInSwr = swr_get_out_samples(ctx->swrCtx, ctx->decodedFrame->nb_samples);

        // Convert into resampledFrame's buffer
        const uint8_t **in_data = (const uint8_t **)ctx->decodedFrame->extended_data;

        while (samplesInSwr >= ctx->encoderCtx->frame_size || ctx->decodedFrame->nb_samples > 0) {
            // Make the resampled frame writable
            av_frame_make_writable(ctx->resampledFrame);
            ctx->resampledFrame->nb_samples = ctx->encoderCtx->frame_size;

            int converted;
            if (ctx->decodedFrame->nb_samples > 0) {
                converted = swr_convert(ctx->swrCtx,
                                       ctx->resampledFrame->extended_data,
                                       ctx->resampledFrame->nb_samples,
                                       in_data,
                                       ctx->decodedFrame->nb_samples);
                ctx->decodedFrame->nb_samples = 0;  // consumed
                in_data = NULL;  // subsequent calls pull from swr internal buffer
            } else {
                converted = swr_convert(ctx->swrCtx,
                                       ctx->resampledFrame->extended_data,
                                       ctx->resampledFrame->nb_samples,
                                       NULL, 0);
            }

            if (converted <= 0) break;

            if (converted < ctx->encoderCtx->frame_size) {
                // Not enough samples for a full frame — swr buffers them
                break;
            }

            ctx->resampledFrame->nb_samples = converted;
            ctx->resampledFrame->pts = ctx->nextPts;
            ctx->nextPts += converted;

            ret = avcodec_send_frame(ctx->encoderCtx, ctx->resampledFrame);
            if (ret < 0 && ret != AVERROR(EAGAIN)) {
                log_to_file("Transcode", "ERR", "avcodec_send_frame failed: %d", ret);
                av_frame_unref(ctx->decodedFrame);
                return ret;
            }

            // Check if there are still enough samples in swr
            samplesInSwr = swr_get_out_samples(ctx->swrCtx, 0);
            if (samplesInSwr < ctx->encoderCtx->frame_size) break;
        }

        av_frame_unref(ctx->decodedFrame);
    }
}

int mks_audio_transcoder_send(MKSAudioTranscoder *ctx, const void *inputPacket) {
    if (!ctx || !inputPacket) return -1;

    const AVPacket *pkt = (const AVPacket *)inputPacket;

    int ret = avcodec_send_packet(ctx->decoderCtx, pkt);
    if (ret < 0 && ret != AVERROR(EAGAIN)) {
        log_to_file("Transcode", "ERR", "avcodec_send_packet failed: %d", ret);
        return ret;
    }

    return transcode_drain_decoded(ctx);
}

int mks_audio_transcoder_receive(MKSAudioTranscoder *ctx, void *outputPacket) {
    if (!ctx || !outputPacket) return AVERROR(EINVAL);

    AVPacket *pkt = (AVPacket *)outputPacket;
    return avcodec_receive_packet(ctx->encoderCtx, pkt);
}

int mks_audio_transcoder_flush(MKSAudioTranscoder *ctx) {
    if (!ctx) return -1;

    // 1. Flush decoder (send NULL packet)
    avcodec_send_packet(ctx->decoderCtx, NULL);
    int ret = transcode_drain_decoded(ctx);
    if (ret < 0) return ret;

    // 2. Flush remaining samples from resampler
    while (1) {
        av_frame_make_writable(ctx->resampledFrame);
        ctx->resampledFrame->nb_samples = ctx->encoderCtx->frame_size;

        int converted = swr_convert(ctx->swrCtx,
                                     ctx->resampledFrame->extended_data,
                                     ctx->resampledFrame->nb_samples,
                                     NULL, 0);
        if (converted <= 0) break;

        ctx->resampledFrame->nb_samples = converted;
        ctx->resampledFrame->pts = ctx->nextPts;
        ctx->nextPts += converted;

        ret = avcodec_send_frame(ctx->encoderCtx, ctx->resampledFrame);
        if (ret < 0 && ret != AVERROR(EAGAIN)) break;
    }

    // 3. Flush encoder (send NULL frame)
    avcodec_send_frame(ctx->encoderCtx, NULL);

    log_to_file("Transcode", "INF", "transcoder flushed (nextPts=%lld)", (long long)ctx->nextPts);
    return 0;
}

void mks_audio_transcoder_reset(MKSAudioTranscoder *ctx) {
    if (!ctx) return;

    // Flush both codecs
    avcodec_flush_buffers(ctx->decoderCtx);
    avcodec_flush_buffers(ctx->encoderCtx);

    // Reset resampler: close + reinit clears internal sample buffer
    if (ctx->swrCtx) {
        swr_close(ctx->swrCtx);
        swr_init(ctx->swrCtx);
    }

    ctx->nextPts = 0;
    log_to_file("Transcode", "INF", "transcoder reset after seek");
}

void mks_audio_transcoder_get_time_base(MKSAudioTranscoder *ctx, int *num, int *den) {
    if (!ctx || !num || !den) {
        if (num) *num = 0;
        if (den) *den = 1;
        return;
    }
    *num = ctx->encoderCtx->time_base.num;
    *den = ctx->encoderCtx->time_base.den;
}

void mks_audio_transcoder_free(MKSAudioTranscoder *ctx) {
    if (!ctx) return;

    if (ctx->decodedFrame) av_frame_free(&ctx->decodedFrame);
    if (ctx->resampledFrame) av_frame_free(&ctx->resampledFrame);
    if (ctx->swrCtx) swr_free(&ctx->swrCtx);
    if (ctx->encoderCtx) avcodec_free_context(&ctx->encoderCtx);
    if (ctx->decoderCtx) avcodec_free_context(&ctx->decoderCtx);

    log_to_file("Transcode", "INF", "audio transcoder freed");
    free(ctx);
}

// --- Diagnostics (moved after collector) ---
static int _removed_legacy_extract_fn = 0;  // was: _unused_mks_subtitle_extract_all_to_vtt
// The standalone extraction function was removed — use the in-band collector instead.

#if 0  // Legacy extraction function — REMOVED (IPTV servers reject extra connections)
static int _unused_mks_subtitle_extract_all_to_vtt(const char *inputURL,
                                     int streamCount,
                                     const int *streamIndices,
                                     const char * const *outputPaths,
                                     int *cueCounts) {
    if (!inputURL || streamCount <= 0 || !streamIndices || !outputPaths || !cueCounts)
        return -1;

    for (int i = 0; i < streamCount; i++) cueCounts[i] = 0;

    // Open ONE connection for all subtitle streams
    // Must pass same HTTP options as main transmux (reconnect, probesize)
    // or IPTV servers may reject the connection
    AVFormatContext *subCtx = NULL;
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "reconnect", "1", 0);
    av_dict_set(&opts, "reconnect_streamed", "1", 0);
    av_dict_set(&opts, "reconnect_delay_max", "5", 0);
    log_to_file("CHelper", "INF", "subtitle extract: opening %s for %d streams", inputURL, streamCount);
    int ret = avformat_open_input(&subCtx, inputURL, NULL, &opts);
    av_dict_free(&opts);
    if (ret < 0 || !subCtx) {
        log_to_file("CHelper", "ERR", "subtitle extract: cannot open input (ret=%d)", ret);
        return -1;
    }

    ret = avformat_find_stream_info(subCtx, NULL);
    if (ret < 0) {
        log_to_file("CHelper", "ERR", "subtitle extract: find_stream_info failed (ret=%d)", ret);
        avformat_close_input(&subCtx);
        return -1;
    }

    detect_field_shifts(subCtx);

    // Set up per-stream decoder contexts, output files, and time bases
    #define MAX_SUB_STREAMS 16
    if (streamCount > MAX_SUB_STREAMS) streamCount = MAX_SUB_STREAMS;

    AVCodecContext *decCtxs[MAX_SUB_STREAMS] = {0};
    FILE *outFiles[MAX_SUB_STREAMS] = {0};
    AVRational timeBases[MAX_SUB_STREAMS] = {{0}};
    int activeCount = 0;

    for (int i = 0; i < streamCount; i++) {
        int idx = streamIndices[i];
        if (idx < 0 || (unsigned)idx >= subCtx->nb_streams) {
            log_to_file("CHelper", "WRN", "subtitle extract: stream %d out of range, skipping", idx);
            continue;
        }

        AVCodecParameters *cp = get_codecpar(subCtx, idx);
        if (!cp) continue;

        int codec_id = read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
        const AVCodec *decoder = avcodec_find_decoder(codec_id);
        if (!decoder) {
            log_to_file("CHelper", "WRN", "subtitle extract: no decoder for stream %d (codec_id=%d)", idx, codec_id);
            continue;
        }

        AVCodecContext *dc = avcodec_alloc_context3(decoder);
        if (!dc) continue;

        avcodec_parameters_to_context(dc, cp);
        ret = avcodec_open2(dc, decoder, NULL);
        if (ret < 0) {
            log_to_file("CHelper", "WRN", "subtitle extract: avcodec_open2 failed for stream %d (ret=%d)", idx, ret);
            avcodec_free_context(&dc);
            continue;
        }

        FILE *f = fopen(outputPaths[i], "w");
        if (!f) {
            avcodec_free_context(&dc);
            continue;
        }
        fprintf(f, "WEBVTT\n\n");

        decCtxs[i] = dc;
        outFiles[i] = f;

        AVStream *st = subCtx->streams[idx];
        timeBases[i] = read_stream_rational(st, offsetof(AVStream, time_base));
        if (timeBases[i].den == 0) { timeBases[i].num = 1; timeBases[i].den = 1000; }

        activeCount++;
        log_to_file("CHelper", "DBG", "subtitle extract: stream %d ready (codec_id=%d)", idx, codec_id);
    }

    if (activeCount == 0) {
        log_to_file("CHelper", "WRN", "subtitle extract: no streams could be initialized");
        avformat_close_input(&subCtx);
        return -1;
    }

    // Single-pass read loop: dispatch packets to the correct decoder
    AVPacket *pkt = av_packet_alloc();
    AVSubtitle sub;
    int gotSub = 0;

    while (av_read_frame(subCtx, pkt) >= 0) {
        // Find which of our subtitle streams this packet belongs to
        int slotIdx = -1;
        for (int i = 0; i < streamCount; i++) {
            if (pkt->stream_index == streamIndices[i] && decCtxs[i] && outFiles[i]) {
                slotIdx = i;
                break;
            }
        }
        if (slotIdx < 0) {
            av_packet_unref(pkt);
            continue;
        }

        ret = avcodec_decode_subtitle2(decCtxs[slotIdx], &sub, &gotSub, pkt);
        if (ret < 0 || !gotSub) {
            av_packet_unref(pkt);
            continue;
        }

        int64_t pts_ms = 0;
        if (pkt->pts != AV_NOPTS_VALUE) {
            pts_ms = av_rescale_q(pkt->pts, timeBases[slotIdx], (AVRational){1, 1000});
        }
        int64_t start_ms = pts_ms + sub.start_display_time;
        int64_t end_ms   = pts_ms + sub.end_display_time;
        if (end_ms <= start_ms) end_ms = start_ms + 5000;

        for (unsigned r = 0; r < sub.num_rects; r++) {
            AVSubtitleRect *rect = sub.rects[r];
            const char *text = NULL;

            if (rect->type == SUBTITLE_TEXT && rect->text) {
                text = rect->text;
            } else if (rect->type == SUBTITLE_ASS && rect->ass) {
                text = rect->ass;
                int commas = 0;
                while (*text && commas < 8) {
                    if (*text == ',') commas++;
                    text++;
                }
            }

            if (text && text[0] != '\0') {
                int cc = cueCounts[slotIdx];
                char startTS[16], endTS[16];
                format_vtt_timestamp(startTS, sizeof(startTS), start_ms);
                format_vtt_timestamp(endTS, sizeof(endTS), end_ms);

                fprintf(outFiles[slotIdx], "%d\n%s --> %s\n", cc + 1, startTS, endTS);

                const char *p = text;
                int inOverride = 0;
                while (*p) {
                    if (*p == '{' && *(p+1) == '\\') { inOverride = 1; p++; continue; }
                    if (inOverride) { if (*p == '}') inOverride = 0; p++; continue; }
                    if (*p == '\\' && (*(p+1) == 'N' || *(p+1) == 'n')) { fprintf(outFiles[slotIdx], "\n"); p += 2; continue; }
                    fputc(*p, outFiles[slotIdx]);
                    p++;
                }
                fprintf(outFiles[slotIdx], "\n\n");
                cueCounts[slotIdx] = cc + 1;
            }
        }

        avsubtitle_free(&sub);
        av_packet_unref(pkt);
    }

    av_packet_free(&pkt);

    // Cleanup
    int totalCues = 0;
    for (int i = 0; i < streamCount; i++) {
        if (outFiles[i]) fclose(outFiles[i]);
        if (decCtxs[i]) avcodec_free_context(&decCtxs[i]);
        totalCues += cueCounts[i];
        if (cueCounts[i] > 0) {
            log_to_file("CHelper", "INF", "subtitle extract: stream %d → %d cues → %s",
                        streamIndices[i], cueCounts[i], outputPaths[i]);
        }
    }
    avformat_close_input(&subCtx);

    log_to_file("CHelper", "INF", "subtitle extract: %d total cues from %d streams", totalCues, activeCount);
    return 0;
    #undef MAX_SUB_STREAMS
}
#endif  // Legacy extraction function

// --- Diagnostics ---

void mks_debug_stream_layout(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx) {
        log_to_file("CLayout", "ERR", "ctx is NULL!");
        return;
    }

    detect_field_shifts(ctx);

    log_to_file("CLayout", "DBG", "stream_shift=%d cp_shift=%d",
                s_stream_shift, s_cp_shift);

    if (streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams) {
        log_to_file("CLayout", "ERR", "streamIndex %d out of range", streamIndex);
        return;
    }

    AVStream *s = ctx->streams[streamIndex];
    if (!s) {
        log_to_file("CLayout", "ERR", "stream[%d] is NULL", streamIndex);
        return;
    }

    AVCodecParameters *cp = get_stream_codecpar(s);
    log_to_file("CLayout", "DBG", "stream[%d] codecpar=%p", streamIndex, (void *)cp);
    if (cp) {
        int ct = read_cp_int(cp, offsetof(AVCodecParameters, codec_type));
        int ci = read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
        int w  = read_cp_int(cp, offsetof(AVCodecParameters, width));
        int h  = read_cp_int(cp, offsetof(AVCodecParameters, height));
        log_to_file("CLayout", "DBG", "codec_type=%d codec_id=%d %dx%d", ct, ci, w, h);
    }
}

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
#import <libavutil/log.h>
#import <libavutil/time.h>

#include "FFmpegStreamHelper.h"
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <pthread.h>

// --- File logging (writes to /tmp/mks-iptv-transmux.log) ---
//
// All log output goes to BOTH stderr (Xcode console) and the log file
// so the web-based log viewer sees everything in real time.
// Format matches TransmuxLog.swift: [HH:mm:ss.SSS] [LEVEL] [TAG] message

static FILE *s_log_file = NULL;
static pthread_mutex_t s_log_mutex = PTHREAD_MUTEX_INITIALIZER;

/// Format a timestamp matching TransmuxLog.swift: HH:mm:ss.SSS
/// Uses av_gettime() (microseconds since epoch) to avoid system <time.h>
/// which is unavailable inside the CFFmpegHelper Swift module.
/// NOTE: This produces UTC time. TransmuxLog.swift produces local time.
/// For timezone-correct timestamps, the log viewer can normalize.
static void format_timestamp(char *buf, size_t bufsize) {
    int64_t us = av_gettime();
    int64_t total_secs = us / 1000000;
    int ms = (int)((us % 1000000) / 1000);
    int64_t day_secs = total_secs % 86400;
    int h = (int)(day_secs / 3600);
    int m = (int)((day_secs % 3600) / 60);
    int s = (int)(day_secs % 60);
    snprintf(buf, bufsize, "%02d:%02d:%02d.%03d", h, m, s, ms);
}

/// Write a log entry to both stderr and the log file.
static void log_to_file(const char *tag, const char *level, const char *fmt, ...) {
    char msg[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    char ts[16];
    format_timestamp(ts, sizeof(ts));

    // stderr (Xcode console)
    fprintf(stderr, "[%s] [%s] [%s] %s\n", ts, level, tag, msg);

    // Log file (thread-safe, append mode)
    pthread_mutex_lock(&s_log_mutex);
    if (s_log_file) {
        fprintf(s_log_file, "[%s] [%s] [%s] %s\n", ts, level, tag, msg);
        fflush(s_log_file);
    }
    pthread_mutex_unlock(&s_log_mutex);
}

/// FFmpeg av_log callback — routes FFmpeg internal messages to the log file.
/// Captures critical messages like "non monotonically increasing dts" from the mp4 muxer.
static void ffmpeg_log_callback(void *avcl, int level, const char *fmt, va_list vl) {
    if (level > av_log_get_level()) return;

    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, vl);

    // Strip trailing whitespace/newlines (FFmpeg appends them)
    size_t len = strlen(buf);
    while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r' || buf[len-1] == ' ')) {
        buf[--len] = '\0';
    }
    if (len == 0) return;

    const char *lvl;
    if (level <= AV_LOG_ERROR)        lvl = "ERR";
    else if (level <= AV_LOG_WARNING) lvl = "WRN";
    else if (level <= AV_LOG_INFO)    lvl = "INF";
    else                              lvl = "DBG";

    log_to_file("FFmpeg", lvl, "%s", buf);
}

void mks_log_init(const char *logFilePath) {
    pthread_mutex_lock(&s_log_mutex);
    if (s_log_file) {
        fclose(s_log_file);
        s_log_file = NULL;
    }
    if (logFilePath) {
        s_log_file = fopen(logFilePath, "a");
        if (!s_log_file) {
            fprintf(stderr, "[FFmpegHelper] WARNING: failed to open log file: %s\n", logFilePath);
        }
    }
    pthread_mutex_unlock(&s_log_mutex);

    // Route FFmpeg internal logging through our callback
    av_log_set_level(AV_LOG_INFO);
    av_log_set_callback(ffmpeg_log_callback);
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

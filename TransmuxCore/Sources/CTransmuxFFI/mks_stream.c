// mks_stream.c — Stream inspection, format helpers, metadata access

#define MKS_LOG_TAG "mks_stream"

#include "include/mks_stream.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/dict.h>
#include <libavutil/mem.h>
#include <string.h>

// ============================================================================
// Stream inspection
// ============================================================================

MKS_HOT
int mks_stream_get_codec_type(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return AVMEDIA_TYPE_UNKNOWN;
    return mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_type));
}

MKS_HOT
int mks_stream_get_codec_id(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return AV_CODEC_ID_NONE;
    return mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
}

int mks_stream_get_disposition(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return 0;

    mks_layout_detect(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) return 0;

    return mks_layout_read_stream_int(s, offsetof(AVStream, disposition));
}

void mks_stream_get_time_base(const void *fmtCtx, int streamIndex,
                               int *num, int *den) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams) {
        *num = 0; *den = 1;
        return;
    }

    mks_layout_detect(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) { *num = 0; *den = 1; return; }

    AVRational tb = mks_layout_read_stream_rational(s, offsetof(AVStream, time_base));
    *num = tb.num;
    *den = tb.den;
}

int mks_stream_get_width(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, width));
}

int mks_stream_get_height(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, height));
}

void mks_stream_get_frame_rate(const void *fmtCtx, int streamIndex, int *num, int *den) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams) {
        *num = 0; *den = 1;
        return;
    }

    mks_layout_detect(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) { *num = 0; *den = 1; return; }

    AVRational fr = mks_layout_read_stream_rational(s, offsetof(AVStream, avg_frame_rate));
    *num = fr.num;
    *den = fr.den;
}

int mks_format_get_nb_streams(const void *fmtCtx) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx) return 0;
    return (int)ctx->nb_streams;
}

// ============================================================================
// Output stream setup
// ============================================================================

MKSError mks_stream_copy_codecpar(void *dstStream,
                                   const void *srcFmtCtx,
                                   int srcStreamIndex) {
    AVStream *dst = (AVStream *)dstStream;
    const AVFormatContext *ctx = (const AVFormatContext *)srcFmtCtx;

    AVCodecParameters *srcPar = mks_layout_get_codecpar(ctx, srcStreamIndex);
    AVCodecParameters *dstPar = mks_layout_get_stream_codecpar(dst);

    if (!srcPar || !dstPar) {
        MKS_LOGE("copy_codecpar: src=%p dst=%p", (void *)srcPar, (void *)dstPar);
        return MKS_ERROR_INVALID_PARAM;
    }

    int src_ct = mks_layout_read_cp_int(srcPar, offsetof(AVCodecParameters, codec_type));
    int src_ci = mks_layout_read_cp_int(srcPar, offsetof(AVCodecParameters, codec_id));
    MKS_LOGD("copy_codecpar: src_type=%d src_id=%d", src_ct, src_ci);

    // Method 1: avcodec_parameters_copy
    int ret = avcodec_parameters_copy(dstPar, srcPar);
    if (ret >= 0) {
        int dst_ct = mks_layout_read_cp_int(dstPar, offsetof(AVCodecParameters, codec_type));
        int dst_ci = mks_layout_read_cp_int(dstPar, offsetof(AVCodecParameters, codec_id));

        if (dst_ct >= 0 && dst_ct <= 5 && dst_ci != 0) {
            MKS_LOGI("avcodec_parameters_copy OK: type=%d id=%d", dst_ct, dst_ci);
            mks_layout_write_cp_uint32(dstPar, offsetof(AVCodecParameters, codec_tag), 0);
            return MKS_OK;
        }
        MKS_LOGW("avcodec_parameters_copy produced bad result, trying memcpy fallback");
    }

    // Method 2: Raw memcpy fallback
    size_t copy_size = sizeof(AVCodecParameters);
    MKS_LOGI("memcpy fallback: %zu bytes src=%p -> dst=%p",
             copy_size, (void *)srcPar, (void *)dstPar);

    void *src_extradata = mks_layout_read_cp_ptr(srcPar, offsetof(AVCodecParameters, extradata));
    int src_extradata_size = mks_layout_read_cp_int(srcPar, offsetof(AVCodecParameters, extradata_size));

    void *old_dst_extradata = mks_layout_read_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata));
    if (old_dst_extradata) {
        av_free(old_dst_extradata);
    }

    memcpy(dstPar, srcPar, copy_size);

    if (src_extradata && src_extradata_size > 0) {
        void *new_extradata = av_malloc(src_extradata_size + AV_INPUT_BUFFER_PADDING_SIZE);
        if (new_extradata) {
            memcpy(new_extradata, src_extradata, src_extradata_size);
            memset((uint8_t *)new_extradata + src_extradata_size, 0,
                   AV_INPUT_BUFFER_PADDING_SIZE);
            mks_layout_write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), new_extradata);
        } else {
            mks_layout_write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), NULL);
            mks_layout_write_cp_int(dstPar, offsetof(AVCodecParameters, extradata_size), 0);
        }
    } else {
        mks_layout_write_cp_ptr(dstPar, offsetof(AVCodecParameters, extradata), NULL);
        mks_layout_write_cp_int(dstPar, offsetof(AVCodecParameters, extradata_size), 0);
    }

    mks_layout_write_cp_uint32(dstPar, offsetof(AVCodecParameters, codec_tag), 0);

    int dst_ct2 = mks_layout_read_cp_int(dstPar, offsetof(AVCodecParameters, codec_type));
    int dst_ci2 = mks_layout_read_cp_int(dstPar, offsetof(AVCodecParameters, codec_id));
    MKS_LOGI("memcpy done: type=%d id=%d", dst_ct2, dst_ci2);

    return MKS_OK;
}

void mks_stream_set_frame_size(void *fmtCtx, int streamIndex, int frameSize) {
    AVCodecParameters *cp = mks_layout_get_codecpar((AVFormatContext *)fmtCtx, streamIndex);
    if (cp) {
        mks_layout_write_cp_int(cp, offsetof(AVCodecParameters, frame_size), frameSize);
        MKS_LOGI("set frame_size=%d on stream %d", frameSize, streamIndex);
    }
}

int mks_stream_has_extradata(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    void *extradata = mks_layout_read_cp_ptr(cp, offsetof(AVCodecParameters, extradata));
    int extradata_size = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, extradata_size));
    return (extradata != NULL && extradata_size > 0) ? 1 : 0;
}

void mks_stream_clear_codec_tag(void *stream) {
    AVStream *s = (AVStream *)stream;
    AVCodecParameters *cp = mks_layout_get_stream_codecpar(s);
    if (cp)
        mks_layout_write_cp_uint32(cp, offsetof(AVCodecParameters, codec_tag), 0);
}

// ============================================================================
// Stream metadata
// ============================================================================

static int read_stream_metadata(const AVFormatContext *ctx, int streamIndex,
                                 const char *key, char *buf, int bufSize) {
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams || !buf || bufSize <= 0)
        return -1;

    mks_layout_detect(ctx);

    AVStream *s = ctx->streams[streamIndex];
    if (!s) return -1;

    AVDictionary *meta = (AVDictionary *)mks_layout_read_stream_ptr(s, offsetof(AVStream, metadata));
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
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;

    int nb_channels = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, ch_layout) + 4);
    if (nb_channels > 0 && nb_channels < 64) return nb_channels;
    return 0;
}

int mks_stream_get_sample_rate(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, sample_rate));
}

int mks_stream_get_subtitle_codec_id(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams)
        return 0;

    int codec_type = mks_stream_get_codec_type(fmtCtx, streamIndex);
    if (codec_type != AVMEDIA_TYPE_SUBTITLE) return 0;

    return mks_stream_get_codec_id(fmtCtx, streamIndex);
}

int64_t mks_stream_get_bit_rate(const void *fmtCtx, int streamIndex) {
    AVCodecParameters *cp = mks_layout_get_codecpar((const AVFormatContext *)fmtCtx, streamIndex);
    if (!cp) return 0;
    return mks_layout_read_cp_int64(cp, offsetof(AVCodecParameters, bit_rate));
}

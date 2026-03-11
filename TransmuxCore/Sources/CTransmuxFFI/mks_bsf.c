// mks_bsf.c — Bitstream filter management
//
// Wraps FFmpeg AVBSFContext lifecycle for:
//   - aac_adtstoasc: ADTS -> ASC conversion required for fMP4 AAC output
//   - dts2pts: PTS reordering fix for IPTV streams (FFmpeg 7+, planned)
//
// The aac_adtstoasc filter is a 1:1 filter: one packet in, one packet out.
// It converts AAC ADTS (Audio Data Transport Stream) headers to AudioSpecificConfig
// format required by MP4/fMP4 containers.
//
// Thread safety: BSF instances are NOT thread-safe.
// Each BSF must be used from a single thread only.

#define MKS_LOG_TAG "mks_bsf"

#include "include/mks_bsf.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libavcodec/bsf.h>

// ============================================================================
// aac_adtstoasc BSF
// ============================================================================

void *mks_bsf_create_aac_adtstoasc(const void *fmtCtx, int audioStreamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || audioStreamIndex < 0 || (unsigned)audioStreamIndex >= ctx->nb_streams)
        return NULL;

    mks_layout_detect(ctx);

    const AVBitStreamFilter *filter = av_bsf_get_by_name("aac_adtstoasc");
    if (!filter) {
        MKS_LOGE("aac_adtstoasc BSF not found in this FFmpeg build");
        return NULL;
    }

    AVBSFContext *bsfCtx = NULL;
    int ret = av_bsf_alloc(filter, &bsfCtx);
    if (ret < 0 || !bsfCtx) {
        MKS_LOGE("av_bsf_alloc failed: %d", ret);
        return NULL;
    }

    AVCodecParameters *srcPar = mks_layout_get_codecpar(ctx, audioStreamIndex);
    if (!srcPar) {
        MKS_LOGE("cannot get codecpar for audio stream %d", audioStreamIndex);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    ret = avcodec_parameters_copy(bsfCtx->par_in, srcPar);
    if (ret < 0) {
        MKS_LOGE("avcodec_parameters_copy to BSF par_in failed: %d", ret);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    AVStream *s = ctx->streams[audioStreamIndex];
    bsfCtx->time_base_in = mks_layout_read_stream_rational(s,
                                                             offsetof(AVStream, time_base));

    ret = av_bsf_init(bsfCtx);
    if (ret < 0) {
        MKS_LOGE("av_bsf_init failed: %d", ret);
        av_bsf_free(&bsfCtx);
        return NULL;
    }

    MKS_LOGI("aac_adtstoasc BSF created for stream %d", audioStreamIndex);
    return bsfCtx;
}

MKS_HOT
MKSError mks_bsf_filter_packet(void *bsfCtx, void *pkt) {
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    AVPacket *p = (AVPacket *)pkt;
    if (!ctx || !p) return MKS_ERROR_INVALID_PARAM;

    int ret = av_bsf_send_packet(ctx, p);
    if (ret < 0) {
        MKS_LOGW("av_bsf_send_packet failed: %d", ret);
        return mks_error_from_averror(ret);
    }

    ret = av_bsf_receive_packet(ctx, p);
    if (ret < 0) {
        // EAGAIN is expected if filter needs more data (rare for aac_adtstoasc)
        if (ret != AVERROR(EAGAIN)) {
            MKS_LOGW("av_bsf_receive_packet failed: %d", ret);
        }
        return mks_error_from_averror(ret);
    }

    return MKS_OK;
}

void mks_bsf_free(void *bsfCtx) {
    if (!bsfCtx) return;
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    av_bsf_free(&ctx);
    MKS_LOGI("BSF freed");
}

void mks_bsf_flush(void *bsfCtx) {
    AVBSFContext *ctx = (AVBSFContext *)bsfCtx;
    if (!ctx) return;

    // av_bsf_flush resets the BSF to its initial state.
    // DO NOT use av_bsf_send_packet(NULL) — that puts BSF into permanent EOF mode.
    av_bsf_flush(ctx);

    MKS_LOGI("BSF flushed after seek");
}

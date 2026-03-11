// mks_debug.c — Runtime diagnostics
//
// Dumps stream layout information including shift detection results,
// codec parameters, and dimensions. Useful for verifying that the
// runtime layout detection in mks_layout.c is working correctly.

#define MKS_LOG_TAG "mks_debug"

#include "include/CTransmuxFFI.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

void mks_debug_stream_layout(const void *fmtCtx, int streamIndex) {
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx) {
        MKS_LOGE("ctx is NULL");
        return;
    }

    mks_layout_detect(ctx);

    MKS_LOGD("stream_shift=%d cp_shift=%d",
             mks_layout_get_stream_shift(), mks_layout_get_cp_shift());

    if (streamIndex < 0 || (unsigned)streamIndex >= ctx->nb_streams) {
        MKS_LOGE("streamIndex %d out of range (nb_streams=%u)",
                 streamIndex, ctx->nb_streams);
        return;
    }

    AVStream *s = ctx->streams[streamIndex];
    if (!s) {
        MKS_LOGE("stream[%d] is NULL", streamIndex);
        return;
    }

    AVCodecParameters *cp = mks_layout_get_stream_codecpar(s);
    MKS_LOGD("stream[%d] codecpar=%p", streamIndex, (void *)cp);

    if (cp) {
        int ct = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_type));
        int ci = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
        int w  = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, width));
        int h  = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, height));
        MKS_LOGI("stream[%d] codec_type=%d codec_id=%d %dx%d",
                 streamIndex, ct, ci, w, h);
    }
}

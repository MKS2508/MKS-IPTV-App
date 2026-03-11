// mks_packet.c — Packet field access, timestamp operations, seek support
//
// Provides safe opaque-pointer accessors for AVPacket fields and
// layout-corrected timestamp rescaling between streams.
//
// All public functions validate inputs and handle NULL gracefully.

#define MKS_LOG_TAG "mks_packet"

#include "include/mks_packet.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libavcodec/packet.h>

// ============================================================================
// Packet field access
// ============================================================================

MKS_HOT
int mks_packet_get_stream_index(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return -1;
    return p->stream_index;
}

MKS_HOT
void mks_packet_set_stream_index(void *pkt, int index) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->stream_index = index;
}

void mks_packet_clear_pos(void *pkt) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->pos = -1;
}

MKS_HOT
int mks_packet_is_keyframe(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return 0;
    return (p->flags & AV_PKT_FLAG_KEY) ? 1 : 0;
}

// ============================================================================
// Timestamp operations
// ============================================================================

MKS_HOT
void mks_packet_rescale_ts(void *pkt,
                            const void *srcFmtCtx, int srcStreamIndex,
                            const void *dstFmtCtx, int dstStreamIndex) {
    AVPacket *p = (AVPacket *)pkt;
    const AVFormatContext *src = (const AVFormatContext *)srcFmtCtx;
    const AVFormatContext *dst = (const AVFormatContext *)dstFmtCtx;
    if (!p || !src || !dst) return;
    if (srcStreamIndex < 0 || (unsigned)srcStreamIndex >= src->nb_streams) return;
    if (dstStreamIndex < 0 || (unsigned)dstStreamIndex >= dst->nb_streams) return;

    mks_layout_detect(src);

    AVStream *srcStream = src->streams[srcStreamIndex];
    AVStream *dstStream = dst->streams[dstStreamIndex];
    if (!srcStream || !dstStream) return;

    AVRational srcTB = mks_layout_read_stream_rational(srcStream,
                                                        offsetof(AVStream, time_base));
    AVRational dstTB = mks_layout_read_stream_rational(dstStream,
                                                        offsetof(AVStream, time_base));

    av_packet_rescale_ts(p, srcTB, dstTB);
}

MKS_HOT
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

MKS_HOT
int64_t mks_packet_get_dts(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return AV_NOPTS_VALUE;
    return p->dts;
}

MKS_HOT
int64_t mks_packet_get_pts(const void *pkt) {
    const AVPacket *p = (const AVPacket *)pkt;
    if (!p) return AV_NOPTS_VALUE;
    return p->pts;
}

void mks_packet_set_dts(void *pkt, int64_t dts) {
    AVPacket *p = (AVPacket *)pkt;
    if (p) p->dts = dts;
}

// ============================================================================
// Seek support
// ============================================================================

void mks_format_flush_input(void *fmtCtx) {
    AVFormatContext *ctx = (AVFormatContext *)fmtCtx;
    if (!ctx) return;

    int ret = avformat_flush(ctx);
    MKS_LOGD("avformat_flush returned %d", ret);
}

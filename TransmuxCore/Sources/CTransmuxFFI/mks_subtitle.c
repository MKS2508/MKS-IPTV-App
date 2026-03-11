// mks_subtitle.c — In-band subtitle collector (fed during remux loop)
//
// Collects subtitle packets during the remux loop and writes WebVTT files.
// Uses the SAME open connection as the remux — no extra HTTP connections.
// This is critical for IPTV servers that block concurrent connections.
//
// Supported subtitle formats (decoded to text, then written as WebVTT):
//   - SubRip (SRT)           AV_CODEC_ID_SUBRIP
//   - ASS/SSA                AV_CODEC_ID_ASS
//   - WebVTT                 AV_CODEC_ID_WEBVTT
//   - MOV Text               AV_CODEC_ID_MOV_TEXT
//   - MicroDVD               AV_CODEC_ID_MICRODVD
//   - SubStation Alpha       AV_CODEC_ID_SSA
//   - HDMV PGS (bitmap)      AV_CODEC_ID_HDMV_PGS_SUBTITLE (skipped)
//
// Thread safety: A single MKSSubtitleCollector is NOT thread-safe.
// Feed packets from the remux loop thread only.

#define MKS_LOG_TAG "mks_subtitle"

#include "include/mks_subtitle.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libavutil/mathematics.h>
#include <stdio.h>
#include <stdlib.h>

#define MKS_MAX_SUB_STREAMS 16

struct MKSSubtitleCollector {
    int streamCount;
    int streamIndices[MKS_MAX_SUB_STREAMS];
    AVCodecContext *decoders[MKS_MAX_SUB_STREAMS];
    FILE *files[MKS_MAX_SUB_STREAMS];
    AVRational timeBases[MKS_MAX_SUB_STREAMS];
    int cueCounts[MKS_MAX_SUB_STREAMS];
    int activeCount;
};

// ============================================================================
// Internal: VTT timestamp formatting (HH:MM:SS.mmm)
// ============================================================================

static void format_vtt_timestamp(char *buf, size_t bufsize, int64_t ms) {
    if (ms < 0) ms = 0;
    int h  = (int)(ms / 3600000);
    int m  = (int)((ms % 3600000) / 60000);
    int s  = (int)((ms % 60000) / 1000);
    int mm = (int)(ms % 1000);
    snprintf(buf, bufsize, "%02d:%02d:%02d.%03d", h, m, s, mm);
}

// ============================================================================
// Lifecycle
// ============================================================================

MKSSubtitleCollector *mks_subtitle_collector_create(
    const void *fmtCtx,
    int streamCount,
    const int *streamIndices,
    const char *const *outputPaths)
{
    const AVFormatContext *ctx = (const AVFormatContext *)fmtCtx;
    if (!ctx || streamCount <= 0 || streamCount > MKS_MAX_SUB_STREAMS ||
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
            MKS_LOGW("stream %d out of range (nb_streams=%u)", idx, ctx->nb_streams);
            continue;
        }

        AVCodecParameters *cp = mks_layout_get_codecpar(ctx, idx);
        if (!cp) continue;

        int codec_id = mks_layout_read_cp_int(cp, offsetof(AVCodecParameters, codec_id));
        const AVCodec *decoder = avcodec_find_decoder(codec_id);
        if (!decoder) {
            MKS_LOGW("no decoder for stream %d (codec_id=%d)", idx, codec_id);
            continue;
        }

        AVCodecContext *dc = avcodec_alloc_context3(decoder);
        if (!dc) continue;

        avcodec_parameters_to_context(dc, cp);
        int ret = avcodec_open2(dc, decoder, NULL);
        if (ret < 0) {
            MKS_LOGW("avcodec_open2 failed for stream %d: %d", idx, ret);
            avcodec_free_context(&dc);
            continue;
        }

        FILE *f = fopen(outputPaths[i], "w");
        if (!f) {
            MKS_LOGW("cannot open output file for stream %d", idx);
            avcodec_free_context(&dc);
            continue;
        }
        fprintf(f, "WEBVTT\n\n");

        c->decoders[i] = dc;
        c->files[i] = f;

        AVStream *st = ctx->streams[idx];
        c->timeBases[i] = mks_layout_read_stream_rational(st,
                                                            offsetof(AVStream, time_base));
        if (c->timeBases[i].den == 0) {
            c->timeBases[i].num = 1;
            c->timeBases[i].den = 1000;
        }

        c->activeCount++;
        MKS_LOGI("stream %d ready (codec_id=%d, tb=%d/%d)",
                 idx, codec_id, c->timeBases[i].num, c->timeBases[i].den);
    }

    if (c->activeCount == 0) {
        MKS_LOGW("no decodable subtitle streams found");
        free(c);
        return NULL;
    }

    MKS_LOGI("created with %d/%d active streams", c->activeCount, streamCount);
    return c;
}

// ============================================================================
// Processing
// ============================================================================

MKS_HOT
void mks_subtitle_collector_feed(MKSSubtitleCollector *collector, const void *rawPkt) {
    if (!collector || !rawPkt) return;
    const AVPacket *pkt = (const AVPacket *)rawPkt;

    // Find the slot for this packet's stream index
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
                                        (const AVPacket *)rawPkt);
    if (ret < 0 || !gotSub) return;

    // Calculate start/end timestamps in milliseconds
    int64_t pts_ms = 0;
    if (pkt->pts != AV_NOPTS_VALUE) {
        pts_ms = av_rescale_q(pkt->pts, collector->timeBases[slot],
                               (AVRational){1, 1000});
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
            // ASS format: skip 8 comma-separated fields to get the text content
            text = rect->ass;
            int commas = 0;
            while (*text && commas < 8) {
                if (*text == ',') commas++;
                text++;
            }
        }

        if (text && text[0] != '\0') {
            int cc = collector->cueCounts[slot];
            char startTS[16], endTS[16];
            format_vtt_timestamp(startTS, sizeof(startTS), start_ms);
            format_vtt_timestamp(endTS, sizeof(endTS), end_ms);
            fprintf(f, "%d\n%s --> %s\n", cc + 1, startTS, endTS);

            // Strip ASS override tags ({\...}) and convert \N to newlines
            const char *p = text;
            int inOverride = 0;
            while (*p) {
                if (*p == '{' && *(p + 1) == '\\') {
                    inOverride = 1;
                    p++;
                    continue;
                }
                if (inOverride) {
                    if (*p == '}') inOverride = 0;
                    p++;
                    continue;
                }
                if (*p == '\\' && (*(p + 1) == 'N' || *(p + 1) == 'n')) {
                    fprintf(f, "\n");
                    p += 2;
                    continue;
                }
                fputc(*p, f);
                p++;
            }
            fprintf(f, "\n\n");
            fflush(f);
            collector->cueCounts[slot] = cc + 1;
        }
    }
    avsubtitle_free(&sub);
}

// ============================================================================
// Finalization
// ============================================================================

void mks_subtitle_collector_finish(MKSSubtitleCollector *collector, int *cueCounts) {
    if (!collector) return;

    int totalCues = 0;
    for (int i = 0; i < collector->streamCount; i++) {
        if (collector->files[i]) fclose(collector->files[i]);
        if (collector->decoders[i]) avcodec_free_context(&collector->decoders[i]);
        if (cueCounts) cueCounts[i] = collector->cueCounts[i];
        totalCues += collector->cueCounts[i];
        if (collector->cueCounts[i] > 0) {
            MKS_LOGI("stream %d -> %d cues",
                     collector->streamIndices[i], collector->cueCounts[i]);
        }
    }
    MKS_LOGI("finished: %d total cues from %d streams",
             totalCues, collector->activeCount);
    free(collector);
}

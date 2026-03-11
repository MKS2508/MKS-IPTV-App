// mks_video.c — Video transcoder (VP9/AV1/MPEG-2 -> H.264/H.265 via VideoToolbox)
//
// Opaque handle wrapping a complete FFmpeg decode -> convert -> VT encode pipeline.
//
// Architecture (AD-03, AD-04):
//   AVPacket (VP9/AV1/MPEG-2/etc)
//     → avcodec_send_packet (FFmpeg software decoder)
//     → avcodec_receive_frame (decoded YUV420P/YUV422P)
//     → sws_scale (colorspace convert to NV12)
//     → avcodec_send_frame (VideoToolbox encoder)
//     → avcodec_receive_packet (H.264/H.265 AVPacket)
//
// Memory (AD-09): 2 pre-allocated AVFrames (~6-8MB at 1080p).
// The pipeline is synchronous: decode -> convert -> encode.
// Only 2 frames are needed simultaneously.
//
// Bitrate strategy (AD-05): VBR with qmin/qmax.
// CRF is IGNORED by VideoToolbox hardware encoder.
//
// Encoder options (AD-06): spatialaq=1 always, power_efficient=1 on battery.

#define MKS_LOG_TAG "mks_video"

#include "include/mks_video.h"
#include "include/mks_stream.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <stdlib.h>
#include <string.h>

// ============================================================================
// Codec ID constants (avoid including full libavcodec for just these)
// ============================================================================

#ifndef AV_CODEC_ID_H264
#define AV_CODEC_ID_H264 27
#endif
#ifndef AV_CODEC_ID_HEVC
#define AV_CODEC_ID_HEVC 173
#endif
#ifndef AV_CODEC_ID_VP9
#define AV_CODEC_ID_VP9 167
#endif
#ifndef AV_CODEC_ID_AV1
#define AV_CODEC_ID_AV1 225
#endif
#ifndef AV_CODEC_ID_MPEG2VIDEO
#define AV_CODEC_ID_MPEG2VIDEO 2
#endif
#ifndef AV_CODEC_ID_MPEG1VIDEO
#define AV_CODEC_ID_MPEG1VIDEO 1
#endif

// ============================================================================
// Internal struct definition (opaque to consumers)
// ============================================================================

struct MKSVideoTranscoder {
    // Decoder (software)
    const AVCodec *decoder;
    AVCodecContext *decoderCtx;

    // Encoder (VideoToolbox)
    const AVCodec *encoder;
    AVCodecContext *encoderCtx;

    // Colorspace converter
    struct SwsContext *swsCtx;

    // Pre-allocated frames (AD-09: 2 frames max)
    AVFrame *decodedFrame;      // Output from decoder (YUV420P/etc)
    AVFrame *nv12Frame;         // Input to encoder (NV12)

    // Input stream info
    int inputWidth;
    int inputHeight;
    AVRational inputTimeBase;
    AVRational inputFrameRate;
    int64_t inputFirstPts;

    // Output stream info
    int outputCodecId;
    int outputWidth;
    int outputHeight;
    int targetBitrate;

    // PTS tracking
    int64_t nextPts;
    int64_t ptsOffset;          // For seek rebasing

    // Configuration
    MKSVideoConfig config;

    // Error context (SQLite pattern)
    int last_averror;

    // VT Error Recovery (AD-11)
    int vtErrorCount;          // Consecutive VT encoder errors
    int usingSwFallback;       // Currently using software encoder fallback
};

// ============================================================================
// Internal: calculate target bitrate from resolution (AD-05)
// ============================================================================

static int calculate_bitrate(int width, int height) {
    int pixels = width * height;

    if (pixels >= 3840 * 2160)       // 4K+
        return 20000000;             // 20 Mbps
    if (pixels >= 2560 * 1440)       // 1440p
        return 12000000;             // 12 Mbps
    if (pixels >= 1920 * 1080)       // 1080p
        return 8000000;              // 8 Mbps
    if (pixels >= 1280 * 720)        // 720p
        return 4000000;              // 4 Mbps
    return 2000000;                  // 2 Mbps for SD
}

// ============================================================================
// Internal: select output codec based on resolution (AD-10)
// ============================================================================

static int select_output_codec(int width, int height, int requestedCodec) {
    // Explicit request takes precedence
    if (requestedCodec == AV_CODEC_ID_H264 || requestedCodec == AV_CODEC_ID_HEVC)
        return requestedCodec;

    // Auto-select: H.265 for 4K+, H.264 otherwise
    int pixels = width * height;
    if (pixels >= 3840 * 2160)
        return AV_CODEC_ID_HEVC;

    return AV_CODEC_ID_H264;
}

// ============================================================================
// Internal: find VideoToolbox encoder by codec ID
// ============================================================================

static const AVCodec *find_vt_encoder(int codecId) {
    if (codecId == AV_CODEC_ID_H264)
        return avcodec_find_encoder_by_name("h264_videotoolbox");
    if (codecId == AV_CODEC_ID_HEVC)
        return avcodec_find_encoder_by_name("hevc_videotoolbox");
    return NULL;
}

// ============================================================================
// Internal: find software encoder by codec ID (fallback for VT errors)
// ============================================================================

static const AVCodec *find_sw_encoder(int codecId) {
    if (codecId == AV_CODEC_ID_H264)
        return avcodec_find_encoder_by_name("libx264");
    if (codecId == AV_CODEC_ID_HEVC)
        return avcodec_find_encoder_by_name("libx265");
    // Fallback to default encoder for codec
    return avcodec_find_encoder(codecId);
}

// ============================================================================
// Lifecycle: create
// ============================================================================

MKSVideoTranscoder *mks_video_transcoder_create(
    const void *inputFmtCtx,
    int inputStreamIndex,
    MKSVideoConfig config
) {
    const AVFormatContext *fmtCtx = (const AVFormatContext *)inputFmtCtx;
    if (!fmtCtx || inputStreamIndex < 0 || (unsigned)inputStreamIndex >= fmtCtx->nb_streams) {
        MKS_LOGE("invalid input parameters");
        return NULL;
    }

    // Allocate handle
    MKSVideoTranscoder *ctx = calloc(1, sizeof(MKSVideoTranscoder));
    if (!ctx) return NULL;

    ctx->config = config;
    ctx->inputFirstPts = AV_NOPTS_VALUE;

    // --- Read input stream parameters ---
    ctx->inputWidth = mks_stream_get_width(inputFmtCtx, inputStreamIndex);
    ctx->inputHeight = mks_stream_get_height(inputFmtCtx, inputStreamIndex);

    mks_stream_get_time_base(inputFmtCtx, inputStreamIndex,
                              &ctx->inputTimeBase.num, &ctx->inputTimeBase.den);

    // --- Find software decoder for input codec ---
    int inputCodecId = mks_stream_get_codec_id(inputFmtCtx, inputStreamIndex);
    ctx->decoder = avcodec_find_decoder(inputCodecId);
    if (!ctx->decoder) {
        MKS_LOGE("no decoder found for codec_id=%d", inputCodecId);
        free(ctx);
        return NULL;
    }

    // --- Create decoder context ---
    ctx->decoderCtx = avcodec_alloc_context3(ctx->decoder);
    if (!ctx->decoderCtx) {
        MKS_LOGE("failed to allocate decoder context");
        free(ctx);
        return NULL;
    }

    // Copy codec parameters from input stream
    AVStream *inStream = fmtCtx->streams[inputStreamIndex];
    int ret = avcodec_parameters_to_context(ctx->decoderCtx, inStream->codecpar);
    if (ret < 0) {
        MKS_LOGE("failed to copy decoder parameters: %d", ret);
        ctx->last_averror = ret;
        goto fail;
    }

    // Open decoder
    ret = avcodec_open2(ctx->decoderCtx, ctx->decoder, NULL);
    if (ret < 0) {
        MKS_LOGE("failed to open decoder: %d", ret);
        ctx->last_averror = ret;
        goto fail;
    }

    // --- Select output codec (AD-10) ---
    ctx->outputCodecId = select_output_codec(ctx->inputWidth, ctx->inputHeight,
                                              config.targetCodecId);
    ctx->outputWidth = ctx->inputWidth;
    ctx->outputHeight = ctx->inputHeight;

    // --- Calculate target bitrate (AD-05) ---
    ctx->targetBitrate = config.targetBitrate > 0
        ? config.targetBitrate
        : calculate_bitrate(ctx->outputWidth, ctx->outputHeight);

    // --- Find VideoToolbox encoder ---
    ctx->encoder = find_vt_encoder(ctx->outputCodecId);
    if (!ctx->encoder) {
        MKS_LOGE("VideoToolbox encoder not found for codec_id=%d", ctx->outputCodecId);
        goto fail;
    }

    MKS_LOGI("created: %dx%d -> %s @ %d bps",
             ctx->inputWidth, ctx->inputHeight,
             ctx->encoder->name, ctx->targetBitrate);

    // --- Pre-allocate frames (AD-09) ---
    ctx->decodedFrame = av_frame_alloc();
    ctx->nv12Frame = av_frame_alloc();
    if (!ctx->decodedFrame || !ctx->nv12Frame) {
        MKS_LOGE("failed to allocate frames");
        goto fail;
    }

    // Setup NV12 frame for encoder input
    ctx->nv12Frame->format = AV_PIX_FMT_NV12;
    ctx->nv12Frame->width = ctx->outputWidth;
    ctx->nv12Frame->height = ctx->outputHeight;
    ret = av_frame_get_buffer(ctx->nv12Frame, 0);
    if (ret < 0) {
        MKS_LOGE("failed to allocate NV12 frame buffer: %d", ret);
        ctx->last_averror = ret;
        goto fail;
    }

    return ctx;

fail:
    mks_video_transcoder_free(ctx);
    return NULL;
}

// ============================================================================
// Lifecycle: setup_output
// ============================================================================

MKSError mks_video_transcoder_setup_output(MKSVideoTranscoder *ctx, void *outputStream) {
    if (!ctx || !outputStream) return MKS_ERROR_INVALID_PARAM;

    AVStream *outStream = (AVStream *)outputStream;

    // --- Create encoder context ---
    ctx->encoderCtx = avcodec_alloc_context3(ctx->encoder);
    if (!ctx->encoderCtx) {
        MKS_LOGE("failed to allocate encoder context");
        return MKS_ERROR_NOMEM;
    }

    // --- Set encoder parameters ---
    ctx->encoderCtx->width = ctx->outputWidth;
    ctx->encoderCtx->height = ctx->outputHeight;
    ctx->encoderCtx->time_base = (AVRational){1, 90000};  // MPEG-TS standard
    ctx->encoderCtx->framerate = ctx->inputFrameRate.num > 0
        ? ctx->inputFrameRate
        : (AVRational){30, 1};
    ctx->encoderCtx->pix_fmt = AV_PIX_FMT_NV12;

    // --- Bitrate (AD-05): VBR with qmin/qmax ---
    ctx->encoderCtx->bit_rate = ctx->targetBitrate;
    ctx->encoderCtx->rc_max_rate = ctx->targetBitrate;
    ctx->encoderCtx->rc_min_rate = 0;
    ctx->encoderCtx->qmin = 20;   // Best quality floor
    ctx->encoderCtx->qmax = 40;   // Worst quality ceiling

    // --- B-frames ---
    ctx->encoderCtx->gop_size = 30;
    ctx->encoderCtx->max_b_frames = ctx->config.maxBFrames;

    // --- Profile (AD-10) ---
    if (ctx->config.profile > 0) {
        ctx->encoderCtx->profile = ctx->config.profile;
    }

    // --- VideoToolbox-specific options (AD-06) ---
    // Spatial adaptive quantization (always on)
    if (ctx->config.spatialAQ) {
        av_opt_set_int(ctx->encoderCtx->priv_data, "spatialaq", 1, 0);
    }

    // Power-efficient encoding (battery mode)
    if (ctx->config.powerEfficient) {
        av_opt_set_int(ctx->encoderCtx->priv_data, "power_efficient", 1, 0);
    }

    // Real-time mode for live content
    if (ctx->config.realtime) {
        av_opt_set_int(ctx->encoderCtx->priv_data, "realtime", 1, 0);
    }

    // Allow software fallback if VT fails
    av_opt_set_int(ctx->encoderCtx->priv_data, "allow_sw", 1, 0);

    // --- Open encoder ---
    int ret = avcodec_open2(ctx->encoderCtx, ctx->encoder, NULL);
    if (ret < 0) {
        MKS_LOGE("failed to open encoder: %d", ret);
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    // --- Copy encoder parameters to output stream ---
    ret = avcodec_parameters_from_context(outStream->codecpar, ctx->encoderCtx);
    if (ret < 0) {
        MKS_LOGE("failed to copy encoder parameters: %d", ret);
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    outStream->time_base = ctx->encoderCtx->time_base;

    MKS_LOGI("encoder ready: %s %dx%d @ %d bps",
             ctx->encoder->name, ctx->outputWidth, ctx->outputHeight, ctx->targetBitrate);

    return MKS_OK;
}

// ============================================================================
// Lifecycle: free
// ============================================================================

void mks_video_transcoder_free(MKSVideoTranscoder *ctx) {
    if (!ctx) return;

    av_frame_free(&ctx->nv12Frame);
    av_frame_free(&ctx->decodedFrame);
    sws_freeContext(ctx->swsCtx);
    avcodec_free_context(&ctx->encoderCtx);
    avcodec_free_context(&ctx->decoderCtx);

    free(ctx);
}

// ============================================================================
// Internal: create colorspace converter (lazy)
// ============================================================================

static int ensure_sws_context(MKSVideoTranscoder *ctx) {
    if (ctx->swsCtx) return 0;

    // Get source pixel format from decoded frame
    // We create it on first decode when we know the actual format
    enum AVPixelFormat srcFmt = ctx->decoderCtx->pix_fmt;
    if (srcFmt == AV_PIX_FMT_NONE) {
        MKS_LOGE("unknown source pixel format");
        return AVERROR(EINVAL);
    }

    ctx->swsCtx = sws_getContext(
        ctx->inputWidth, ctx->inputHeight, srcFmt,
        ctx->outputWidth, ctx->outputHeight, AV_PIX_FMT_NV12,
        SWS_BILINEAR, NULL, NULL, NULL
    );

    if (!ctx->swsCtx) {
        MKS_LOGE("failed to create sws context");
        return AVERROR(ENOMEM);
    }

    MKS_LOGI("sws context: %s -> NV12", av_get_pix_fmt_name(srcFmt));
    return 0;
}

// ============================================================================
// Internal: convert decoded frame to NV12
// ============================================================================

static int convert_to_nv12(MKSVideoTranscoder *ctx) {
    int ret = ensure_sws_context(ctx);
    if (ret < 0) return ret;

    ret = av_frame_make_writable(ctx->nv12Frame);
    if (ret < 0) {
        MKS_LOGE("failed to make NV12 frame writable: %d", ret);
        return ret;
    }

    // Perform colorspace conversion
    sws_scale(ctx->swsCtx,
              (const uint8_t * const *)ctx->decodedFrame->data,
              ctx->decodedFrame->linesize,
              0, ctx->inputHeight,
              ctx->nv12Frame->data,
              ctx->nv12Frame->linesize);

    // Copy timing info
    ctx->nv12Frame->pts = ctx->decodedFrame->pts;
    ctx->nv12Frame->pkt_dts = ctx->decodedFrame->pkt_dts;

    // HDR passthrough: copy frame properties (side data, HDR metadata, etc.)
    av_frame_copy_props(ctx->nv12Frame, ctx->decodedFrame);

    // Explicitly preserve color properties for HDR support
    ctx->nv12Frame->color_primaries = ctx->decodedFrame->color_primaries;
    ctx->nv12Frame->color_trc = ctx->decodedFrame->color_trc;
    ctx->nv12Frame->colorspace = ctx->decodedFrame->colorspace;
    ctx->nv12Frame->color_range = ctx->decodedFrame->color_range;

    return 0;
}

// ============================================================================
// Internal: drain decoded frames through encoder
// ============================================================================

static int drain_decoded_frame(MKSVideoTranscoder *ctx) {
    int ret;

    // Convert to NV12
    ret = convert_to_nv12(ctx);
    if (ret < 0) return ret;

    // Rebase PTS if needed (seek handling)
    if (ctx->ptsOffset != 0 && ctx->nv12Frame->pts != AV_NOPTS_VALUE) {
        ctx->nv12Frame->pts -= ctx->ptsOffset;
    }

    // Track first PTS for offset calculation
    if (ctx->inputFirstPts == AV_NOPTS_VALUE && ctx->nv12Frame->pts != AV_NOPTS_VALUE) {
        ctx->inputFirstPts = ctx->nv12Frame->pts;
    }

    // Rescale PTS to output time base
    if (ctx->nv12Frame->pts != AV_NOPTS_VALUE) {
        ctx->nv12Frame->pts = av_rescale_q(ctx->nv12Frame->pts,
                                            ctx->inputTimeBase,
                                            ctx->encoderCtx->time_base);
    }

    // Send to encoder with VT error recovery (AD-11)
send_frame:
    ret = avcodec_send_frame(ctx->encoderCtx, ctx->nv12Frame);
    if (ret < 0 && ret != AVERROR(EAGAIN)) {
        // Check for VT encoder failure (AVERROR_EXTERNAL)
        if (ret == AVERROR_EXTERNAL && !ctx->usingSwFallback) {
            ctx->vtErrorCount++;
            MKS_LOGW("VT encoder error (count=%d), attempting recovery", ctx->vtErrorCount);

            // After 3 consecutive VT errors, switch to software encoder
            if (ctx->vtErrorCount >= 3) {
                MKS_LOGW("VT encoder persistent failure, switching to software fallback");
                const AVCodec *swEncoder = find_sw_encoder(ctx->outputCodecId);
                if (swEncoder) {
                    // Save encoder configuration
                    int width = ctx->encoderCtx->width;
                    int height = ctx->encoderCtx->height;
                    AVRational tb = ctx->encoderCtx->time_base;
                    AVRational fr = ctx->encoderCtx->framerate;
                    int64_t bitrate = ctx->encoderCtx->bit_rate;

                    // Free VT encoder and create SW encoder
                    avcodec_free_context(&ctx->encoderCtx);
                    ctx->encoderCtx = avcodec_alloc_context3(swEncoder);
                    if (ctx->encoderCtx) {
                        ctx->encoderCtx->width = width;
                        ctx->encoderCtx->height = height;
                        ctx->encoderCtx->time_base = tb;
                        ctx->encoderCtx->framerate = fr;
                        ctx->encoderCtx->pix_fmt = AV_PIX_FMT_NV12;
                        ctx->encoderCtx->bit_rate = bitrate;

                        int openRet = avcodec_open2(ctx->encoderCtx, swEncoder, NULL);
                        if (openRet >= 0) {
                            ctx->usingSwFallback = 1;
                            ctx->vtErrorCount = 0;
                            MKS_LOGI("Successfully switched to software encoder: %s", swEncoder->name);
                            goto send_frame;  // Retry with SW encoder
                        } else {
                            MKS_LOGE("Failed to open software encoder: %d", openRet);
                        }
                    }
                }
            }
        }
        MKS_LOGE("avcodec_send_frame failed: %d", ret);
        return ret;
    }

    // Reset error count on successful encode
    if (ret >= 0) {
        ctx->vtErrorCount = 0;
    }

    return 0;
}

// ============================================================================
// Processing: send
// ============================================================================

MKSError mks_video_transcoder_send(MKSVideoTranscoder *ctx, const void *inputPacket) {
    if (!ctx || !inputPacket) return MKS_ERROR_INVALID_PARAM;

    const AVPacket *pkt = (const AVPacket *)inputPacket;
    int ret;

    // Send packet to decoder
    ret = avcodec_send_packet(ctx->decoderCtx, pkt);
    if (ret < 0) {
        MKS_LOGE("avcodec_send_packet failed: %d", ret);
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    // Drain all decoded frames through converter + encoder
    while (1) {
        ret = avcodec_receive_frame(ctx->decoderCtx, ctx->decodedFrame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            break;
        }
        if (ret < 0) {
            MKS_LOGE("avcodec_receive_frame failed: %d", ret);
            ctx->last_averror = ret;
            return mks_error_from_averror(ret);
        }

        ret = drain_decoded_frame(ctx);
        if (ret < 0) {
            ctx->last_averror = ret;
            return mks_error_from_averror(ret);
        }
    }

    return MKS_OK;
}

// ============================================================================
// Processing: receive
// ============================================================================

MKSError mks_video_transcoder_receive(MKSVideoTranscoder *ctx, void *outputPacket) {
    if (!ctx || !outputPacket) return MKS_ERROR_INVALID_PARAM;

    AVPacket *pkt = (AVPacket *)outputPacket;

    int ret = avcodec_receive_packet(ctx->encoderCtx, pkt);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
        return ret == AVERROR(EAGAIN) ? MKS_ERROR_EAGAIN : MKS_ERROR_EOF;
    }
    if (ret < 0) {
        MKS_LOGE("avcodec_receive_packet failed: %d", ret);
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    return MKS_OK;
}

// ============================================================================
// Processing: flush
// ============================================================================

MKSError mks_video_transcoder_flush(MKSVideoTranscoder *ctx) {
    if (!ctx) return MKS_ERROR_INVALID_PARAM;

    int ret;

    // Flush decoder
    ret = avcodec_send_packet(ctx->decoderCtx, NULL);
    if (ret < 0) {
        MKS_LOGW("flush decoder failed: %d", ret);
    }

    // Drain remaining decoded frames
    while (1) {
        ret = avcodec_receive_frame(ctx->decoderCtx, ctx->decodedFrame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            break;
        }
        if (ret < 0) {
            MKS_LOGE("flush receive_frame failed: %d", ret);
            ctx->last_averror = ret;
            return mks_error_from_averror(ret);
        }

        ret = drain_decoded_frame(ctx);
        if (ret < 0) {
            ctx->last_averror = ret;
            return mks_error_from_averror(ret);
        }
    }

    // Flush encoder
    ret = avcodec_send_frame(ctx->encoderCtx, NULL);
    if (ret < 0) {
        MKS_LOGW("flush encoder failed: %d", ret);
    }

    return MKS_OK;
}

// ============================================================================
// Control: reset
// ============================================================================

void mks_video_transcoder_reset(MKSVideoTranscoder *ctx) {
    if (!ctx) return;

    // Flush decoder
    avcodec_send_packet(ctx->decoderCtx, NULL);
    while (avcodec_receive_frame(ctx->decoderCtx, ctx->decodedFrame) >= 0) {}

    // Flush encoder
    avcodec_send_frame(ctx->encoderCtx, NULL);
    AVPacket tmp = {0};
    while (avcodec_receive_packet(ctx->encoderCtx, &tmp) >= 0) {
        av_packet_unref(&tmp);
    }

    // Reset PTS tracking
    ctx->nextPts = 0;
    ctx->inputFirstPts = AV_NOPTS_VALUE;

    MKS_LOGI("transcoder reset complete");
}

// ============================================================================
// Control: getters
// ============================================================================

void mks_video_transcoder_get_time_base(MKSVideoTranscoder *ctx, int *num, int *den) {
    if (!ctx || !ctx->encoderCtx) {
        *num = 1;
        *den = 90000;
        return;
    }
    *num = ctx->encoderCtx->time_base.num;
    *den = ctx->encoderCtx->time_base.den;
}

int mks_video_transcoder_get_output_codec_id(const MKSVideoTranscoder *ctx) {
    return ctx ? ctx->outputCodecId : 0;
}

int mks_video_transcoder_get_width(const MKSVideoTranscoder *ctx) {
    return ctx ? ctx->outputWidth : 0;
}

int mks_video_transcoder_get_height(const MKSVideoTranscoder *ctx) {
    return ctx ? ctx->outputHeight : 0;
}

int mks_video_transcoder_last_averror(const MKSVideoTranscoder *ctx) {
    return ctx ? ctx->last_averror : 0;
}

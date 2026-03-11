// mks_audio.c — Audio transcoder (AC3/EAC3/DTS -> AAC)
//
// Opaque handle wrapping a complete FFmpeg decode -> resample -> encode pipeline.
//
// Architecture:
//   AVPacket (AC3/EAC3/DTS)
//     → avcodec_send_packet (decoder)
//     → avcodec_receive_frame (decoded PCM)
//     → swr_convert (resample to encoder sample rate/format/channels)
//     → avcodec_send_frame (AAC encoder)
//     → avcodec_receive_packet (AAC AVPacket)
//
// The resampler accumulates samples until it has enough for one encoder frame
// (frame_size samples). This naturally handles the mismatch between decoded
// frame sizes and the encoder's required frame size.
//
// Error handling:
//   - All public functions return MKSError (not raw AVERROR).
//   - The last FFmpeg AVERROR is stored per-handle for diagnostic access
//     via mks_audio_transcoder_last_averror() (SQLite pattern).
//   - Internal functions return raw AVERROR for efficiency.
//
// Thread safety: A single MKSAudioTranscoder is NOT thread-safe.
// Create separate instances for concurrent transcoding.

#define MKS_LOG_TAG "mks_audio"

#include "include/mks_audio.h"
#include "internal/mks_internal.h"
#include "internal/mks_log_internal.h"

#include <libswresample/swresample.h>
#include <libavutil/channel_layout.h>
#include <libavutil/frame.h>
#include <libavutil/opt.h>
#include <stdlib.h>

// ============================================================================
// Internal struct definition (opaque to consumers)
// ============================================================================

struct MKSAudioTranscoder {
    AVCodecContext *decoderCtx;
    AVCodecContext *encoderCtx;
    struct SwrContext *swrCtx;
    AVFrame *decodedFrame;
    AVFrame *resampledFrame;
    int64_t nextPts;
    int last_averror;           // SQLite pattern: last FFmpeg error per-handle
};

// ============================================================================
// Internal: drain decoded frames through resampler + encoder
//
// Returns 0 on success, negative AVERROR on failure.
// Called from send() and flush() — error mapping happens at public boundary.
// ============================================================================

static int transcode_drain_decoded(MKSAudioTranscoder *ctx) {
    int ret;

    while (1) {
        ret = avcodec_receive_frame(ctx->decoderCtx, ctx->decodedFrame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            return 0;
        }
        if (ret < 0) {
            MKS_LOGE("avcodec_receive_frame failed: %d", ret);
            return ret;
        }

        int samplesInSwr = swr_get_out_samples(ctx->swrCtx,
                                                 ctx->decodedFrame->nb_samples);
        const uint8_t **in_data = (const uint8_t **)ctx->decodedFrame->extended_data;

        while (samplesInSwr >= ctx->encoderCtx->frame_size ||
               ctx->decodedFrame->nb_samples > 0) {

            av_frame_make_writable(ctx->resampledFrame);
            ctx->resampledFrame->nb_samples = ctx->encoderCtx->frame_size;

            int converted;
            if (ctx->decodedFrame->nb_samples > 0) {
                converted = swr_convert(ctx->swrCtx,
                                         ctx->resampledFrame->extended_data,
                                         ctx->resampledFrame->nb_samples,
                                         in_data,
                                         ctx->decodedFrame->nb_samples);
                ctx->decodedFrame->nb_samples = 0;
                in_data = NULL;
            } else {
                converted = swr_convert(ctx->swrCtx,
                                         ctx->resampledFrame->extended_data,
                                         ctx->resampledFrame->nb_samples,
                                         NULL, 0);
            }

            if (converted <= 0) break;

            if (converted < ctx->encoderCtx->frame_size) {
                break;
            }

            ctx->resampledFrame->nb_samples = converted;
            ctx->resampledFrame->pts = ctx->nextPts;
            ctx->nextPts += converted;

            ret = avcodec_send_frame(ctx->encoderCtx, ctx->resampledFrame);
            if (ret < 0 && ret != AVERROR(EAGAIN)) {
                MKS_LOGE("avcodec_send_frame failed: %d", ret);
                av_frame_unref(ctx->decodedFrame);
                return ret;
            }

            samplesInSwr = swr_get_out_samples(ctx->swrCtx, 0);
            if (samplesInSwr < ctx->encoderCtx->frame_size) break;
        }

        av_frame_unref(ctx->decodedFrame);
    }
}

// ============================================================================
// Lifecycle
// ============================================================================

MKSAudioTranscoder *mks_audio_transcoder_create(
    const void *inputFmtCtx,
    int inputStreamIndex,
    int targetBitrate,
    int targetSampleRate,
    int targetChannels)
{
    const AVFormatContext *inCtx = (const AVFormatContext *)inputFmtCtx;
    if (!inCtx || inputStreamIndex < 0 ||
        (unsigned)inputStreamIndex >= inCtx->nb_streams) {
        MKS_LOGE("invalid input context or stream index %d", inputStreamIndex);
        return NULL;
    }

    mks_layout_detect(inCtx);

    AVCodecParameters *srcPar = mks_layout_get_codecpar(inCtx, inputStreamIndex);
    if (!srcPar) {
        MKS_LOGE("cannot get codecpar for stream %d", inputStreamIndex);
        return NULL;
    }

    int srcCodecId = mks_layout_read_cp_int(srcPar,
                                              offsetof(AVCodecParameters, codec_id));

    if (srcCodecId != AV_CODEC_ID_AC3 &&
        srcCodecId != AV_CODEC_ID_EAC3 &&
        srcCodecId != AV_CODEC_ID_DTS) {
        MKS_LOGW("codec_id %d is not AC3/EAC3/DTS, no transcoding needed",
                 srcCodecId);
        return NULL;
    }

    const char *codecName = srcCodecId == AV_CODEC_ID_AC3  ? "AC3" :
                            srcCodecId == AV_CODEC_ID_EAC3 ? "EAC3" : "DTS";

    // --- Decoder ---

    const AVCodec *decoder = avcodec_find_decoder(srcCodecId);
    if (!decoder) {
        MKS_LOGE("no decoder found for %s (id=%d)", codecName, srcCodecId);
        return NULL;
    }

    AVCodecContext *decCtx = avcodec_alloc_context3(decoder);
    if (!decCtx) {
        MKS_LOGE("failed to allocate decoder context");
        return NULL;
    }

    int ret = avcodec_parameters_to_context(decCtx, srcPar);
    if (ret < 0) {
        MKS_LOGE("avcodec_parameters_to_context failed: %d", ret);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    AVStream *inStream = inCtx->streams[inputStreamIndex];
    decCtx->pkt_timebase = mks_layout_read_stream_rational(
        inStream, offsetof(AVStream, time_base));

    ret = avcodec_open2(decCtx, decoder, NULL);
    if (ret < 0) {
        MKS_LOGE("avcodec_open2 decoder failed: %d", ret);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    int srcSampleRate = decCtx->sample_rate;
    int srcChannels   = decCtx->ch_layout.nb_channels;
    if (srcSampleRate <= 0) srcSampleRate = 48000;
    if (srcChannels   <= 0) srcChannels   = 2;

    int outSampleRate = targetSampleRate > 0 ? targetSampleRate : srcSampleRate;
    int outChannels   = targetChannels   > 0 ? targetChannels   : srcChannels;

    MKS_LOGI("decoder opened: %s %dch %dHz -> target AAC %dch %dHz %dkbps",
             codecName, srcChannels, srcSampleRate,
             outChannels, outSampleRate, targetBitrate / 1000);

    // --- Encoder ---

    const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!encoder) {
        MKS_LOGE("no AAC encoder found in FFmpeg build");
        avcodec_free_context(&decCtx);
        return NULL;
    }

    AVCodecContext *encCtx = avcodec_alloc_context3(encoder);
    if (!encCtx) {
        MKS_LOGE("failed to allocate encoder context");
        avcodec_free_context(&decCtx);
        return NULL;
    }

    encCtx->sample_fmt  = AV_SAMPLE_FMT_FLTP;
    encCtx->sample_rate = outSampleRate;
    encCtx->bit_rate    = targetBitrate;
    av_channel_layout_default(&encCtx->ch_layout, outChannels);
    encCtx->time_base = (AVRational){1, outSampleRate};
    encCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    ret = avcodec_open2(encCtx, encoder, NULL);
    if (ret < 0) {
        MKS_LOGE("avcodec_open2 encoder failed: %d", ret);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    MKS_LOGI("AAC encoder opened: %dch %dHz %dkbps frame_size=%d",
             outChannels, outSampleRate, targetBitrate / 1000, encCtx->frame_size);

    // --- Resampler ---

    struct SwrContext *swr = NULL;
    ret = swr_alloc_set_opts2(&swr,
                               &encCtx->ch_layout, AV_SAMPLE_FMT_FLTP, outSampleRate,
                               &decCtx->ch_layout, decCtx->sample_fmt, srcSampleRate,
                               0, NULL);
    if (ret < 0 || !swr) {
        MKS_LOGE("swr_alloc_set_opts2 failed: %d", ret);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    ret = swr_init(swr);
    if (ret < 0) {
        MKS_LOGE("swr_init failed: %d", ret);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // --- Pre-allocated frames ---

    AVFrame *decodedFrame = av_frame_alloc();
    AVFrame *resampledFrame = av_frame_alloc();
    if (!decodedFrame || !resampledFrame) {
        MKS_LOGE("failed to allocate frames");
        if (decodedFrame)   av_frame_free(&decodedFrame);
        if (resampledFrame) av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    resampledFrame->format      = AV_SAMPLE_FMT_FLTP;
    resampledFrame->sample_rate = outSampleRate;
    av_channel_layout_copy(&resampledFrame->ch_layout, &encCtx->ch_layout);
    resampledFrame->nb_samples  = encCtx->frame_size;

    ret = av_frame_get_buffer(resampledFrame, 0);
    if (ret < 0) {
        MKS_LOGE("av_frame_get_buffer failed: %d", ret);
        av_frame_free(&decodedFrame);
        av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    // --- Assemble handle ---

    MKSAudioTranscoder *tc = calloc(1, sizeof(MKSAudioTranscoder));
    if (!tc) {
        av_frame_free(&decodedFrame);
        av_frame_free(&resampledFrame);
        swr_free(&swr);
        avcodec_free_context(&encCtx);
        avcodec_free_context(&decCtx);
        return NULL;
    }

    tc->decoderCtx     = decCtx;
    tc->encoderCtx     = encCtx;
    tc->swrCtx         = swr;
    tc->decodedFrame   = decodedFrame;
    tc->resampledFrame = resampledFrame;
    tc->nextPts        = 0;
    tc->last_averror   = 0;

    MKS_LOGI("audio transcoder created: %s -> AAC (%dch %dHz %dkbps)",
             codecName, outChannels, outSampleRate, targetBitrate / 1000);
    return tc;
}

MKSError mks_audio_transcoder_setup_output(MKSAudioTranscoder *ctx,
                                            void *outputStream) {
    if (!ctx || !outputStream) return MKS_ERROR_INVALID_PARAM;

    AVStream *outStream = (AVStream *)outputStream;
    AVCodecParameters *outPar = mks_layout_get_stream_codecpar(outStream);
    if (!outPar) {
        MKS_LOGE("cannot get output stream codecpar");
        return MKS_ERROR_INVALID_PARAM;
    }

    int ret = avcodec_parameters_from_context(outPar, ctx->encoderCtx);
    if (ret < 0) {
        ctx->last_averror = ret;
        MKS_LOGE("avcodec_parameters_from_context failed: %d", ret);
        return mks_error_from_averror(ret);
    }

    mks_layout_write_cp_uint32(outPar, offsetof(AVCodecParameters, codec_tag), 0);

    MKS_LOGI("output stream configured: AAC %dch %dHz",
             ctx->encoderCtx->ch_layout.nb_channels,
             ctx->encoderCtx->sample_rate);
    return MKS_OK;
}

void mks_audio_transcoder_free(MKSAudioTranscoder *ctx) {
    if (!ctx) return;

    if (ctx->decodedFrame)   av_frame_free(&ctx->decodedFrame);
    if (ctx->resampledFrame) av_frame_free(&ctx->resampledFrame);
    if (ctx->swrCtx)         swr_free(&ctx->swrCtx);
    if (ctx->encoderCtx)     avcodec_free_context(&ctx->encoderCtx);
    if (ctx->decoderCtx)     avcodec_free_context(&ctx->decoderCtx);

    MKS_LOGI("audio transcoder freed");
    free(ctx);
}

// ============================================================================
// Processing
// ============================================================================

MKS_HOT
MKSError mks_audio_transcoder_send(MKSAudioTranscoder *ctx,
                                    const void *inputPacket) {
    if (!ctx || !inputPacket) return MKS_ERROR_INVALID_PARAM;

    const AVPacket *pkt = (const AVPacket *)inputPacket;

    int ret = avcodec_send_packet(ctx->decoderCtx, pkt);
    if (ret < 0 && ret != AVERROR(EAGAIN)) {
        ctx->last_averror = ret;
        MKS_LOGE("avcodec_send_packet failed: %d", ret);
        return mks_error_from_averror(ret);
    }

    ret = transcode_drain_decoded(ctx);
    if (ret < 0) {
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    return MKS_OK;
}

MKS_HOT
MKSError mks_audio_transcoder_receive(MKSAudioTranscoder *ctx,
                                       void *outputPacket) {
    if (!ctx || !outputPacket) return MKS_ERROR_INVALID_PARAM;

    AVPacket *pkt = (AVPacket *)outputPacket;
    int ret = avcodec_receive_packet(ctx->encoderCtx, pkt);

    if (ret == 0)                return MKS_OK;
    if (ret == AVERROR(EAGAIN))  return MKS_ERROR_EAGAIN;
    if (ret == AVERROR_EOF)      return MKS_ERROR_EOF;

    ctx->last_averror = ret;
    return mks_error_from_averror(ret);
}

MKSError mks_audio_transcoder_flush(MKSAudioTranscoder *ctx) {
    if (!ctx) return MKS_ERROR_INVALID_PARAM;

    // Signal end of input to decoder
    avcodec_send_packet(ctx->decoderCtx, NULL);

    int ret = transcode_drain_decoded(ctx);
    if (ret < 0) {
        ctx->last_averror = ret;
        return mks_error_from_averror(ret);
    }

    // Drain remaining samples from resampler
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

    // Signal end of input to encoder
    avcodec_send_frame(ctx->encoderCtx, NULL);

    MKS_LOGI("transcoder flushed (nextPts=%lld)", (long long)ctx->nextPts);
    return MKS_OK;
}

// ============================================================================
// Control
// ============================================================================

void mks_audio_transcoder_reset(MKSAudioTranscoder *ctx) {
    if (!ctx) return;

    avcodec_flush_buffers(ctx->decoderCtx);
    avcodec_flush_buffers(ctx->encoderCtx);

    if (ctx->swrCtx) {
        swr_close(ctx->swrCtx);
        swr_init(ctx->swrCtx);
    }

    ctx->nextPts      = 0;
    ctx->last_averror = 0;
    MKS_LOGI("transcoder reset after seek");
}

void mks_audio_transcoder_get_time_base(MKSAudioTranscoder *ctx,
                                         int *num, int *den) {
    if (!ctx || !num || !den) {
        if (num) *num = 0;
        if (den) *den = 1;
        return;
    }
    *num = ctx->encoderCtx->time_base.num;
    *den = ctx->encoderCtx->time_base.den;
}

// ============================================================================
// Error context (SQLite pattern)
// ============================================================================

int mks_audio_transcoder_last_averror(const MKSAudioTranscoder *ctx) {
    if (!ctx) return 0;
    return ctx->last_averror;
}

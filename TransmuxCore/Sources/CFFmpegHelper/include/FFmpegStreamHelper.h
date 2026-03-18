#ifndef FFmpegStreamHelper_h
#define FFmpegStreamHelper_h

#include <stdint.h>

// Pure C accessors for FFmpeg struct fields.
//
// WHY: Swift's import of AVStream omits the av_class field, shifting all
// field offsets by 8 bytes. stream.pointee.codecpar returns nil in the app.
// C code compiled against the same FFmpeg headers accesses the correct offsets.
//
// All FFmpeg struct pointers are passed as void* to avoid type conflicts
// between the bridging header and Swift's "import Libavformat" module.

// --- Logging ---
// CFFmpegHelper logging is delegated to CTransmuxFFI's mks_log_impl.
// Call mks_log_init() (from CTransmuxFFI/mks_log.h) before using any mks_* function.

// --- Stream inspection ---

/// Get codec_type (AVMediaType) for a stream. Returns -1 on failure.
int mks_stream_get_codec_type(const void * _Nonnull fmtCtx, int streamIndex);

/// Get codec_id for a stream. Returns 0 (AV_CODEC_ID_NONE) on failure.
int mks_stream_get_codec_id(const void * _Nonnull fmtCtx, int streamIndex);

/// Get disposition flags for a stream. Returns 0 on failure.
int mks_stream_get_disposition(const void * _Nonnull fmtCtx, int streamIndex);

/// Get stream time_base numerator and denominator.
void mks_stream_get_time_base(const void * _Nonnull fmtCtx, int streamIndex,
                               int * _Nonnull num, int * _Nonnull den);

/// Get width from stream codecpar. Returns 0 on failure.
int mks_stream_get_width(const void * _Nonnull fmtCtx, int streamIndex);

/// Get height from stream codecpar. Returns 0 on failure.
int mks_stream_get_height(const void * _Nonnull fmtCtx, int streamIndex);

/// Get number of streams.
int mks_format_get_nb_streams(const void * _Nonnull fmtCtx);

// --- Output stream setup ---

/// Copy codec parameters from source stream to destination stream.
/// dstStream: pointer to AVStream (from avformat_new_stream)
/// srcFmtCtx: pointer to source AVFormatContext
/// Returns 0 on success, negative on error.
int mks_stream_copy_codecpar(void * _Nonnull dstStream,
                              const void * _Nonnull srcFmtCtx,
                              int srcStreamIndex);

/// Set codec_tag to 0 on a stream's codecpar.
void mks_stream_clear_codec_tag(void * _Nonnull stream);

/// Set frame_size on a stream's codecpar.
/// Used to pre-populate AC3/EAC3 frame_size before write_header,
/// eliminating the need for delay_moov.
void mks_stream_set_frame_size(void * _Nonnull fmtCtx, int streamIndex, int frameSize);

/// Check if a stream's codecpar has extradata (non-NULL, size > 0).
/// Returns 1 if extradata exists, 0 otherwise.
int mks_stream_has_extradata(const void * _Nonnull fmtCtx, int streamIndex);

// --- Packet helpers ---

/// Get stream_index from a packet.
int mks_packet_get_stream_index(const void * _Nonnull pkt);

/// Set stream_index on a packet.
void mks_packet_set_stream_index(void * _Nonnull pkt, int index);

/// Rescale packet timestamps between source and destination stream time_bases.
void mks_packet_rescale_ts(void * _Nonnull pkt,
                            const void * _Nonnull srcFmtCtx, int srcStreamIndex,
                            const void * _Nonnull dstFmtCtx, int dstStreamIndex);

/// Set packet pos to -1.
void mks_packet_clear_pos(void * _Nonnull pkt);

// --- Bitstream filter (BSF) ---

/// Create an aac_adtstoasc BSF context for the given audio stream.
/// Converts ADTS-wrapped AAC (from MPEG-TS) to raw AAC for MP4 muxing.
/// Returns an opaque BSF context pointer, or NULL on failure.
void * _Nullable mks_bsf_create_aac_adtstoasc(const void * _Nonnull fmtCtx,
                                                 int audioStreamIndex);

/// Filter a packet through the BSF. Modifies the packet in place.
/// Returns 0 on success (filtered packet available), negative on error.
int mks_bsf_filter_packet(void * _Nonnull bsfCtx, void * _Nonnull pkt);

/// Free a BSF context created by mks_bsf_create_aac_adtstoasc.
void mks_bsf_free(void * _Nullable bsfCtx);

// --- Seek support ---

/// Flush the input demuxer's internal buffers after a seek.
/// Clears stale PES packets so av_read_frame returns fresh data.
/// @param fmtCtx  INPUT format context (the demuxer)
void mks_format_flush_input(void * _Nonnull fmtCtx);

/// Flush BSF internal state after a seek.
/// Sends NULL to drain any partial ADTS frames from before the seek.
/// @param bsfCtx  BSF context (opaque pointer from mks_bsf_create_aac_adtstoasc)
void mks_bsf_flush(void * _Nullable bsfCtx);

/// Check if a packet has the KEY_FRAME flag set.
/// @return 1 if keyframe, 0 otherwise
int mks_packet_is_keyframe(const void * _Nonnull pkt);

/// Add an offset to packet DTS and PTS for timestamp rebasing.
/// Skips AV_NOPTS_VALUE timestamps.
void mks_packet_adjust_ts(void * _Nonnull pkt, int64_t dtsOffset);

/// Get packet DTS. Returns AV_NOPTS_VALUE if not set.
int64_t mks_packet_get_dts(const void * _Nonnull pkt);

/// Get packet PTS. Returns AV_NOPTS_VALUE if not set.
int64_t mks_packet_get_pts(const void * _Nonnull pkt);

/// Set packet DTS to a specific value.
/// Used to recover keyframes where DTS=AV_NOPTS but PTS is valid.
void mks_packet_set_dts(void * _Nonnull pkt, int64_t dts);

// --- Stream metadata ---

/// Get language metadata tag from a stream. Writes up to bufSize chars.
/// Returns 0 on success, -1 if no language tag.
int mks_stream_get_language(const void * _Nonnull fmtCtx, int streamIndex,
                            char * _Nonnull buf, int bufSize);

/// Get title metadata tag from a stream (e.g. "Commentary", "Director's Cut").
/// Returns 0 on success, -1 if no title tag.
int mks_stream_get_title(const void * _Nonnull fmtCtx, int streamIndex,
                         char * _Nonnull buf, int bufSize);

/// Get number of audio channels from stream codecpar.
/// Returns 0 on failure or if not an audio stream.
int mks_stream_get_channels(const void * _Nonnull fmtCtx, int streamIndex);

/// Get audio sample rate from stream codecpar.
/// Returns 0 on failure or if not an audio stream.
int mks_stream_get_sample_rate(const void * _Nonnull fmtCtx, int streamIndex);

/// Get subtitle codec_id for a stream. Returns 0 (AV_CODEC_ID_NONE) if not subtitle.
int mks_stream_get_subtitle_codec_id(const void * _Nonnull fmtCtx, int streamIndex);

// --- Subtitle collector (in-band, fed during remux loop) ---

/// Opaque handle for collecting subtitle packets during the main remux loop.
/// Uses the SAME open connection — no extra HTTP connections needed.
/// IPTV servers block concurrent connections, so this is the only viable approach.
typedef struct MKSSubtitleCollector MKSSubtitleCollector;

/// Create a subtitle collector for N subtitle streams from the already-open format context.
/// @param fmtCtx         The already-open AVFormatContext (same one used for A/V remux)
/// @param streamCount    Number of subtitle streams to collect
/// @param streamIndices  Array of input stream indices
/// @param outputPaths    Array of output .vtt file paths
/// @returns Opaque collector handle, or NULL on error
MKSSubtitleCollector * _Nullable mks_subtitle_collector_create(
    const void * _Nonnull fmtCtx,
    int streamCount,
    const int * _Nonnull streamIndices,
    const char * _Nonnull const * _Nonnull outputPaths);

/// Feed a raw AVPacket to the collector. Call this from the remux loop for subtitle packets.
/// The collector checks if the packet's stream_index matches any of its subtitle streams.
/// If it does, the packet is decoded and the cue is appended to the corresponding .vtt file.
/// @param collector  Handle from mks_subtitle_collector_create
/// @param pkt        Raw AVPacket pointer (const void* to avoid Swift import issues)
void mks_subtitle_collector_feed(MKSSubtitleCollector * _Nonnull collector,
                                  const void * _Nonnull pkt);

/// Finalize the collector: close all output files and free resources.
/// @param collector  Handle to finalize. Do not use after this call.
/// @param cueCounts  Output array of cue counts per stream (length = streamCount from create).
///                   Pass NULL if not needed.
void mks_subtitle_collector_finish(MKSSubtitleCollector * _Nonnull collector,
                                    int * _Nullable cueCounts);

// --- Audio transcoder (AC3/EAC3/DTS → AAC) ---

typedef struct MKSAudioTranscoder MKSAudioTranscoder;

/// Create audio transcoder: decoder + resampler + AAC encoder.
/// Reads codec info from inputFmtCtx stream, configures AAC output.
/// Returns NULL on failure (e.g., unsupported codec, missing decoder).
/// @param inputFmtCtx   Source AVFormatContext (for codecpar + time_base)
/// @param inputStreamIndex  Index of the audio stream to transcode
/// @param targetBitrate     AAC bitrate in bits/s (e.g., 192000 for 192kbps)
/// @param targetSampleRate  Output sample rate (e.g., 48000; 0 = same as source)
/// @param targetChannels    Output channels (e.g., 2 for stereo; 0 = same as source)
MKSAudioTranscoder * _Nullable mks_audio_transcoder_create(
    const void * _Nonnull inputFmtCtx,
    int inputStreamIndex,
    int targetBitrate,
    int targetSampleRate,
    int targetChannels);

/// Configure output stream's codecpar with AAC parameters from encoder.
/// Call after avformat_new_stream() instead of mks_stream_copy_codecpar().
/// @param ctx          Transcoder context
/// @param outputStream Pointer to AVStream (from avformat_new_stream)
/// @return 0 on success, negative on error.
int mks_audio_transcoder_setup_output(MKSAudioTranscoder * _Nonnull ctx,
                                       void * _Nonnull outputStream);

/// Send one input packet to the transcoder (decoder side).
/// Internally decodes → resamples → encodes. Output packets accumulate
/// in the encoder and can be retrieved with mks_audio_transcoder_receive().
/// @return 0 on success, negative on error.
int mks_audio_transcoder_send(MKSAudioTranscoder * _Nonnull ctx,
                               const void * _Nonnull inputPacket);

/// Receive one transcoded AAC packet.
/// @param outputPacket  Pre-allocated AVPacket to fill.
/// @return 0 if packet available, AVERROR(EAGAIN) if need more input,
///         AVERROR_EOF if done.
int mks_audio_transcoder_receive(MKSAudioTranscoder * _Nonnull ctx,
                                  void * _Nonnull outputPacket);

/// Flush remaining buffered frames (call at EOF).
/// After this, call mks_audio_transcoder_receive() in a loop until AVERROR_EOF.
/// @return 0 on success, negative on error.
int mks_audio_transcoder_flush(MKSAudioTranscoder * _Nonnull ctx);

/// Reset after seek: flush decoder+encoder, reset resampler state.
/// Clears internal PTS counter. Call alongside mks_bsf_flush().
void mks_audio_transcoder_reset(MKSAudioTranscoder * _Nonnull ctx);

/// Get encoder time_base for timestamp rescaling.
/// Caller uses this to av_packet_rescale_ts from encoder TB to output TB.
void mks_audio_transcoder_get_time_base(MKSAudioTranscoder * _Nonnull ctx,
                                         int * _Nonnull num, int * _Nonnull den);

/// Free transcoder and all internal contexts.
void mks_audio_transcoder_free(MKSAudioTranscoder * _Nullable ctx);

// --- Diagnostics ---

/// Print struct layout info and pointer chain for a stream.
/// Helps diagnose header/binary mismatches where codecpar appears NULL.
void mks_debug_stream_layout(const void * _Nonnull fmtCtx, int streamIndex);

#endif /* FFmpegStreamHelper_h */

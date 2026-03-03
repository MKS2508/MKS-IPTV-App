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

// --- Logging setup ---

/// Initialize C-level file logging and FFmpeg av_log callback.
/// Routes all CHelper diagnostics and FFmpeg internal messages
/// (e.g. "non monotonically increasing dts") to the same log file
/// that TransmuxLog.swift writes to, so the web log viewer sees everything.
/// Must be called before any other mks_* function.
/// @param logFilePath  Path to append logs to (e.g. "/tmp/mks-iptv-transmux.log")
void mks_log_init(const char * _Nullable logFilePath);

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

// --- Diagnostics ---

/// Print struct layout info and pointer chain for a stream.
/// Helps diagnose header/binary mismatches where codecpar appears NULL.
void mks_debug_stream_layout(const void * _Nonnull fmtCtx, int streamIndex);

#endif /* FFmpegStreamHelper_h */

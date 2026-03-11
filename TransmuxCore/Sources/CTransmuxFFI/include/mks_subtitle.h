// mks_subtitle.h — In-band subtitle extraction to WebVTT
//
// Collects subtitle packets during the remux loop and writes WebVTT files.
// Uses the SAME open connection as the remux — no extra HTTP connections.
// This is critical for IPTV servers that block concurrent connections.
//
// Thread safety: A single MKSSubtitleCollector is NOT thread-safe.
// Feed packets from the remux loop thread only.

#ifndef MKS_CTRANSMUX_FFI_SUBTITLE_H
#define MKS_CTRANSMUX_FFI_SUBTITLE_H

#include "mks_common.h"

#pragma clang assume_nonnull begin

// ============================================================================
// Opaque type
// ============================================================================

/// Opaque subtitle collector handle.
/// The internal struct is defined in mks_subtitle.c.
typedef struct MKSSubtitleCollector MKSSubtitleCollector;

// ============================================================================
// Lifecycle
// ============================================================================

/// Create a subtitle collector for the specified subtitle streams.
///
/// @param fmtCtx        Opaque AVFormatContext* of the input.
/// @param streamCount   Number of subtitle streams to collect (max 16).
/// @param streamIndices Array of stream indices to collect from.
/// @param outputPaths   Array of output file paths (one per stream).
/// @return A new collector handle, or NULL if no decodable streams found.
///
/// @note The collector does NOT take ownership of fmtCtx.
///       The caller must ensure fmtCtx outlives the collector.
MKS_PUBLIC MKS_WARN_UNUSED
MKSSubtitleCollector * _Nullable mks_subtitle_collector_create(
    const void *fmtCtx,
    int streamCount,
    const int *streamIndices,
    const char * _Nonnull const * _Nonnull outputPaths);

// ============================================================================
// Processing
// ============================================================================

/// Feed a packet to the collector during the remux loop.
/// Non-subtitle packets or packets for uncollected streams are ignored.
/// Decoded subtitle cues are written to the corresponding WebVTT file.
MKS_PUBLIC MKS_HOT
void mks_subtitle_collector_feed(MKSSubtitleCollector *collector,
                                  const void *pkt);

// ============================================================================
// Finalization
// ============================================================================

/// Finish collection: close all output files, free decoders.
/// Optionally returns the number of cues written per stream.
///
/// @param collector  The collector to finalize. Freed after this call.
/// @param cueCounts  Optional array (streamCount elements) to receive
///                   per-stream cue counts. Pass NULL to ignore.
MKS_PUBLIC
void mks_subtitle_collector_finish(MKSSubtitleCollector *collector,
                                    int * _Nullable cueCounts);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_SUBTITLE_H

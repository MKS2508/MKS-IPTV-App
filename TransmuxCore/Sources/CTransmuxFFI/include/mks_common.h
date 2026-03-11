// mks_common.h — CTransmuxFFI foundation types
//
// Error codes, transcode tiers, version macros, and compiler attribute helpers.
// Every public header in CTransmuxFFI includes this file.
//
// References:
//   - FFmpeg AVERROR pattern (negative error codes, zero = success)
//   - SQLite ranged error codes (grouped by category)
//   - libcurl CURLcode enum + curl_easy_strerror()
//   - CERT C ERR30-C, ERR33-C

#ifndef MKS_CTRANSMUX_FFI_COMMON_H
#define MKS_CTRANSMUX_FFI_COMMON_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// ============================================================================
// Version
// ============================================================================

#define MKS_VERSION_MAJOR 1
#define MKS_VERSION_MINOR 0
#define MKS_VERSION_MICRO 0

#define MKS_VERSION_INT(a, b, c) (((a) << 16) | ((b) << 8) | (c))
#define MKS_VERSION \
    MKS_VERSION_INT(MKS_VERSION_MAJOR, MKS_VERSION_MINOR, MKS_VERSION_MICRO)

// Stringification helpers for version string generation
#define MKS_STRINGIFY_(x) #x
#define MKS_STRINGIFY(x)  MKS_STRINGIFY_(x)
#define MKS_VERSION_STRING \
    MKS_STRINGIFY(MKS_VERSION_MAJOR) "." \
    MKS_STRINGIFY(MKS_VERSION_MINOR) "." \
    MKS_STRINGIFY(MKS_VERSION_MICRO)

// ============================================================================
// Compiler attribute macros
// ============================================================================

// --- Symbol visibility (FFmpeg, libcurl pattern) ---
#if defined(_WIN32) || defined(__CYGWIN__)
  #define MKS_PUBLIC __declspec(dllexport)
#elif defined(__GNUC__) && __GNUC__ >= 4
  #define MKS_PUBLIC __attribute__((visibility("default")))
#else
  #define MKS_PUBLIC
#endif

#define MKS_INTERNAL __attribute__((visibility("hidden")))

// --- Return value checking (CERT C ERR33-C) ---
#if __has_attribute(warn_unused_result)
  #define MKS_WARN_UNUSED __attribute__((warn_unused_result))
#else
  #define MKS_WARN_UNUSED
#endif

// --- Printf format string checking (GCC/Clang) ---
#if defined(__GNUC__) || defined(__clang__)
  #define MKS_PRINTF_FMT(fmt_idx, args_idx) \
      __attribute__((format(printf, fmt_idx, args_idx)))
#else
  #define MKS_PRINTF_FMT(fmt_idx, args_idx)
#endif

// --- Hot/cold path optimization (I-cache locality) ---
#if __has_attribute(cold)
  #define MKS_COLD __attribute__((cold, noinline))
#else
  #define MKS_COLD
#endif

#if __has_attribute(hot)
  #define MKS_HOT __attribute__((hot))
#else
  #define MKS_HOT
#endif

// ============================================================================
// Error codes
//
// Ranged by category (HTTP status code pattern):
//   General:      -1  to  -99
//   I/O & format: -100 to -199
//   Codec:        -200 to -299
//   VideoToolbox: -300 to -399
//
// Zero = success. Negative = error.
// Use mks_strerror() for human-readable descriptions.
// ============================================================================

typedef enum MKSError {
    MKS_OK = 0,

    // General errors (-1 to -99)
    MKS_ERROR_NOMEM              =  -1,
    MKS_ERROR_INVALID_PARAM      =  -2,
    MKS_ERROR_NOT_INITIALIZED    =  -3,
    MKS_ERROR_UNSUPPORTED        =  -4,

    // I/O and format errors (-100 to -199)
    MKS_ERROR_OPEN_FAILED        = -100,
    MKS_ERROR_EOF                = -101,
    MKS_ERROR_EAGAIN             = -102,
    MKS_ERROR_SEEK_FAILED        = -103,
    MKS_ERROR_IO                 = -104,

    // Codec errors (-200 to -299)
    MKS_ERROR_CODEC_NOT_FOUND    = -200,
    MKS_ERROR_ENCODER_NOT_FOUND  = -201,
    MKS_ERROR_UNSUPPORTED_CODEC  = -202,
    MKS_ERROR_DECODE_FAILED      = -203,
    MKS_ERROR_ENCODE_FAILED      = -204,

    // VideoToolbox errors (-300 to -399)
    MKS_ERROR_VT_SESSION         = -300,
    MKS_ERROR_VT_ENCODE          = -301,
    MKS_ERROR_VT_DECODE          = -302,
} MKSError;

/// Convert an MKSError code to a human-readable string.
/// Thread-safe: uses a caller-provided buffer (av_strerror pattern).
///
/// @param err    The error code to describe.
/// @param buf    Caller-provided buffer for the description.
/// @param buflen Size of buf in bytes (64 recommended minimum).
/// @return 0 on success, -1 if the error code is unknown.
MKS_PUBLIC MKS_WARN_UNUSED
int mks_strerror(MKSError err, char *buf, size_t buflen);

// ============================================================================
// Transcode tiers
//
// Tier 0: Passthrough   — H.264, H.265, ProRes (AVPlayer native)
// Tier 1: Audio-only    — DTS/TrueHD -> AAC, video passthrough
// Tier 2: Video transc. — VP9/AV1/MPEG-2 -> H.264/H.265 via VideoToolbox
// Tier 3: Full transc.  — Unknown/legacy codecs, SW encode fallback
// ============================================================================

typedef enum MKSTranscodeTier {
    MKS_TIER_PASSTHROUGH     = 0,
    MKS_TIER_AUDIO_ONLY      = 1,
    MKS_TIER_VIDEO_TRANSCODE = 2,
    MKS_TIER_FULL_TRANSCODE  = 3,
} MKSTranscodeTier;

// ============================================================================
// Library version query
// ============================================================================

/// Returns the runtime library version as a packed integer.
/// Compare with MKS_VERSION to detect header/library ABI mismatch.
MKS_PUBLIC int mks_version(void);

/// Returns the library version as a static string (e.g., "1.0.0").
/// The returned pointer is valid for the lifetime of the process.
MKS_PUBLIC const char *mks_version_string(void);

#endif // MKS_CTRANSMUX_FFI_COMMON_H

// mks_log_internal.h — CTransmuxFFI internal logging macros
//
// PRIVATE header. Not exposed to consumers (not in include/).
// Provides per-module logging with:
//   - Compile-time format string checking via __attribute__((format))
//   - Compile-time level gating (NDEBUG strips debug/trace)
//   - Runtime level filtering via atomic log level
//   - Branch prediction hints for the non-logging fast path
//
// Usage in .c files:
//   #define MKS_LOG_TAG "mks_audio"
//   #include "internal/mks_log_internal.h"
//
// References:
//   - FFmpeg av_log_once(), av_log() macros
//   - Linux kernel pr_debug / pr_info macros
//   - GCC __attribute__((format(printf, N, M)))

#ifndef MKS_CTRANSMUX_FFI_LOG_INTERNAL_H
#define MKS_CTRANSMUX_FFI_LOG_INTERNAL_H

// Public header — resolved via SPM publicHeadersPath (-I include/)
#include "mks_log.h"

// ============================================================================
// Core log function (implemented in mks_log.c)
// ============================================================================

/// Core variadic log function. All MKS_LOG* macros route here.
/// @note __attribute__((format)) enables compile-time format string checking.
MKS_PRINTF_FMT(3, 4)
void mks_log_impl(const char *tag, MKSLogLevel level, const char *fmt, ...);

// ============================================================================
// Compile-time level gating
// ============================================================================

#ifdef NDEBUG
  #define MKS_MIN_LOG_LEVEL MKS_LOG_INFO
#else
  #define MKS_MIN_LOG_LEVEL MKS_LOG_TRACE
#endif

// ============================================================================
// Branch prediction hint
// ============================================================================

#if defined(__GNUC__) || defined(__clang__)
  #define MKS_UNLIKELY(x) __builtin_expect(!!(x), 0)
#else
  #define MKS_UNLIKELY(x) (x)
#endif

// ============================================================================
// Logging macros
//
// Two-level filtering:
//   1. Compile-time: MKS_MIN_LOG_LEVEL strips dead code in release builds
//   2. Runtime: mks_log_get_level() allows dynamic verbosity changes
//
// The do-while(0) idiom ensures correct behavior in if/else contexts.
// MKS_UNLIKELY hints that logging is not the hot path.
// ============================================================================

#define MKS_LOG(tag, level, fmt, ...)                                        \
    do {                                                                      \
        if ((level) <= MKS_MIN_LOG_LEVEL &&                                  \
            MKS_UNLIKELY((level) <= mks_log_get_level())) {                  \
            mks_log_impl((tag), (level), (fmt), ##__VA_ARGS__);              \
        }                                                                     \
    } while (0)

// ============================================================================
// Per-module convenience macros
//
// Each .c file defines MKS_LOG_TAG before including this header.
// Example:
//   #define MKS_LOG_TAG "mks_audio"
//   #include "internal/mks_log_internal.h"
//
//   MKS_LOGI("encoder opened: %s %dch %dHz", name, ch, rate);
// ============================================================================

#ifndef MKS_LOG_TAG
  #error "Define MKS_LOG_TAG before including mks_log_internal.h"
#endif

#define MKS_LOGP(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_PANIC,   (fmt), ##__VA_ARGS__)
#define MKS_LOGF(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_FATAL,   (fmt), ##__VA_ARGS__)
#define MKS_LOGE(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_ERROR,   (fmt), ##__VA_ARGS__)
#define MKS_LOGW(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_WARNING, (fmt), ##__VA_ARGS__)
#define MKS_LOGI(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_INFO,    (fmt), ##__VA_ARGS__)
#define MKS_LOGV(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_VERBOSE, (fmt), ##__VA_ARGS__)
#define MKS_LOGD(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_DEBUG,   (fmt), ##__VA_ARGS__)
#define MKS_LOGT(fmt, ...) MKS_LOG(MKS_LOG_TAG, MKS_LOG_TRACE,   (fmt), ##__VA_ARGS__)

#endif // MKS_CTRANSMUX_FFI_LOG_INTERNAL_H

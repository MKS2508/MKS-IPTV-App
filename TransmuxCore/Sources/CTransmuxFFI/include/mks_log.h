// mks_log.h — CTransmuxFFI public logging API
//
// Callback-based logging modeled after FFmpeg's av_log facility.
// Log levels match FFmpeg convention: lower numeric value = more severe.
//
// Thread safety: The log callback MUST be thread-safe. The default callback
// (stderr + optional file) uses pthread_mutex_t for file I/O.
//
// References:
//   - FFmpeg libavutil/log.h (callback pattern, level constants)
//   - CERT C CON33-C (thread-safe library functions)

#ifndef MKS_CTRANSMUX_FFI_LOG_H
#define MKS_CTRANSMUX_FFI_LOG_H

#include "mks_common.h"
#include <stdarg.h>

#pragma clang assume_nonnull begin

// ============================================================================
// Log levels (FFmpeg convention: lower = more severe)
// ============================================================================

typedef enum MKSLogLevel {
    MKS_LOG_QUIET   = -8,   // Suppress all output
    MKS_LOG_PANIC   =  0,   // Unrecoverable error, abort imminent
    MKS_LOG_FATAL   =  8,   // Fatal error, cannot continue
    MKS_LOG_ERROR   = 16,   // Error that may be recoverable
    MKS_LOG_WARNING = 24,   // Something unexpected but non-fatal
    MKS_LOG_INFO    = 32,   // Informational messages
    MKS_LOG_VERBOSE = 40,   // Detailed operational info
    MKS_LOG_DEBUG   = 48,   // Developer diagnostics
    MKS_LOG_TRACE   = 56,   // Per-packet / per-frame trace
} MKSLogLevel;

// ============================================================================
// Log callback
// ============================================================================

/// Log callback signature.
/// @param tag    Module identifier (e.g., "mks_audio", "mks_stream").
/// @param level  Severity level of this message.
/// @param fmt    printf-compatible format string.
/// @param vl     Variadic argument list for fmt.
///
/// @note The callback MUST be thread-safe. It may be called concurrently
///       from multiple threads (e.g., decode thread + main thread).
typedef void (*MKSLogCallback)(const char *tag,
                                MKSLogLevel level,
                                const char *fmt,
                                va_list vl);

/// Set the global log callback.
/// Pass NULL to restore the default callback (stderr + optional file).
/// @note Thread-safe. Takes effect immediately for subsequent log calls.
MKS_PUBLIC
void mks_log_set_callback(MKSLogCallback _Nullable callback);

// ============================================================================
// Log level control
// ============================================================================

/// Set the global log level threshold. Messages above this level are suppressed.
/// Default: MKS_LOG_INFO.
/// @note Thread-safe (uses atomic store).
MKS_PUBLIC
void mks_log_set_level(MKSLogLevel level);

/// Get the current global log level.
/// @note Thread-safe (uses atomic load).
MKS_PUBLIC
MKSLogLevel mks_log_get_level(void);

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the CTransmuxFFI logging subsystem.
/// - Optionally opens a log file for persistent output.
/// - Installs the FFmpeg av_log callback to route FFmpeg messages through
///   the CTransmuxFFI logging system.
/// - Safe to call multiple times (idempotent via pthread_once).
///
/// @param logFilePath Path to the log file, or NULL for stderr-only logging.
///
/// Must be called before any other mks_* function.
MKS_PUBLIC
void mks_log_init(const char * _Nullable logFilePath);

#pragma clang assume_nonnull end

#endif // MKS_CTRANSMUX_FFI_LOG_H

// mks_log.c — Logging subsystem + version + error string
//
// Implements the CTransmuxFFI logging facility:
//   - Callback-based log routing (default: stderr + optional file)
//   - FFmpeg av_log integration (routes FFmpeg messages through MKS logging)
//   - pthread_once for idempotent initialization
//   - _Atomic log level for lock-free runtime filtering
//   - mks_strerror() for thread-safe error descriptions
//   - mks_version() / mks_version_string() for ABI checks

#define MKS_LOG_TAG "mks_log"

#include "include/mks_common.h"
#include "include/mks_log.h"
#include "internal/mks_log_internal.h"

#include <libavutil/avutil.h>
#include <libavutil/log.h>
#include <libavutil/time.h>

#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <pthread.h>

// ============================================================================
// State
// ============================================================================

static FILE           *s_log_file     = NULL;
static pthread_mutex_t s_log_mutex    = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t  s_init_once    = PTHREAD_ONCE_INIT;
static _Atomic int     s_log_level    = MKS_LOG_INFO;
// Callback stored as _Atomic void* and cast at use-sites.
// C11 _Atomic on function pointer types is implementation-defined,
// but _Atomic(void*) is universally supported. We cast through void*
// to guarantee atomic load/store semantics without data races.
static _Atomic(void *) s_log_callback = (void *)0;  // NULL = default

// ============================================================================
// Timestamp formatting (matches TransmuxLog.swift: HH:mm:ss.SSS)
// ============================================================================

static void format_timestamp(char *buf, size_t bufsize) {
    int64_t us = av_gettime();
    int64_t total_secs = us / 1000000;
    int ms = (int)((us % 1000000) / 1000);
    int64_t day_secs = total_secs % 86400;
    int h = (int)(day_secs / 3600);
    int m = (int)((day_secs % 3600) / 60);
    int s = (int)(day_secs % 60);
    snprintf(buf, bufsize, "%02d:%02d:%02d.%03d", h, m, s, ms);
}

// ============================================================================
// Level string mapping
// ============================================================================

static const char *level_string(MKSLogLevel level) {
    if (level <= MKS_LOG_ERROR)   return "ERR";
    if (level <= MKS_LOG_WARNING) return "WRN";
    if (level <= MKS_LOG_INFO)    return "INF";
    if (level <= MKS_LOG_VERBOSE) return "VRB";
    if (level <= MKS_LOG_DEBUG)   return "DBG";
    return "TRC";
}

// ============================================================================
// Default log callback (stderr + optional file)
// ============================================================================

static void default_log_callback(const char *tag, MKSLogLevel level,
                                  const char *fmt, va_list vl) {
    char msg[2048];
    vsnprintf(msg, sizeof(msg), fmt, vl);

    char ts[16];
    format_timestamp(ts, sizeof(ts));

    const char *lvl = level_string(level);

    fprintf(stderr, "[%s] [%s] [%s] %s\n", ts, lvl, tag, msg);

    pthread_mutex_lock(&s_log_mutex);
    if (s_log_file) {
        fprintf(s_log_file, "[%s] [%s] [%s] %s\n", ts, lvl, tag, msg);
        fflush(s_log_file);
    }
    pthread_mutex_unlock(&s_log_mutex);
}

// ============================================================================
// Core log implementation (called from MKS_LOG macros)
// ============================================================================

void mks_log_impl(const char *tag, MKSLogLevel level, const char *fmt, ...) {
    va_list vl;
    va_start(vl, fmt);

    MKSLogCallback cb = (MKSLogCallback)atomic_load_explicit(
        &s_log_callback, memory_order_acquire);
    if (cb) {
        cb(tag, level, fmt, vl);
    } else {
        default_log_callback(tag, level, fmt, vl);
    }

    va_end(vl);
}

// ============================================================================
// FFmpeg av_log callback
// ============================================================================

static void ffmpeg_log_callback(void *avcl, int level, const char *fmt, va_list vl) {
    if (level > av_log_get_level()) return;

    // Map FFmpeg log level to MKS log level
    MKSLogLevel mks_level;
    if (level <= AV_LOG_ERROR)        mks_level = MKS_LOG_ERROR;
    else if (level <= AV_LOG_WARNING) mks_level = MKS_LOG_WARNING;
    else if (level <= AV_LOG_INFO)    mks_level = MKS_LOG_INFO;
    else                              mks_level = MKS_LOG_DEBUG;

    // Skip if below current threshold
    if (mks_level > atomic_load_explicit(&s_log_level, memory_order_relaxed))
        return;

    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, vl);

    // Trim trailing whitespace (FFmpeg often appends \n)
    size_t len = strlen(buf);
    while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r' || buf[len-1] == ' ')) {
        buf[--len] = '\0';
    }
    if (len == 0) return;

    // Route through our logging system (no-va_list version)
    mks_log_impl("FFmpeg", mks_level, "%s", buf);
}

// ============================================================================
// Initialization (pthread_once guarantees exactly-once execution)
// ============================================================================

static const char *s_pending_log_path = NULL;

static void mks_log_init_impl(void) {
    pthread_mutex_lock(&s_log_mutex);
    if (s_pending_log_path) {
        s_log_file = fopen(s_pending_log_path, "a");
        if (!s_log_file) {
            fprintf(stderr, "[CTransmuxFFI] WARNING: failed to open log: %s\n",
                    s_pending_log_path);
        }
    }
    pthread_mutex_unlock(&s_log_mutex);

    av_log_set_level(AV_LOG_INFO);
    av_log_set_callback(ffmpeg_log_callback);
}

void mks_log_init(const char *logFilePath) {
    s_pending_log_path = logFilePath;
    pthread_once(&s_init_once, mks_log_init_impl);
}

// ============================================================================
// Public API
// ============================================================================

void mks_log_set_callback(MKSLogCallback callback) {
    atomic_store_explicit(&s_log_callback, (void *)callback, memory_order_release);
}

void mks_log_set_level(MKSLogLevel level) {
    atomic_store_explicit(&s_log_level, level, memory_order_relaxed);
}

MKSLogLevel mks_log_get_level(void) {
    return atomic_load_explicit(&s_log_level, memory_order_relaxed);
}

// ============================================================================
// Error string (av_strerror pattern: caller-provided buffer, thread-safe)
// ============================================================================

int mks_strerror(MKSError err, char *buf, size_t buflen) {
    if (!buf || buflen == 0) return -1;

    const char *desc;
    switch (err) {
    case MKS_OK:                      desc = "Success"; break;
    case MKS_ERROR_NOMEM:             desc = "Out of memory"; break;
    case MKS_ERROR_INVALID_PARAM:     desc = "Invalid parameter"; break;
    case MKS_ERROR_NOT_INITIALIZED:   desc = "Not initialized"; break;
    case MKS_ERROR_UNSUPPORTED:       desc = "Unsupported operation"; break;
    case MKS_ERROR_OPEN_FAILED:       desc = "Failed to open input"; break;
    case MKS_ERROR_EOF:               desc = "End of file"; break;
    case MKS_ERROR_EAGAIN:            desc = "Resource temporarily unavailable"; break;
    case MKS_ERROR_SEEK_FAILED:       desc = "Seek failed"; break;
    case MKS_ERROR_IO:                desc = "I/O error"; break;
    case MKS_ERROR_CODEC_NOT_FOUND:   desc = "Codec not found"; break;
    case MKS_ERROR_ENCODER_NOT_FOUND: desc = "Encoder not found"; break;
    case MKS_ERROR_UNSUPPORTED_CODEC: desc = "Unsupported codec"; break;
    case MKS_ERROR_DECODE_FAILED:     desc = "Decode failed"; break;
    case MKS_ERROR_ENCODE_FAILED:     desc = "Encode failed"; break;
    case MKS_ERROR_VT_SESSION:        desc = "VideoToolbox session error"; break;
    case MKS_ERROR_VT_ENCODE:         desc = "VideoToolbox encode error"; break;
    case MKS_ERROR_VT_DECODE:         desc = "VideoToolbox decode error"; break;
    default:
        snprintf(buf, buflen, "Unknown error (%d)", err);
        return -1;
    }

    snprintf(buf, buflen, "%s", desc);
    return 0;
}

// ============================================================================
// Version
// ============================================================================

int mks_version(void) {
    return MKS_VERSION;
}

const char *mks_version_string(void) {
    return MKS_VERSION_STRING;
}

#!/bin/bash
#===============================================================================
# 5. Build FFmpeg for tvOS (device arm64 + simulator arm64)
#
# Builds FFmpeg static libraries for tvOS device and Apple Silicon simulator.
# Mirror of 3-build-ffmpeg-ios.sh adapted for tvOS triplets and SDKs.
#
# Usage: ./5-build-ffmpeg-tvos.sh [--force]
#        ./5-build-ffmpeg-tvos.sh [--force] arm64       # Only device
#        ./5-build-ffmpeg-tvos.sh [--force] arm64-sim   # Only simulator
#
# LC_BUILD_VERSION expected:
#   - arm64      → platform 3 (tvOS)
#   - arm64-sim  → platform 8 (tvOSSimulator)
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
ARCHS=("arm64" "arm64-sim")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=1
            shift
            ;;
        arm64|arm64-sim)
            ARCHS=("$1")
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

log_section "Building FFmpeg for tvOS (${ARCHS[*]})"

#-------------------------------------------------------------------------------
# Verify source exists
#-------------------------------------------------------------------------------
if [[ ! -d "${FFMPEG_SOURCE_DIR}" ]]; then
    log_error "FFmpeg source not found. Run ./1-download-ffmpeg.sh first"
    exit 1
fi

#-------------------------------------------------------------------------------
# Build function for a single architecture
#-------------------------------------------------------------------------------
build_arch() {
    local ARCH="$1"
    local PLATFORM
    local SDK
    local CFLAGS
    local LDFLAGS
    local OUTPUT_DIR
    local MARKER_FILE
    local CONFIGURE_ARCH
    local AS_FLAG=""

    case "$ARCH" in
        arm64)
            # tvOS device (LC_BUILD_VERSION platform 3 = tvOS)
            PLATFORM="AppleTVOS"
            SDK="appletvos"
            CFLAGS="-arch arm64 -mtvos-version-min=${TVOS_DEPLOYMENT_TARGET}"
            LDFLAGS="-arch arm64 -mtvos-version-min=${TVOS_DEPLOYMENT_TARGET}"
            OUTPUT_DIR="${BUILD_TVOS_ARM64}"
            CONFIGURE_ARCH="arm64"
            # gas-preprocessor needed for arm64 device legacy NEON asm path.
            AS_FLAG="--as=gas-preprocessor.pl -arch arm64 -- xcrun -sdk ${SDK} clang"
            ;;
        arm64-sim)
            # tvOS simulator on Apple Silicon (LC_BUILD_VERSION platform 8 = tvOSSimulator)
            PLATFORM="AppleTVSimulator"
            SDK="appletvsimulator"
            CFLAGS="-arch arm64 -target arm64-apple-tvos${TVOS_DEPLOYMENT_TARGET}-simulator"
            LDFLAGS="-arch arm64 -target arm64-apple-tvos${TVOS_DEPLOYMENT_TARGET}-simulator"
            OUTPUT_DIR="${BUILD_TVOS_SIM_ARM64}"
            CONFIGURE_ARCH="arm64"
            # arm64 simulator builds use clang native assembler — no gas-preprocessor.
            ;;
        *)
            log_error "Unknown arch: $ARCH"
            exit 1
            ;;
    esac

    MARKER_FILE="${OUTPUT_DIR}/.build-complete"

    # Check if already built
    if check_already_built "$MARKER_FILE" "tvOS ${ARCH}"; then
        return 0
    fi

    log_info "Building for tvOS ${ARCH} (${PLATFORM})..."

    ensure_clean_dir "${OUTPUT_DIR}"

    cd "${FFMPEG_SOURCE_DIR}"
    # distclean wipes config.mak + metallib intermediates that contaminate
    # cross-platform reconfigure runs. See 0-config.sh comment.
    make distclean 2>/dev/null || true

    # Configure
    # tvOS does NOT support avfoundation indev (capture). Disable defensively even
    # though FFmpeg auto-detects most platform unsupported indevs.
    local TVOS_EXTRA_FLAGS="--disable-indev=avfoundation"

    if [[ -n "$AS_FLAG" ]]; then
        ./configure \
            --prefix="${OUTPUT_DIR}" \
            --arch="${CONFIGURE_ARCH}" \
            --target-os=darwin \
            --cc="xcrun -sdk ${SDK} clang" \
            --ar="xcrun -sdk ${SDK} ar" \
            "${AS_FLAG}" \
            --extra-cflags="${CFLAGS}" \
            --extra-ldflags="${LDFLAGS}" \
            ${FFMPEG_CONFIGURE_FLAGS} \
            ${TVOS_EXTRA_FLAGS}
    else
        ./configure \
            --prefix="${OUTPUT_DIR}" \
            --arch="${CONFIGURE_ARCH}" \
            --target-os=darwin \
            --cc="xcrun -sdk ${SDK} clang" \
            --ar="xcrun -sdk ${SDK} ar" \
            --extra-cflags="${CFLAGS}" \
            --extra-ldflags="${LDFLAGS}" \
            ${FFMPEG_CONFIGURE_FLAGS} \
            ${TVOS_EXTRA_FLAGS}
    fi

    # Build
    log_info "Compiling tvOS ${ARCH} (parallel jobs: ${FFMPEG_PARALLEL_JOBS})..."
    make -j${FFMPEG_PARALLEL_JOBS}

    # Install
    log_info "Installing tvOS ${ARCH} to ${OUTPUT_DIR}..."
    make install

    # Verify each lib exists
    for lib in "${FFMPEG_LIBRARIES[@]}"; do
        lib_file="${OUTPUT_DIR}/lib/lib${lib}.a"
        if [[ -f "$lib_file" ]]; then
            lipo -info "$lib_file"
        else
            log_error "Missing: lib${lib}.a"
            exit 1
        fi
    done

    # Verify LC_BUILD_VERSION matches expected platform
    verify_platform "$ARCH" "$OUTPUT_DIR"

    mark_built "$MARKER_FILE"
    log_success "tvOS ${ARCH} build complete!"
}

#-------------------------------------------------------------------------------
# Verify the produced .a files have the correct LC_BUILD_VERSION platform tag.
# This catches silent platform mismatches before they break consuming apps.
#-------------------------------------------------------------------------------
verify_platform() {
    local ARCH="$1"
    local OUTPUT_DIR="$2"
    local EXPECTED_PLATFORM_NAME

    case "$ARCH" in
        arm64)      EXPECTED_PLATFORM_NAME="TVOS" ;;          # 3
        arm64-sim)  EXPECTED_PLATFORM_NAME="TVOSSIMULATOR" ;; # 8
    esac

    local probe_lib="${OUTPUT_DIR}/lib/libavformat.a"
    if [[ ! -f "$probe_lib" ]]; then
        log_warning "Skipping platform verification — libavformat.a missing"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local verify_failed=0
    (
        cd "$tmp_dir"
        # libavformat.a may be fat OR thin — try thin first, fallback to copy.
        lipo "$probe_lib" -thin arm64 -output libavformat-thin.a 2>/dev/null \
            || cp "$probe_lib" libavformat-thin.a
        ar -x libavformat-thin.a 2>/dev/null
        local first_obj
        first_obj=$(ls *.o 2>/dev/null | head -1)
        if [[ -z "$first_obj" ]]; then
            log_warning "Could not extract object from libavformat.a — skipping verification"
            exit 0
        fi
        # Grep specifically for the 'platform' field inside LC_BUILD_VERSION.
        # otool prints multiple lines per LC; we want the line matching '^ +platform '.
        local platform_num
        platform_num=$(otool -l "$first_obj" 2>/dev/null \
            | awk '/LC_BUILD_VERSION/{found=1; next} found && /platform/{print $2; exit}')
        if [[ -z "$platform_num" ]]; then
            log_warning "No LC_BUILD_VERSION platform field found in $first_obj"
            exit 0
        fi
        local platform_name
        case "$platform_num" in
            1)  platform_name="MACOS" ;;
            2)  platform_name="IOS" ;;
            3)  platform_name="TVOS" ;;
            7)  platform_name="IOSSIMULATOR" ;;
            8)  platform_name="TVOSSIMULATOR" ;;
            *)  platform_name="UNKNOWN(${platform_num})" ;;
        esac

        if [[ "$platform_name" == "$EXPECTED_PLATFORM_NAME" ]]; then
            log_success "Platform verified: ${platform_name} (LC_BUILD_VERSION=${platform_num})"
            exit 0
        else
            log_error "Platform mismatch! expected ${EXPECTED_PLATFORM_NAME}, got ${platform_name} (${platform_num})"
            exit 1
        fi
    )
    verify_failed=$?
    rm -rf "$tmp_dir"
    if [[ $verify_failed -ne 0 ]]; then
        return 1
    fi
}

#-------------------------------------------------------------------------------
# Build each architecture
#-------------------------------------------------------------------------------
for ARCH in "${ARCHS[@]}"; do
    build_arch "$ARCH"
done

#-------------------------------------------------------------------------------
# Copy shared headers (only need to do once — use device build as reference)
#-------------------------------------------------------------------------------
HEADERS_DIR="${BUILD_TVOS}/include"
if [[ ! -d "$HEADERS_DIR" ]] || [[ "$FORCE_BUILD" == "1" ]]; then
    if [[ -d "${BUILD_TVOS_ARM64}/include" ]]; then
        log_info "Copying headers to ${HEADERS_DIR}..."
        cp -R "${BUILD_TVOS_ARM64}/include" "${HEADERS_DIR}"
    fi
fi

log_success "tvOS FFmpeg build complete!"
log_info "  Device arm64:        ${BUILD_TVOS_ARM64}/lib/"
log_info "  Simulator arm64:     ${BUILD_TVOS_SIM_ARM64}/lib/"

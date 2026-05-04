#!/bin/bash
#===============================================================================
# 3. Build FFmpeg for iOS (device arm64 + simulator x86_64 + simulator arm64)
#
# Builds FFmpeg static libraries for iOS device and simulators (Intel + Apple Silicon).
#
# Usage: ./3-build-ffmpeg-ios.sh [--force]
#        ./3-build-ffmpeg-ios.sh [--force] arm64       # Only device
#        ./3-build-ffmpeg-ios.sh [--force] x86_64      # Only simulator (Intel)
#        ./3-build-ffmpeg-ios.sh [--force] arm64-sim   # Only simulator (Apple Silicon)
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
ARCHS=("arm64" "x86_64" "arm64-sim")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=1
            shift
            ;;
        arm64|x86_64|arm64-sim)
            ARCHS=("$1")
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

log_section "Building FFmpeg for iOS (${ARCHS[*]})"

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
        x86_64)
            PLATFORM="iPhoneSimulator"
            SDK="iphonesimulator"
            CFLAGS="-arch x86_64 -target x86_64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            LDFLAGS="-arch x86_64 -target x86_64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            OUTPUT_DIR="${BUILD_IOS_X64}"
            CONFIGURE_ARCH="x86_64"
            ;;
        arm64-sim)
            # Apple Silicon Mac iOS simulator (LC_BUILD_VERSION platform 7 = iOSSimulator)
            PLATFORM="iPhoneSimulator"
            SDK="iphonesimulator"
            CFLAGS="-arch arm64 -target arm64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            LDFLAGS="-arch arm64 -target arm64-apple-ios${IOS_DEPLOYMENT_TARGET}-simulator"
            OUTPUT_DIR="${BUILD_IOS_SIM_ARM64}"
            CONFIGURE_ARCH="arm64"
            ;;
        arm64)
            # iOS device (LC_BUILD_VERSION platform 2 = iOS)
            PLATFORM="iPhoneOS"
            SDK="iphoneos"
            CFLAGS="-arch arm64 -mios-version-min=${IOS_DEPLOYMENT_TARGET}"
            LDFLAGS="-arch arm64 -mios-version-min=${IOS_DEPLOYMENT_TARGET}"
            OUTPUT_DIR="${BUILD_IOS_ARM64}"
            CONFIGURE_ARCH="arm64"
            # gas-preprocessor only needed for arm64 device build (legacy NEON asm path).
            # arm64 simulator builds use clang native assembler.
            AS_FLAG="--as=gas-preprocessor.pl -arch arm64 -- xcrun -sdk ${SDK} clang"
            ;;
        *)
            log_error "Unknown arch: $ARCH"
            exit 1
            ;;
    esac

    MARKER_FILE="${OUTPUT_DIR}/.build-complete"

    # Check if already built
    if check_already_built "$MARKER_FILE" "iOS ${ARCH}"; then
        return 0
    fi

    log_info "Building for iOS ${ARCH} (${PLATFORM})..."

    ensure_clean_dir "${OUTPUT_DIR}"

    cd "${FFMPEG_SOURCE_DIR}"
    # distclean wipes config.mak + metallib intermediates that contaminate
    # cross-platform reconfigure runs. See 0-config.sh comment.
    make distclean 2>/dev/null || true

    # Configure
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
            ${FFMPEG_CONFIGURE_FLAGS}
    else
        ./configure \
            --prefix="${OUTPUT_DIR}" \
            --arch="${CONFIGURE_ARCH}" \
            --target-os=darwin \
            --cc="xcrun -sdk ${SDK} clang" \
            --ar="xcrun -sdk ${SDK} ar" \
            --extra-cflags="${CFLAGS}" \
            --extra-ldflags="${LDFLAGS}" \
            ${FFMPEG_CONFIGURE_FLAGS}
    fi
    
    # Build
    log_info "Compiling iOS ${ARCH} (parallel jobs: ${FFMPEG_PARALLEL_JOBS})..."
    make -j${FFMPEG_PARALLEL_JOBS}
    
    # Install
    log_info "Installing iOS ${ARCH} to ${OUTPUT_DIR}..."
    make install
    
    # Verify
    for lib in "${FFMPEG_LIBRARIES[@]}"; do
        lib_file="${OUTPUT_DIR}/lib/lib${lib}.a"
        if [[ -f "$lib_file" ]]; then
            lipo -info "$lib_file"
        else
            log_error "Missing: lib${lib}.a"
            exit 1
        fi
    done
    
    mark_built "$MARKER_FILE"
    log_success "iOS ${ARCH} build complete!"
}

#-------------------------------------------------------------------------------
# Build each architecture
#-------------------------------------------------------------------------------
for ARCH in "${ARCHS[@]}"; do
    build_arch "$ARCH"
done

#-------------------------------------------------------------------------------
# Copy shared headers (only need to do once)
#-------------------------------------------------------------------------------
HEADERS_DIR="${BUILD_IOS}/include"
if [[ ! -d "$HEADERS_DIR" ]] || [[ "$FORCE_BUILD" == "1" ]]; then
    log_info "Copying headers to ${HEADERS_DIR}..."
    cp -R "${BUILD_IOS_ARM64}/include" "${HEADERS_DIR}"
fi

log_success "iOS FFmpeg build complete!"
log_info "  Device arm64:        ${BUILD_IOS_ARM64}/lib/"
log_info "  Simulator x86_64:    ${BUILD_IOS_X64}/lib/"
log_info "  Simulator arm64:     ${BUILD_IOS_SIM_ARM64}/lib/"

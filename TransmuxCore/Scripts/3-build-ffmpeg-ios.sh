#!/bin/bash
#===============================================================================
# 3. Build FFmpeg for iOS (device arm64 + simulator x86_64)
#
# Builds FFmpeg static libraries for iOS device and simulator.
#
# Usage: ./3-build-ffmpeg-ios.sh [--force]
#        ./3-build-ffmpeg-ios.sh [--force] arm64      # Only device
#        ./3-build-ffmpeg-ios.sh [--force] x86_64     # Only simulator
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
ARCHS=("arm64" "x86_64")

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=1
            shift
            ;;
        arm64|x86_64)
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
    
    if [[ "$ARCH" == "x86_64" ]]; then
        PLATFORM="iPhoneSimulator"
        SDK="iphonesimulator"
        CFLAGS="-arch x86_64 -mios-simulator-version-min=${IOS_DEPLOYMENT_TARGET}"
        LDFLAGS="-arch x86_64 -mios-simulator-version-min=${IOS_DEPLOYMENT_TARGET}"
        OUTPUT_DIR="${BUILD_IOS_X64}"
    else
        PLATFORM="iPhoneOS"
        SDK="iphoneos"
        CFLAGS="-arch arm64 -mios-version-min=${IOS_DEPLOYMENT_TARGET}"
        LDFLAGS="-arch arm64 -mios-version-min=${IOS_DEPLOYMENT_TARGET}"
        OUTPUT_DIR="${BUILD_IOS_ARM64}"
    fi
    
    MARKER_FILE="${OUTPUT_DIR}/.build-complete"
    
    # Check if already built
    if check_already_built "$MARKER_FILE" "iOS ${ARCH}"; then
        return 0
    fi
    
    log_info "Building for iOS ${ARCH} (${PLATFORM})..."
    
    ensure_clean_dir "${OUTPUT_DIR}"
    
    cd "${FFMPEG_SOURCE_DIR}"
    make clean 2>/dev/null || true
    
    # Configure
    ./configure \
        --prefix="${OUTPUT_DIR}" \
        --arch="${ARCH}" \
        --target-os=darwin \
        --cc="xcrun -sdk ${SDK} clang" \
        --ar="xcrun -sdk ${SDK} ar" \
        --as="gas-preprocessor.pl -arch ${ARCH} -- xcrun -sdk ${SDK} clang" \
        --extra-cflags="${CFLAGS}" \
        --extra-ldflags="${LDFLAGS}" \
        ${FFMPEG_CONFIGURE_FLAGS}
    
    # Build
    log_info "Compiling iOS ${ARCH}..."
    make -j$(sysctl -n hw.ncpu)
    
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
log_info "  Device arm64: ${BUILD_IOS_ARM64}/lib/"
log_info "  Simulator x86_64: ${BUILD_IOS_X64}/lib/"

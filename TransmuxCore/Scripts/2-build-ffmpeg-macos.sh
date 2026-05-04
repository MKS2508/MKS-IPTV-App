#!/bin/bash
#===============================================================================
# 2. Build FFmpeg for macOS (arm64)
#
# Builds FFmpeg static libraries for macOS Apple Silicon.
#
# Usage: ./2-build-ffmpeg-macos.sh [--force]
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
if [[ "$1" == "--force" ]]; then
    FORCE_BUILD=1
fi

log_section "Building FFmpeg for macOS arm64"

#-------------------------------------------------------------------------------
# Verify source exists
#-------------------------------------------------------------------------------
if [[ ! -d "${FFMPEG_SOURCE_DIR}" ]]; then
    log_error "FFmpeg source not found. Run ./1-download-ffmpeg.sh first"
    exit 1
fi

#-------------------------------------------------------------------------------
# Check if already built
#-------------------------------------------------------------------------------
MARKER_FILE="${BUILD_MACOS}/.build-complete"
if check_already_built "$MARKER_FILE" "macOS FFmpeg"; then
    exit 0
fi

#-------------------------------------------------------------------------------
# Setup build directories
#-------------------------------------------------------------------------------
ensure_clean_dir "${BUILD_MACOS}"
ensure_clean_dir "${SCRATCH_DIR}/macos-arm64"

#-------------------------------------------------------------------------------
# Build for macOS arm64
#-------------------------------------------------------------------------------
log_info "Configuring FFmpeg for macOS arm64..."

cd "${FFMPEG_SOURCE_DIR}"

# Clean previous build — distclean wipes config.mak, intermediate metallib
# artifacts, and all generated headers. Plain `make clean` leaves these and
# they cause cross-platform contamination on subsequent ./configure runs.
make distclean 2>/dev/null || true

# Configure
./configure \
    --prefix="${BUILD_MACOS}" \
    --arch=arm64 \
    --target-os=darwin \
    --cc="xcrun -sdk macosx clang" \
    --ar="xcrun -sdk macosx ar" \
    --extra-cflags="-arch arm64 -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET} -O3" \
    --extra-ldflags="-arch arm64 -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}" \
    ${FFMPEG_CONFIGURE_FLAGS}

log_info "Building FFmpeg for macOS arm64 (parallel jobs: ${FFMPEG_PARALLEL_JOBS})..."
# NOTE: -flto=thin was previously enabled but produces bitcode-embedded .o
# files that cannot be packaged into XCFrameworks via xcodebuild
# -create-xcframework (fails with "Unknown header: 0xb17c0de"). Plain -O3
# without LTO gives Mach-O native objects that xcframeworks can wrap.
make -j${FFMPEG_PARALLEL_JOBS}

log_info "Installing to ${BUILD_MACOS}..."
make install

#-------------------------------------------------------------------------------
# Verify build
#-------------------------------------------------------------------------------
for lib in "${FFMPEG_LIBRARIES[@]}"; do
    lib_file="${BUILD_MACOS}/lib/lib${lib}.a"
    if [[ -f "$lib_file" ]]; then
        log_success "Built: lib${lib}.a"
    else
        log_error "Missing: lib${lib}.a"
        exit 1
    fi
done

#-------------------------------------------------------------------------------
# Mark as complete
#-------------------------------------------------------------------------------
mark_built "$MARKER_FILE"
log_success "macOS FFmpeg build complete!"

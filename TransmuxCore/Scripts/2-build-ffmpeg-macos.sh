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

# Clean previous build
make clean 2>/dev/null || true

# Configure
./configure \
    --prefix="${BUILD_MACOS}" \
    --arch=arm64 \
    --target-os=darwin \
    --cc="xcrun -sdk macosx clang" \
    --ar="xcrun -sdk macosx ar" \
    --extra-cflags="-arch arm64 -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}" \
    --extra-ldflags="-arch arm64 -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}" \
    ${FFMPEG_CONFIGURE_FLAGS}

log_info "Building FFmpeg for macOS arm64..."
make -j$(sysctl -n hw.ncpu)

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

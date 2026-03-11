#!/bin/bash
#===============================================================================
# FFmpeg Build Configuration for TransmuxCore
# 
# This script defines all configuration variables for building FFmpeg 8.x
# for Apple platforms (macOS, iOS).
#
# Usage: source 0-config.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# Colors for output
#-------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# FFmpeg Version
#-------------------------------------------------------------------------------
export FFMPEG_VERSION="8.0.1"
export FFMPEG_TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
export FFMPEG_DOWNLOAD_URL="https://ffmpeg.org/releases/${FFMPEG_TARBALL}"

#-------------------------------------------------------------------------------
# Directory Structure
# All builds output to a single unified directory
#-------------------------------------------------------------------------------
export SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TRANSMUX_ROOT="$(dirname "$SCRIPTS_DIR")"
export PROJECT_ROOT="$(dirname "$TRANSMUX_ROOT")"

# Source FFmpeg (downloaded/extracted here)
export FFMPEG_SOURCE_DIR="${SCRIPTS_DIR}/ffmpeg-${FFMPEG_VERSION}"

# Build artifacts (all platforms)
export BUILD_ROOT="${SCRIPTS_DIR}/build"
export BUILD_MACOS="${BUILD_ROOT}/macos"
export BUILD_IOS="${BUILD_ROOT}/ios"
export BUILD_IOS_ARM64="${BUILD_IOS}/arm64"
export BUILD_IOS_X64="${BUILD_IOS}/x86_64"

# Final XCFrameworks output
export XCFRAMEWORKS_DIR="${TRANSMUX_ROOT}/Frameworks/FFmpeg/xcframeworks"

# Temporary scratch directories for building
export SCRATCH_DIR="${BUILD_ROOT}/scratch"

#-------------------------------------------------------------------------------
# Deployment Targets
#-------------------------------------------------------------------------------
export MACOS_DEPLOYMENT_TARGET="14.0"
export IOS_DEPLOYMENT_TARGET="17.0"

#-------------------------------------------------------------------------------
# FFmpeg Configure Flags (common for all platforms)
# TransmuxCore tier system:
#   Tier 0: Container remux (passthrough)
#   Tier 1: Audio transcode (AC3/EAC3/DTS -> AAC)
#   Tier 2: Video transcode (VP9/AV1/MPEG-2 -> H.264/H.265 via VideoToolbox)
#-------------------------------------------------------------------------------
export FFMPEG_CONFIGURE_FLAGS="
    --disable-debug
    --disable-programs
    --disable-doc
    --enable-pic
    --disable-encoder=vvc
    --disable-decoder=vvc
    --enable-cross-compile
    --enable-videotoolbox
    --enable-audiotoolbox
    --enable-encoder=h264_videotoolbox,hevc_videotoolbox
    --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
    --enable-filter=scale_vt,transpose_vt
    --enable-bsf=dts2pts
"

#-------------------------------------------------------------------------------
# Libraries to build
#-------------------------------------------------------------------------------
export FFMPEG_LIBRARIES=(
    "avcodec"
    "avformat"
    "avutil"
    "swresample"
    "swscale"
    "avfilter"
    "avdevice"
)

#-------------------------------------------------------------------------------
# Helper Functions
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required dependency '$1' not found"
        log_info "Install with: brew install $2"
        return 1
    fi
    log_success "Found: $1"
}

ensure_clean_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log_info "Removing existing directory: $dir"
        rm -rf "$dir"
    fi
    mkdir -p "$dir"
}

is_force_mode() {
    [[ "$FORCE_BUILD" == "1" ]]
}

check_already_built() {
    local marker_file="$1"
    local description="$2"
    
    if [[ -f "$marker_file" ]] && ! is_force_mode; then
        log_warning "$description already built (use --force to rebuild)"
        return 0
    fi
    return 1
}

mark_built() {
    local marker_file="$1"
    touch "$marker_file"
}

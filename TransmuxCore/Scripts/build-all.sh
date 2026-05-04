#!/bin/bash
#===============================================================================
# FFmpeg Build Orchestrator for TransmuxCore
#
# Runs all build steps in sequence to create XCFrameworks for macOS, iOS, tvOS.
#
# Usage: ./build-all.sh [options]
#
# Options:
#   --force           Force rebuild all steps
#   --skip-download   Skip download step (use existing source)
#   --macos-only      Only build for macOS
#   --ios-only        Only build for iOS (skips macOS + tvOS)
#   --tvos-only       Only build for tvOS (skips macOS + iOS)
#   --no-tvos         Skip tvOS build (legacy iOS+macOS behaviour)
#   --help            Show this help
#
# Steps:
#   1. Download FFmpeg source
#   2. Build for macOS arm64
#   3. Build for iOS (device arm64 + simulator x86_64 + simulator arm64)
#   4. Build for tvOS (device arm64 + simulator arm64)
#   5. Create XCFrameworks (6 slices per library)
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

#-------------------------------------------------------------------------------
# Parse arguments
#-------------------------------------------------------------------------------
FORCE_BUILD=0
SKIP_DOWNLOAD=0
MACOS_ONLY=0
IOS_ONLY=0
TVOS_ONLY=0
NO_TVOS=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_BUILD=1
            export FORCE_BUILD
            ;;
        --skip-download)
            SKIP_DOWNLOAD=1
            ;;
        --macos-only)
            MACOS_ONLY=1
            ;;
        --ios-only)
            IOS_ONLY=1
            ;;
        --tvos-only)
            TVOS_ONLY=1
            ;;
        --no-tvos)
            NO_TVOS=1
            ;;
        --help|-h)
            head -30 "$0" | tail -25
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

#-------------------------------------------------------------------------------
# Print banner
#-------------------------------------------------------------------------------
clear
cat << "BANNER"
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║     ███████╗██████╗  █████╗ ███╗   ███╗███████╗                             ║
║     ██╔════╝██╔══██╗██╔══██╗████╗ ████║██╔════╝                             ║
║     █████╗  ██████╔╝███████║██╔████╔██║█████╗                               ║
║     ██╔══╝  ██╔══██╗██╔══██║██║╚██╔╝██║██╔══╝                               ║
║     ██║     ██║  ██║██║  ██║██║ ╚═╝ ██║███████╗                             ║
║     ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝                             ║
║                                                                              ║
║                    TransmuxCore Build System                                ║
║                         FFmpeg 8.0.1                                        ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER

echo ""
echo "  Configuration:"
echo "  ─────────────────────────────────────────────────"
echo "  FFmpeg Version:    ${FFMPEG_VERSION}"
echo "  Force Rebuild:     $([ $FORCE_BUILD -eq 1 ] && echo "Yes" || echo "No")"
if [[ $MACOS_ONLY -eq 1 ]]; then
    BUILD_TARGET_LABEL="macOS only"
elif [[ $IOS_ONLY -eq 1 ]]; then
    BUILD_TARGET_LABEL="iOS only"
elif [[ $TVOS_ONLY -eq 1 ]]; then
    BUILD_TARGET_LABEL="tvOS only"
elif [[ $NO_TVOS -eq 1 ]]; then
    BUILD_TARGET_LABEL="macOS + iOS (no tvOS)"
else
    BUILD_TARGET_LABEL="All platforms (macOS + iOS + tvOS)"
fi
echo "  Build Target:      ${BUILD_TARGET_LABEL}"
echo "  Output Directory:  ${XCFRAMEWORKS_DIR}"
echo ""

echo "  Starting build..."
echo ""

START_TIME=$(date +%s)

#-------------------------------------------------------------------------------
# Step 1: Download FFmpeg
#-------------------------------------------------------------------------------
if [[ $SKIP_DOWNLOAD -eq 0 ]]; then
    log_section "Step 1/4: Downloading FFmpeg"
    "${SCRIPT_DIR}/1-download-ffmpeg.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_warning "Skipping download step"
fi

#-------------------------------------------------------------------------------
# Step 2: Build for macOS
#-------------------------------------------------------------------------------
if [[ $IOS_ONLY -eq 0 && $TVOS_ONLY -eq 0 ]]; then
    log_section "Step 2/5: Building for macOS"
    "${SCRIPT_DIR}/2-build-ffmpeg-macos.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_info "Skipping macOS build"
fi

#-------------------------------------------------------------------------------
# Step 3: Build for iOS (device + simulators)
#-------------------------------------------------------------------------------
if [[ $MACOS_ONLY -eq 0 && $TVOS_ONLY -eq 0 ]]; then
    log_section "Step 3/5: Building for iOS"
    "${SCRIPT_DIR}/3-build-ffmpeg-ios.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_info "Skipping iOS build"
fi

#-------------------------------------------------------------------------------
# Step 4: Build for tvOS (device + simulator)
#-------------------------------------------------------------------------------
if [[ $MACOS_ONLY -eq 0 && $IOS_ONLY -eq 0 && $NO_TVOS -eq 0 ]]; then
    log_section "Step 4/5: Building for tvOS"
    "${SCRIPT_DIR}/5-build-ffmpeg-tvos.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_info "Skipping tvOS build"
fi

#-------------------------------------------------------------------------------
# Step 5: Create XCFrameworks
#-------------------------------------------------------------------------------
log_section "Step 5/5: Creating XCFrameworks"
"${SCRIPT_DIR}/4-build-xcframeworks.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")

#-------------------------------------------------------------------------------
# Done!
#-------------------------------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

log_section "Build Complete!"
echo ""
echo "  ╔════════════════════════════════════════════════╗"
echo "  ║             BUILD SUCCESSFUL                   ║"
echo "  ╠════════════════════════════════════════════════╣"
echo "  ║  Duration: ${MINUTES}m ${SECONDS}s                              ║"
echo "  ║  XCFrameworks: ${XCFRAMEWORKS_DIR}"
echo "  ╚════════════════════════════════════════════════╝"
echo ""
echo "  Generated frameworks:"
ls -1 "${XCFRAMEWORKS_DIR}/" | while read fw; do
    echo "    ✓ ${fw}"
done
echo ""
echo "  Next steps:"
echo "    1. cd ${TRANSMUX_ROOT}"
echo "    2. swift build --product transmux-cli"
echo ""

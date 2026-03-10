#!/bin/bash
#===============================================================================
# FFmpeg Build Orchestrator for TransmuxCore
#
# Runs all build steps in sequence to create XCFrameworks for iOS and macOS.
#
# Usage: ./build-all.sh [options]
#
# Options:
#   --force       Force rebuild all steps
#   --skip-download   Skip download step (use existing source)
#   --macos-only      Only build for macOS
#   --ios-only        Only build for iOS
#   --help            Show this help
#
# Steps:
#   1. Download FFmpeg source
#   2. Build for macOS arm64
#   3. Build for iOS (device + simulator)
#   4. Create XCFrameworks
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
echo "  Build Target:      $([ $MACOS_ONLY -eq 1 ] && echo "macOS only" || ([ $IOS_ONLY -eq 1 ] && echo "iOS only" || echo "All platforms"))"
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
if [[ $IOS_ONLY -eq 0 ]]; then
    log_section "Step 2/4: Building for macOS"
    "${SCRIPT_DIR}/2-build-ffmpeg-macos.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_info "Skipping macOS build (--ios-only)"
fi

#-------------------------------------------------------------------------------
# Step 3: Build for iOS
#-------------------------------------------------------------------------------
if [[ $MACOS_ONLY -eq 0 ]]; then
    log_section "Step 3/4: Building for iOS"
    "${SCRIPT_DIR}/3-build-ffmpeg-ios.sh" $([ $FORCE_BUILD -eq 1 ] && echo "--force")
else
    log_info "Skipping iOS build (--macos-only)"
fi

#-------------------------------------------------------------------------------
# Step 4: Create XCFrameworks
#-------------------------------------------------------------------------------
log_section "Step 4/4: Creating XCFrameworks"
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

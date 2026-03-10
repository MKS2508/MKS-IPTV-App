#!/bin/bash
#===============================================================================
# 1. Download and Prepare FFmpeg Source
#
# Downloads FFmpeg source if not present. Idempotent.
#
# Usage: ./1-download-ffmpeg.sh [--force]
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
if [[ "$1" == "--force" ]]; then
    FORCE_BUILD=1
fi

log_section "Downloading FFmpeg ${FFMPEG_VERSION}"

#-------------------------------------------------------------------------------
# Check dependencies
#-------------------------------------------------------------------------------
log_info "Checking dependencies..."
check_dependency yasm yasm
check_dependency nasm nasm

# Check for gas-preprocessor
if ! command -v gas-preprocessor.pl &> /dev/null; then
    log_info "Installing gas-preprocessor.pl..."
    curl -L https://github.com/libav/gas-preprocessor/raw/master/gas-preprocessor.pl \
        -o /usr/local/bin/gas-preprocessor.pl \
        && chmod +x /usr/local/bin/gas-preprocessor.pl
fi
log_success "Found: gas-preprocessor.pl"

#-------------------------------------------------------------------------------
# Download FFmpeg source
#-------------------------------------------------------------------------------
if [[ -d "${FFMPEG_SOURCE_DIR}" ]] && [[ "$FORCE_BUILD" != "1" ]]; then
    log_success "FFmpeg source already exists at ${FFMPEG_SOURCE_DIR}"
    log_info "Use --force to re-download"
    exit 0
fi

cd "${SCRIPTS_DIR}"

# Remove existing if force mode
if [[ -d "${FFMPEG_SOURCE_DIR}" ]]; then
    log_info "Removing existing source..."
    rm -rf "${FFMPEG_SOURCE_DIR}"
fi

# Download if tarball doesn't exist
if [[ ! -f "${FFMPEG_TARBALL}" ]]; then
    log_info "Downloading FFmpeg ${FFMPEG_VERSION}..."
    curl -L -o "${FFMPEG_TARBALL}" "${FFMPEG_DOWNLOAD_URL}"
    log_success "Download complete"
else
    log_info "Tarball already exists: ${FFMPEG_TARBALL}"
fi

# Extract
log_info "Extracting FFmpeg source..."
tar xf "${FFMPEG_TARBALL}"
log_success "Extraction complete"

# Verify
if [[ -f "${FFMPEG_SOURCE_DIR}/configure" ]]; then
    log_success "FFmpeg ${FFMPEG_VERSION} ready at ${FFMPEG_SOURCE_DIR}"
else
    log_error "Extraction failed - configure not found"
    exit 1
fi

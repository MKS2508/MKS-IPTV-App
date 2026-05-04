#!/bin/bash
#===============================================================================
# 4. Create XCFrameworks
#
# Creates XCFrameworks from the built static libraries for each FFmpeg library.
#
# Each XCFramework contains 6 slices:
#   - macOS arm64 (Apple Silicon)
#   - iOS device arm64
#   - iOS simulator x86_64 (Intel Mac)
#   - iOS simulator arm64 (Apple Silicon Mac)
#   - tvOS device arm64
#   - tvOS simulator arm64 (Apple Silicon Mac)
#
# Usage: ./4-build-xcframeworks.sh [--force]
#===============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/0-config.sh"

FORCE_BUILD=0
if [[ "$1" == "--force" ]]; then
    FORCE_BUILD=1
fi

log_section "Creating XCFrameworks"

#-------------------------------------------------------------------------------
# Verify all builds exist
#-------------------------------------------------------------------------------
verify_build() {
    local dir="$1"
    local name="$2"
    
    if [[ ! -d "$dir" ]]; then
        log_error "${name} build not found at ${dir}"
        log_info "Run the appropriate build script first"
        exit 1
    fi
    
    for lib in "${FFMPEG_LIBRARIES[@]}"; do
        if [[ ! -f "${dir}/lib/lib${lib}.a" ]]; then
            log_error "Missing ${name} library: lib${lib}.a"
            exit 1
        fi
    done
    log_success "${name} build verified"
}

verify_build "${BUILD_MACOS}" "macOS arm64"
verify_build "${BUILD_IOS_ARM64}" "iOS device arm64"
verify_build "${BUILD_IOS_X64}" "iOS simulator x86_64"
verify_build "${BUILD_IOS_SIM_ARM64}" "iOS simulator arm64"
verify_build "${BUILD_TVOS_ARM64}" "tvOS device arm64"
verify_build "${BUILD_TVOS_SIM_ARM64}" "tvOS simulator arm64"

#-------------------------------------------------------------------------------
# Create XCFrameworks
#-------------------------------------------------------------------------------
ensure_clean_dir "${XCFRAMEWORKS_DIR}"

# Scratch directory for fat (multi-arch) .a archives. iOS Simulator has two
# arches (x86_64 + arm64) that must share a single LibraryIdentifier — they
# are combined with `lipo -create` into one fat archive per platform variant.
FAT_DIR="${BUILD_ROOT}/scratch/xcframework-fat"
ensure_clean_dir "${FAT_DIR}"

create_framework() {
    local LIB_NAME="$1"  # e.g., "avcodec"
    # Capitalize first letter: avcodec -> Avcodec
    local FRAMEWORK_NAME="$(echo "$LIB_NAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"

    log_info "Creating ${FRAMEWORK_NAME}.xcframework..."

    # iOS Simulator: lipo x86_64 + arm64 into single fat .a (one slice).
    local IOS_SIM_FAT="${FAT_DIR}/ios-sim-fat-lib${LIB_NAME}.a"
    lipo -create \
        "${BUILD_IOS_X64}/lib/lib${LIB_NAME}.a" \
        "${BUILD_IOS_SIM_ARM64}/lib/lib${LIB_NAME}.a" \
        -output "${IOS_SIM_FAT}"

    # Use the -library variant of xcodebuild -create-xcframework. This passes
    # static .a archives directly; xcodebuild reads each archive's
    # LC_BUILD_VERSION to assign the correct slice. No framework wrappers,
    # modulemaps, or Info.plists needed — those are only required for dynamic
    # frameworks. Headers are not bundled into the XCFramework; consumers get
    # headers via Package.swift cSettings header search paths pointing to
    # Frameworks/FFmpeg/include/.
    local OUTPUT_PATH="${XCFRAMEWORKS_DIR}/${FRAMEWORK_NAME}.xcframework"
    local CMD_OUT
    if ! CMD_OUT=$(xcodebuild -create-xcframework \
            -library "${BUILD_MACOS}/lib/lib${LIB_NAME}.a" \
            -library "${BUILD_IOS_ARM64}/lib/lib${LIB_NAME}.a" \
            -library "${IOS_SIM_FAT}" \
            -library "${BUILD_TVOS_ARM64}/lib/lib${LIB_NAME}.a" \
            -library "${BUILD_TVOS_SIM_ARM64}/lib/lib${LIB_NAME}.a" \
            -output "${OUTPUT_PATH}" 2>&1); then
        log_error "xcodebuild failed for ${FRAMEWORK_NAME}.xcframework:"
        echo "$CMD_OUT" >&2
        exit 1
    fi

    if [[ -d "${OUTPUT_PATH}" ]]; then
        log_success "Created ${FRAMEWORK_NAME}.xcframework"
    else
        log_error "Failed to create ${FRAMEWORK_NAME}.xcframework"
        echo "$CMD_OUT" >&2
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Create each XCFramework
#-------------------------------------------------------------------------------
for lib in "${FFMPEG_LIBRARIES[@]}"; do
    create_framework "$lib"
done

#-------------------------------------------------------------------------------
# Copy shared headers
#-------------------------------------------------------------------------------
HEADERS_DEST="${TRANSMUX_ROOT}/Frameworks/FFmpeg/include"
log_info "Copying shared headers to ${HEADERS_DEST}..."
mkdir -p "${HEADERS_DEST}"
cp -R "${BUILD_MACOS}/include/"* "${HEADERS_DEST}/"
log_success "Headers copied"

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
log_section "XCFrameworks Build Complete!"
echo ""
echo "Generated XCFrameworks:"
ls -la "${XCFRAMEWORKS_DIR}/"
echo ""
echo "Headers: ${HEADERS_DEST}"
echo ""
echo "Next steps:"
echo "  1. Update Package.swift to use the XCFrameworks"
echo "  2. Build TransmuxCore: swift build --product transmux-cli"

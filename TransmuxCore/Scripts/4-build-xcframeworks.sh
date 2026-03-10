#!/bin/bash
#===============================================================================
# 4. Create XCFrameworks
#
# Creates XCFrameworks from the built static libraries for each FFmpeg library.
# Each XCFramework contains: iOS device (arm64), iOS simulator (x86_64), macOS (arm64)
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

verify_build "${BUILD_MACOS}" "macOS"
verify_build "${BUILD_IOS_ARM64}" "iOS device"
verify_build "${BUILD_IOS_X64}" "iOS simulator"

#-------------------------------------------------------------------------------
# Create XCFrameworks
#-------------------------------------------------------------------------------
ensure_clean_dir "${XCFRAMEWORKS_DIR}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

create_framework() {
    local LIB_NAME="$1"  # e.g., "avcodec"
    # Capitalize first letter: avcodec -> Avcodec
    local FRAMEWORK_NAME="$(echo "$LIB_NAME" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
    
    log_info "Creating ${FRAMEWORK_NAME}.xcframework..."
    
    # Create framework directories for each platform
    local IOS_DEVICE_FW="${TEMP_DIR}/ios-device/${FRAMEWORK_NAME}.framework"
    local IOS_SIM_FW="${TEMP_DIR}/ios-simulator/${FRAMEWORK_NAME}.framework"
    local MACOS_FW="${TEMP_DIR}/macos/${FRAMEWORK_NAME}.framework"
    
    mkdir -p "${IOS_DEVICE_FW}/Headers"
    mkdir -p "${IOS_SIM_FW}/Headers"
    mkdir -p "${MACOS_FW}/Headers"
    
    # Copy binaries
    cp "${BUILD_IOS_ARM64}/lib/lib${LIB_NAME}.a" "${IOS_DEVICE_FW}/${FRAMEWORK_NAME}"
    cp "${BUILD_IOS_X64}/lib/lib${LIB_NAME}.a" "${IOS_SIM_FW}/${FRAMEWORK_NAME}"
    cp "${BUILD_MACOS}/lib/lib${LIB_NAME}.a" "${MACOS_FW}/${FRAMEWORK_NAME}"
    
    # Copy headers (use iOS as reference)
    if [[ -d "${BUILD_IOS_ARM64}/include/${LIB_NAME}" ]]; then
        cp -R "${BUILD_IOS_ARM64}/include/${LIB_NAME}" "${IOS_DEVICE_FW}/Headers/"
        cp -R "${BUILD_IOS_X64}/include/${LIB_NAME}" "${IOS_SIM_FW}/Headers/"
        cp -R "${BUILD_MACOS}/include/${LIB_NAME}" "${MACOS_FW}/Headers/"
    fi
    
    # Create module.modulemap for each framework
    create_modulemap "${IOS_DEVICE_FW}" "${LIB_NAME}"
    create_modulemap "${IOS_SIM_FW}" "${LIB_NAME}"
    create_modulemap "${MACOS_FW}" "${LIB_NAME}"
    
    # Create Info.plist for each framework
    create_info_plist "${IOS_DEVICE_FW}" "${FRAMEWORK_NAME}" "iPhoneOS"
    create_info_plist "${IOS_SIM_FW}" "${FRAMEWORK_NAME}" "iPhoneSimulator"
    create_info_plist "${MACOS_FW}" "${FRAMEWORK_NAME}" "MacOSX"
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -framework "${IOS_DEVICE_FW}" \
        -framework "${IOS_SIM_FW}" \
        -framework "${MACOS_FW}" \
        -output "${XCFRAMEWORKS_DIR}/${FRAMEWORK_NAME}.xcframework" \
        2>&1 | grep -v "^$" | while read line; do
            if [[ "$line" == *"error"* ]]; then
                log_error "$line"
            elif [[ "$line" == *"warning"* ]]; then
                log_warning "$line"
            fi
        done
    
    if [[ -d "${XCFRAMEWORKS_DIR}/${FRAMEWORK_NAME}.xcframework" ]]; then
        log_success "Created ${FRAMEWORK_NAME}.xcframework"
    else
        log_error "Failed to create ${FRAMEWORK_NAME}.xcframework"
        exit 1
    fi
}

create_modulemap() {
    local FW_DIR="$1"
    local LIB_NAME="$2"
    
    mkdir -p "${FW_DIR}/Modules"
    cat > "${FW_DIR}/Modules/module.modulemap" << EOF
framework module ${LIB_NAME} {
    umbrella header "${LIB_NAME}.h"
    export *
    module * { export * }
}
EOF
    
    # Create umbrella header
    cat > "${FW_DIR}/Headers/${LIB_NAME}.h" << EOF
// Auto-generated umbrella header for ${LIB_NAME}
// FFmpeg ${FFMPEG_VERSION}

#ifndef ${LIB_NAME}_umbrella_h
#define ${LIB_NAME}_umbrella_h

#ifdef __cplusplus
extern "C" {
#endif

EOF
    
    # Add all headers from the library
    if [[ -d "${FW_DIR}/Headers/${LIB_NAME}" ]]; then
        for header in "${FW_DIR}/Headers/${LIB_NAME}"/*.h; do
            echo "#include <${LIB_NAME}/$(basename "$header")>" >> "${FW_DIR}/Headers/${LIB_NAME}.h"
        done
    fi
    
    cat >> "${FW_DIR}/Headers/${LIB_NAME}.h" << EOF

#ifdef __cplusplus
}
#endif

#endif /* ${LIB_NAME}_umbrella_h */
EOF
}

create_info_plist() {
    local FW_DIR="$1"
    local FRAMEWORK_NAME="$2"
    local PLATFORM="$3"
    
    cat > "${FW_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ffmpeg.${FRAMEWORK_NAME}</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${FFMPEG_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${FFMPEG_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${PLATFORM}</string>
    </array>
</dict>
</plist>
EOF
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

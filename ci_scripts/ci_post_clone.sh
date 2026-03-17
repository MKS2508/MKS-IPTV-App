#!/bin/bash
#===============================================================================
# Xcode Cloud — ci_post_clone.sh
#
# Runs after Xcode Cloud clones the repository.
# Builds FFmpeg 8.0.1 from source for TransmuxCore since the pre-built
# static libraries are excluded from git (.gitignore).
#
# Environment variables provided by Xcode Cloud:
#   CI_PRIMARY_REPOSITORY_PATH — path to the cloned repository
#   CI_PRODUCT_PLATFORM        — target platform (iOS, macOS, etc.)
#   CI_XCODE_PROJECT           — path to the .xcodeproj
#===============================================================================
set -euo pipefail

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  ci_post_clone.sh — TransmuxCore FFmpeg Build           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
TRANSMUX_ROOT="${REPO_ROOT}/TransmuxCore"
SCRIPTS_DIR="${TRANSMUX_ROOT}/Scripts"
FRAMEWORKS_DIR="${TRANSMUX_ROOT}/Frameworks/FFmpeg"

echo "[INFO] Repository root: ${REPO_ROOT}"
echo "[INFO] TransmuxCore:    ${TRANSMUX_ROOT}"
echo ""

#-------------------------------------------------------------------------------
# Step 1: Install build dependencies
#-------------------------------------------------------------------------------
echo "══════════════════════════════════════════════════════════"
echo "  Step 1/3: Installing build dependencies"
echo "══════════════════════════════════════════════════════════"

if command -v brew &> /dev/null; then
    echo "[INFO] Homebrew found, installing yasm and nasm..."
    brew install yasm nasm 2>/dev/null || {
        echo "[WARN] brew install failed, checking if already installed..."
        command -v yasm && echo "[OK] yasm available" || echo "[ERROR] yasm not available"
        command -v nasm && echo "[OK] nasm available" || echo "[ERROR] nasm not available"
    }
else
    echo "[WARN] Homebrew not found, checking for pre-installed tools..."
    command -v yasm || echo "[ERROR] yasm not found"
    command -v nasm || echo "[ERROR] nasm not found"
fi

echo ""

#-------------------------------------------------------------------------------
# Step 2: Build FFmpeg from source
#-------------------------------------------------------------------------------
echo "══════════════════════════════════════════════════════════"
echo "  Step 2/3: Building FFmpeg from source"
echo "══════════════════════════════════════════════════════════"

if [[ ! -d "${SCRIPTS_DIR}" ]]; then
    echo "[ERROR] TransmuxCore/Scripts not found at: ${SCRIPTS_DIR}"
    exit 1
fi

cd "${SCRIPTS_DIR}"

# Make all build scripts executable
chmod +x 0-config.sh 1-download-ffmpeg.sh 2-build-ffmpeg-macos.sh \
         3-build-ffmpeg-ios.sh 4-build-xcframeworks.sh build-all.sh

echo "[INFO] Starting FFmpeg build (all platforms)..."
echo "[INFO] This will download FFmpeg 8.0.1, compile for macOS + iOS, and create XCFrameworks"
echo ""

./build-all.sh

echo ""

#-------------------------------------------------------------------------------
# Step 3: Copy .a libraries to Package.swift expected locations
#
# Package.swift uses -L flags pointing to:
#   Frameworks/FFmpeg/macos/arm64/
#   Frameworks/FFmpeg/ios/arm64/
#   Frameworks/FFmpeg/ios/x86_64/ (simulator, for tvOS too)
#
# build-all.sh outputs to Scripts/build/{platform}/lib/
# and copies headers + xcframeworks to Frameworks/FFmpeg/
# but does NOT copy the raw .a files to the -L locations.
#-------------------------------------------------------------------------------
echo "══════════════════════════════════════════════════════════"
echo "  Step 3/3: Copying static libraries to Package.swift locations"
echo "══════════════════════════════════════════════════════════"

BUILD_DIR="${SCRIPTS_DIR}/build"

# macOS arm64
if [[ -d "${BUILD_DIR}/macos/lib" ]]; then
    mkdir -p "${FRAMEWORKS_DIR}/macos/arm64"
    cp "${BUILD_DIR}/macos/lib/"*.a "${FRAMEWORKS_DIR}/macos/arm64/"
    echo "[OK] macOS arm64 libraries copied ($(ls "${FRAMEWORKS_DIR}/macos/arm64/"*.a | wc -l | tr -d ' ') libs)"
else
    echo "[WARN] macOS build output not found at ${BUILD_DIR}/macos/lib"
fi

# iOS arm64 (device)
if [[ -d "${BUILD_DIR}/ios/arm64/lib" ]]; then
    mkdir -p "${FRAMEWORKS_DIR}/ios/arm64"
    cp "${BUILD_DIR}/ios/arm64/lib/"*.a "${FRAMEWORKS_DIR}/ios/arm64/"
    echo "[OK] iOS arm64 libraries copied ($(ls "${FRAMEWORKS_DIR}/ios/arm64/"*.a | wc -l | tr -d ' ') libs)"
else
    echo "[WARN] iOS arm64 build output not found at ${BUILD_DIR}/ios/arm64/lib"
fi

# iOS x86_64 (simulator)
if [[ -d "${BUILD_DIR}/ios/x86_64/lib" ]]; then
    mkdir -p "${FRAMEWORKS_DIR}/ios/x86_64"
    cp "${BUILD_DIR}/ios/x86_64/lib/"*.a "${FRAMEWORKS_DIR}/ios/x86_64/"
    echo "[OK] iOS x86_64 simulator libraries copied ($(ls "${FRAMEWORKS_DIR}/ios/x86_64/"*.a | wc -l | tr -d ' ') libs)"
else
    echo "[WARN] iOS x86_64 build output not found at ${BUILD_DIR}/ios/x86_64/lib"
fi

echo ""

#-------------------------------------------------------------------------------
# Verification
#-------------------------------------------------------------------------------
echo "══════════════════════════════════════════════════════════"
echo "  Verification"
echo "══════════════════════════════════════════════════════════"

REQUIRED_LIBS=("libavcodec.a" "libavformat.a" "libavutil.a" "libswresample.a" "libswscale.a" "libavfilter.a" "libavdevice.a")
ERRORS=0

# Check headers
if [[ -d "${FRAMEWORKS_DIR}/include/libavformat" ]]; then
    echo "[OK] FFmpeg headers present"
else
    echo "[ERROR] FFmpeg headers missing at ${FRAMEWORKS_DIR}/include/"
    ERRORS=$((ERRORS + 1))
fi

# Check iOS arm64 libraries (required for TestFlight)
for lib in "${REQUIRED_LIBS[@]}"; do
    if [[ -f "${FRAMEWORKS_DIR}/ios/arm64/${lib}" ]]; then
        echo "[OK] iOS arm64: ${lib}"
    else
        echo "[ERROR] Missing iOS arm64: ${lib}"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check macOS arm64 libraries
for lib in "${REQUIRED_LIBS[@]}"; do
    if [[ -f "${FRAMEWORKS_DIR}/macos/arm64/${lib}" ]]; then
        echo "[OK] macOS arm64: ${lib}"
    else
        echo "[ERROR] Missing macOS arm64: ${lib}"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""

if [[ ${ERRORS} -gt 0 ]]; then
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  [ERROR] ${ERRORS} verification errors found!                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    exit 1
else
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  [OK] All FFmpeg libraries verified successfully!       ║"
    echo "╚══════════════════════════════════════════════════════════╝"
fi

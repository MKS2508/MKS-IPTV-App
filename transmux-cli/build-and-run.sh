#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_BASE="/Users/mks/Library/Developer/Xcode/DerivedData/mks-multiplatform-iptv-gcedrffrfjscjfeevtoxyyjifzlr/SourcePackages/checkouts/FFmpegKit/Sources"

# Framework directories (macOS universal)
FW_AVFORMAT="$FFMPEG_BASE/Libavformat.xcframework/macos-arm64_x86_64"
FW_AVCODEC="$FFMPEG_BASE/Libavcodec.xcframework/macos-arm64_x86_64"
FW_AVUTIL="$FFMPEG_BASE/Libavutil.xcframework/macos-arm64_x86_64"
FW_SWRESAMPLE="$FFMPEG_BASE/Libswresample.xcframework/macos-arm64_x86_64"
FW_SWSCALE="$FFMPEG_BASE/Libswscale.xcframework/macos-arm64_x86_64"

# Verify frameworks exist
for fw in "$FW_AVFORMAT" "$FW_AVCODEC" "$FW_AVUTIL"; do
    if [ ! -d "$fw" ]; then
        echo "ERROR: Framework not found at $fw"
        echo "Make sure you've built the main project in Xcode first (to populate DerivedData)"
        exit 1
    fi
done

echo "=== Building transmux-cli ==="

swiftc \
    -F "$FW_AVFORMAT" \
    -F "$FW_AVCODEC" \
    -F "$FW_AVUTIL" \
    -F "$FW_SWRESAMPLE" \
    -F "$FW_SWSCALE" \
    -framework Libavformat \
    -framework Libavcodec \
    -framework Libavutil \
    -Xlinker -rpath -Xlinker "$FW_AVFORMAT" \
    -Xlinker -rpath -Xlinker "$FW_AVCODEC" \
    -Xlinker -rpath -Xlinker "$FW_AVUTIL" \
    -Xlinker -rpath -Xlinker "$FW_SWRESAMPLE" \
    -Xlinker -rpath -Xlinker "$FW_SWSCALE" \
    -O \
    "$SCRIPT_DIR/main.swift" \
    -o "$SCRIPT_DIR/transmux-cli"

echo "=== Build OK ==="
echo ""

if [ $# -ge 1 ]; then
    echo "=== Running ==="
    DYLD_FRAMEWORK_PATH="$FW_AVFORMAT:$FW_AVCODEC:$FW_AVUTIL:$FW_SWRESAMPLE:$FW_SWSCALE" \
        "$SCRIPT_DIR/transmux-cli" "$@"
else
    echo "Built successfully. Run with:"
    echo "  $0 <url> [--transmux]"
fi

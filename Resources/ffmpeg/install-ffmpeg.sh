#!/bin/bash

# FFmpeg Installation Script for mks-multiplatform-iptv
# This script downloads and installs ffprobe for stream analysis

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-6.1.1.zip"
FFPROBE_PATH="$SCRIPT_DIR/ffprobe"

echo "🔧 FFmpeg Installation Script"
echo "=============================\n"

# Check if ffprobe already exists
if [ -f "$FFPROBE_PATH" ]; then
    echo "✅ ffprobe already exists at: $FFPROBE_PATH"
    echo "Version info:"
    "$FFPROBE_PATH" -version | head -n 1
    exit 0
fi

echo "📥 Downloading ffprobe..."
curl -L -o "$SCRIPT_DIR/ffprobe.zip" "$FFPROBE_URL"

if [ $? -ne 0 ]; then
    echo "❌ Failed to download ffprobe"
    exit 1
fi

echo "📦 Extracting ffprobe..."
unzip -q "$SCRIPT_DIR/ffprobe.zip" -d "$SCRIPT_DIR"
rm "$SCRIPT_DIR/ffprobe.zip"

# Make executable
chmod +x "$FFPROBE_PATH"

# Remove quarantine attribute (macOS Gatekeeper)
xattr -d com.apple.quarantine "$FFPROBE_PATH" 2>/dev/null

echo "✅ ffprobe installed successfully!"
echo "📍 Location: $FFPROBE_PATH"
echo "\nVersion info:"
"$FFPROBE_PATH" -version | head -n 1

echo "\n💡 To use system-wide, you can:"
echo "   brew install ffmpeg"
echo "\n✨ Done!"
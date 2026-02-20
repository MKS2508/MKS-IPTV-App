#!/bin/bash
# fix-ksplayer-frameworks.sh
# Fixes KSPlayer/FFmpegKit framework issues for macOS builds on Xcode 26+
#
# Issues fixed:
# 1. Shallow bundle → Versioned bundle structure (macOS requirement)
# 2. CFBundleIdentifier with underscores (Apple validation requirement)
# 3. Re-signs all modified frameworks
#
# This script runs as a Build Phase after "Embed Frameworks".
# On iOS builds, it only fixes CFBundleIdentifier issues (no shallow bundle problem).

set -euo pipefail

# Determine frameworks directory based on platform
if [ "${PLATFORM_NAME:-}" = "macosx" ]; then
    FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
elif [ "${PLATFORM_NAME:-}" = "iphoneos" ] || [ "${PLATFORM_NAME:-}" = "iphonesimulator" ]; then
    FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Frameworks"
elif [ "${PLATFORM_NAME:-}" = "appletvos" ] || [ "${PLATFORM_NAME:-}" = "appletvsimulator" ]; then
    FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Frameworks"
else
    echo "fix-frameworks: Unknown platform '${PLATFORM_NAME:-}', skipping."
    exit 0
fi

if [ ! -d "$FRAMEWORKS_DIR" ]; then
    echo "fix-frameworks: No Frameworks directory at $FRAMEWORKS_DIR, skipping."
    exit 0
fi

FIXED_STRUCTURE=0
FIXED_BUNDLEID=0
RESIGNED=0

for FRAMEWORK_PATH in "$FRAMEWORKS_DIR"/*.framework; do
    [ -d "$FRAMEWORK_PATH" ] || continue
    FRAMEWORK_NAME=$(basename "$FRAMEWORK_PATH" .framework)

    # --- Fix 1: Shallow bundle → Versioned bundle (macOS only) ---
    if [ "${PLATFORM_NAME:-}" = "macosx" ]; then
        if [ -f "$FRAMEWORK_PATH/Info.plist" ] && [ ! -d "$FRAMEWORK_PATH/Versions" ]; then
            echo "fix-frameworks: Converting shallow bundle: $FRAMEWORK_NAME"

            mkdir -p "$FRAMEWORK_PATH/Versions/A/Resources"

            # Move binary
            if [ -f "$FRAMEWORK_PATH/$FRAMEWORK_NAME" ]; then
                mv "$FRAMEWORK_PATH/$FRAMEWORK_NAME" "$FRAMEWORK_PATH/Versions/A/"
            fi

            # Move Info.plist
            mv "$FRAMEWORK_PATH/Info.plist" "$FRAMEWORK_PATH/Versions/A/Resources/"

            # Move Headers
            if [ -d "$FRAMEWORK_PATH/Headers" ] && [ ! -L "$FRAMEWORK_PATH/Headers" ]; then
                mv "$FRAMEWORK_PATH/Headers" "$FRAMEWORK_PATH/Versions/A/"
            fi

            # Move Modules
            if [ -d "$FRAMEWORK_PATH/Modules" ] && [ ! -L "$FRAMEWORK_PATH/Modules" ]; then
                mv "$FRAMEWORK_PATH/Modules" "$FRAMEWORK_PATH/Versions/A/"
            fi

            # Move _CodeSignature
            if [ -d "$FRAMEWORK_PATH/_CodeSignature" ]; then
                rm -rf "$FRAMEWORK_PATH/_CodeSignature"
            fi

            # Move any remaining non-Versions items
            for item in "$FRAMEWORK_PATH"/*; do
                local_name=$(basename "$item")
                if [ "$local_name" != "Versions" ] && [ ! -L "$item" ]; then
                    mv "$item" "$FRAMEWORK_PATH/Versions/A/" 2>/dev/null || true
                fi
            done

            # Create symlinks
            ln -sfh A "$FRAMEWORK_PATH/Versions/Current"
            ln -sfh "Versions/Current/Resources" "$FRAMEWORK_PATH/Resources"

            if [ -f "$FRAMEWORK_PATH/Versions/A/$FRAMEWORK_NAME" ]; then
                ln -sfh "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_PATH/$FRAMEWORK_NAME"
            fi
            if [ -d "$FRAMEWORK_PATH/Versions/A/Headers" ]; then
                ln -sfh "Versions/Current/Headers" "$FRAMEWORK_PATH/Headers"
            fi
            if [ -d "$FRAMEWORK_PATH/Versions/A/Modules" ]; then
                ln -sfh "Versions/Current/Modules" "$FRAMEWORK_PATH/Modules"
            fi

            FIXED_STRUCTURE=$((FIXED_STRUCTURE + 1))
        fi
    fi

    # --- Fix 2: CFBundleIdentifier with underscores ---
    # Check both possible plist locations
    for plist in "$FRAMEWORK_PATH/Info.plist" \
                 "$FRAMEWORK_PATH/Resources/Info.plist" \
                 "$FRAMEWORK_PATH/Versions/A/Resources/Info.plist"; do
        [ -f "$plist" ] || continue
        BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$plist" 2>/dev/null || true)
        if echo "$BUNDLE_ID" | grep -q '_'; then
            FIXED_ID=$(echo "$BUNDLE_ID" | tr '_' '-')
            /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $FIXED_ID" "$plist"
            echo "fix-frameworks: Fixed bundle ID: $BUNDLE_ID -> $FIXED_ID"
            FIXED_BUNDLEID=$((FIXED_BUNDLEID + 1))
        fi
        break  # Only process first found plist
    done
done

# --- Fix 3: Re-sign all frameworks ---
SIGNING_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="-"  # Ad-hoc signing for development
fi

for FRAMEWORK_PATH in "$FRAMEWORKS_DIR"/*.framework; do
    [ -d "$FRAMEWORK_PATH" ] || continue
    codesign --force --sign "$SIGNING_IDENTITY" \
        --preserve-metadata=identifier,entitlements \
        --timestamp=none \
        "$FRAMEWORK_PATH" 2>/dev/null || {
            # Fallback to ad-hoc if identity fails
            codesign --force --sign - "$FRAMEWORK_PATH" 2>/dev/null || true
        }
    RESIGNED=$((RESIGNED + 1))
done

echo "fix-frameworks: Done. Structure fixes: $FIXED_STRUCTURE, BundleID fixes: $FIXED_BUNDLEID, Re-signed: $RESIGNED"

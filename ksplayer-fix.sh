#!/bin/bash

# KSPlayer & VLC Framework Fix Script for mks-multiplatform-iptv
# Fixes CFBundleIdentifier issues and framework bundle structure for Xcode 26+
# Handles both KSPlayer and VLC-related frameworks
# 
# Usage:
#   ./ksplayer-fix.sh                    # Auto-discover and fix builds
#   ./ksplayer-fix.sh /path/to/app.bundle  # Fix specific app bundle
#   ./ksplayer-fix.sh /path/to/DerivedData # Fix all bundles in DerivedData

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "🔧 KSPlayer CFBundleIdentifier Fix Script"
echo "=========================================="

# Function to find DerivedData directory
find_derived_data() {
    local project_names=("mks-multiplatform-iptv" "mks-multiplataforma-tvos-iptv")
    
    # Common DerivedData locations
    local search_paths=(
        "$HOME/Library/Developer/Xcode/DerivedData"
        "/Users/*/Library/Developer/Xcode/DerivedData"
    )
    
    for base_path in "${search_paths[@]}"; do
        if [ -d "$base_path" ]; then
            for project_name in "${project_names[@]}"; do
                find "$base_path" -name "*${project_name}*" -type d -maxdepth 1 2>/dev/null | head -1
            done
        fi
    done
}

# Function to find app bundles with problematic frameworks
find_app_bundles() {
    local derived_data="$1"
    # Find apps with frameworks that commonly need fixing
    find "$derived_data" -name "*.app" -type d \( \
        -exec test -d "{}/Contents/Frameworks/libshaderc_combined.framework" \; -o \
        -exec test -d "{}/Frameworks/libshaderc_combined.framework" \; -o \
        -exec test -d "{}/Contents/Frameworks/Libswresample.framework" \; -o \
        -exec test -d "{}/Frameworks/Libswresample.framework" \; -o \
        -exec test -d "{}/Contents/Frameworks/Libavcodec.framework" \; -o \
        -exec test -d "{}/Frameworks/Libavcodec.framework" \; -o \
        -exec test -d "{}/Contents/Frameworks/libharfbuzz.framework" \; -o \
        -exec test -d "{}/Frameworks/libharfbuzz.framework" \; \
    \) -print 2>/dev/null
}

# Function to fix VLC framework bundle structure for macOS
fix_macos_framework_structure() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    # Only process frameworks that have Info.plist in root (shallow bundles)
    if [ ! -f "$framework_path/Info.plist" ]; then
        return 0
    fi
    
    # Check if it already has proper macOS structure
    if [ -d "$framework_path/Versions" ]; then
        log_info "✓ $framework_name already has proper macOS structure"
        return 0
    fi
    
    log_info "🔧 Converting $framework_name to proper macOS bundle structure..."
    
    # Create Versions/A structure
    mkdir -p "$framework_path/Versions/A/Resources"
    
    # Move Info.plist to proper location
    mv "$framework_path/Info.plist" "$framework_path/Versions/A/Resources/"
    
    # Move binary if it exists
    if [ -f "$framework_path/$framework_name" ]; then
        mv "$framework_path/$framework_name" "$framework_path/Versions/A/"
    fi
    
    # Move any other resources
    for item in "$framework_path"/*; do
        if [ -f "$item" ] || [ -d "$item" ]; then
            local basename_item=$(basename "$item")
            if [ "$basename_item" != "Versions" ]; then
                mv "$item" "$framework_path/Versions/A/"
            fi
        fi
    done
    
    # Create symbolic links
    cd "$framework_path/Versions"
    ln -sf A Current
    cd "$framework_path"
    ln -sf Versions/Current/Resources/Info.plist Info.plist
    
    # Create symlink to binary if it exists
    if [ -f "$framework_path/Versions/A/$framework_name" ]; then
        ln -sf "Versions/Current/$framework_name" "$framework_name"
    fi
    
    # Create symlinks for other resources
    for item in "$framework_path/Versions/A"/*; do
        if [ -f "$item" ] || [ -d "$item" ]; then
            local basename_item=$(basename "$item")
            if [ "$basename_item" != "Resources" ] && [ "$basename_item" != "$framework_name" ]; then
                ln -sf "Versions/Current/$basename_item" "$basename_item"
            fi
        fi
    done
    
    log_success "✅ $framework_name converted to proper macOS structure"
    return 0
}

# Function to fix CFBundleIdentifier in a framework
fix_framework_bundle_identifier() {
    local framework_path="$1"
    local new_identifier="$2"
    local framework_name=$(basename "$framework_path" .framework)
    
    if [ ! -f "${framework_path}/Info.plist" ]; then
        log_error "Info.plist not found in $framework_name"
        return 1
    fi
    
    # Get current identifier
    local current_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${framework_path}/Info.plist" 2>/dev/null || echo "")
    
    if [ -z "$current_id" ]; then
        log_error "Could not read CFBundleIdentifier from $framework_name"
        return 1
    fi
    
    log_info "Current CFBundleIdentifier in $framework_name: $current_id"
    
    if [ "$current_id" = "$new_identifier" ]; then
        log_success "$framework_name already has correct CFBundleIdentifier"
        return 0
    fi
    
    # Backup original Info.plist
    cp "${framework_path}/Info.plist" "${framework_path}/Info.plist.backup"
    log_info "Created backup: ${framework_path}/Info.plist.backup"
    
    # Update CFBundleIdentifier
    if /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new_identifier" "${framework_path}/Info.plist" 2>/dev/null; then
        # Verify the change
        local verify_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${framework_path}/Info.plist" 2>/dev/null || echo "")
        if [ "$verify_id" = "$new_identifier" ]; then
            log_success "Successfully updated $framework_name: $current_id → $new_identifier"
            
            # Re-sign the framework for physical device deployment
            if resign_framework "$framework_path"; then
                log_success "Framework $framework_name re-signed successfully"
            else
                log_warning "Could not re-sign $framework_name - may cause issues on physical devices"
            fi
            
            return 0
        else
            log_error "Verification failed for $framework_name (got: $verify_id)"
            # Restore backup
            cp "${framework_path}/Info.plist.backup" "${framework_path}/Info.plist"
            return 1
        fi
    else
        log_error "Failed to update CFBundleIdentifier in $framework_name"
        return 1
    fi
}

# Function to re-sign framework after modifying Info.plist
resign_framework() {
    local framework_path="$1"
    local framework_name=$(basename "$framework_path" .framework)
    
    # Get the app bundle path to determine signing identity
    local app_bundle=$(echo "$framework_path" | sed 's|/Frameworks/.*||')
    
    # Try to get the signing identity from the app bundle
    local signing_identity=""
    if [ -d "$app_bundle" ]; then
        # Extract signing identity from the main app
        signing_identity=$(codesign -dv "$app_bundle" 2>&1 | grep "Authority=" | head -1 | sed 's/Authority=//' || echo "")
        
        # If we can't get the authority, try to get identifier info
        if [ -z "$signing_identity" ]; then
            # Check if it's an ad-hoc signed app (for development)
            local adhoc_check=$(codesign -dv "$app_bundle" 2>&1 | grep "Signature=adhoc" || echo "")
            if [ -n "$adhoc_check" ]; then
                signing_identity="-"  # Use ad-hoc signing
            fi
        fi
    fi
    
    # Default to ad-hoc signing for development
    if [ -z "$signing_identity" ]; then
        signing_identity="-"
    fi
    
    log_info "Re-signing $framework_name with identity: $signing_identity"
    
    # Remove existing signature first
    codesign --remove-signature "$framework_path" 2>/dev/null || true
    
    # Re-sign the framework
    if codesign --force --sign "$signing_identity" "$framework_path" 2>/dev/null; then
        return 0
    else
        # Try with different signing options for development builds
        if codesign --force --sign - --deep "$framework_path" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to fix all problematic frameworks in an app bundle
fix_app_bundle() {
    local app_bundle="$1"
    local fixed_count=0
    local total_problematic=0
    local structure_fixed=0
    local total_structure_issues=0
    
    log_info "Processing app bundle: $(basename "$app_bundle")"
    
    # Determine frameworks path (macOS vs iOS)
    local frameworks_path
    if [ -d "${app_bundle}/Contents/Frameworks" ]; then
        frameworks_path="${app_bundle}/Contents/Frameworks"
        log_info "Detected macOS app bundle"
    elif [ -d "${app_bundle}/Frameworks" ]; then
        frameworks_path="${app_bundle}/Frameworks"
        log_info "Detected iOS app bundle"
    else
        log_warning "No Frameworks directory found in app bundle"
        return 1
    fi
    
    log_info "Scanning frameworks for issues..."
    
    # All frameworks that commonly have structure issues on macOS
    local frameworks_needing_structure_fix=(
        "Libswresample" "Libswscale" "Libavdevice" "gnutls" "libass"
        "Libavcodec" "lcms2" "nettle" "gmp" "libbluray" "libplacebo"
        "libzvbi" "libsrt" "Libavformat" "Libavutil" "Libavfilter"
        "libshaderc_combined" "libharfbuzz" "libdav1d" "libfontconfig"
        "libfreetype" "libfribidi" "libsmbclient" "hogweed"
    )
    
    # Process all frameworks
    for framework in "${frameworks_path}"/*.framework; do
        if [ ! -d "$framework" ]; then
            continue
        fi
        
        local framework_name=$(basename "$framework" .framework)
        
        # Check for macOS bundle structure issues
        for fw in "${frameworks_needing_structure_fix[@]}"; do
            if [[ "$framework_name" == "$fw" ]]; then
                total_structure_issues=$((total_structure_issues + 1))
                if fix_macos_framework_structure "$framework"; then
                    structure_fixed=$((structure_fixed + 1))
                fi
                break
            fi
        done
        
        # Check for CFBundleIdentifier issues (KSPlayer frameworks)
        local info_plist_path="$framework/Info.plist"
        if [ ! -f "$info_plist_path" ] && [ -f "$framework/Versions/Current/Resources/Info.plist" ]; then
            info_plist_path="$framework/Versions/Current/Resources/Info.plist"
        fi
        
        if [ -f "$info_plist_path" ]; then
            local current_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info_plist_path" 2>/dev/null || echo "")
            
            # Check if identifier contains underscore (problematic)
            if [[ "$current_id" == *"_"* ]]; then
                log_warning "Found problematic CFBundleIdentifier: $framework_name ($current_id)"
                total_problematic=$((total_problematic + 1))
                
                # Determine new identifier
                local new_id
                if [[ "$framework_name" == "libshaderc_combined" ]]; then
                    new_id="com.kintan.ksplayer.libshaderc"
                else
                    # Generic underscore replacement strategy
                    new_id=$(echo "$current_id" | sed 's/_combined//g' | sed 's/_/-/g')
                fi
                
                if fix_framework_bundle_identifier "$framework" "$new_id"; then
                    fixed_count=$((fixed_count + 1))
                fi
            else
                if [ -n "$current_id" ]; then
                    log_info "✓ $framework_name: $current_id (CFBundleIdentifier OK)"
                fi
            fi
        fi
    done
    
    echo ""
    log_info "Summary for $(basename "$app_bundle"):"
    log_info "  - Bundle structure issues found: $total_structure_issues"
    log_info "  - Bundle structure issues fixed: $structure_fixed"
    log_info "  - CFBundleIdentifier issues found: $total_problematic"
    log_info "  - CFBundleIdentifier issues fixed: $fixed_count"
    
    local overall_success=true
    
    if [ $total_structure_issues -gt 0 ]; then
        if [ $structure_fixed -eq $total_structure_issues ]; then
            log_success "All bundle structure issues fixed!"
        else
            log_error "Some bundle structure issues could not be fixed ($structure_fixed/$total_structure_issues)"
            overall_success=false
        fi
    fi
    
    if [ $total_problematic -gt 0 ]; then
        if [ $fixed_count -eq $total_problematic ]; then
            log_success "All CFBundleIdentifier issues fixed!"
        else
            log_error "Some CFBundleIdentifier issues could not be fixed ($fixed_count/$total_problematic)"
            overall_success=false
        fi
    fi
    
    if [ $total_structure_issues -eq 0 ] && [ $total_problematic -eq 0 ]; then
        log_success "No issues found - all frameworks are properly configured!"
    fi
    
    return $($overall_success && echo 0 || echo 1)
}

# Main execution
main() {
    # If specific path provided as argument, use it
    if [ $# -gt 0 ]; then
        local target_path="$1"
        log_info "Using provided path: $target_path"
        
        if [ -d "$target_path" ] && [[ "$target_path" == *.app ]]; then
            # Direct app bundle path
            fix_app_bundle "$target_path"
        elif [ -d "$target_path" ]; then
            # Directory path, search for app bundles
            local app_bundles=($(find "$target_path" -name "*.app" -type d -exec test -d "{}/Frameworks/libshaderc_combined.framework" \; -print 2>/dev/null))
            if [ ${#app_bundles[@]} -eq 0 ]; then
                log_error "No app bundles with KSPlayer frameworks found in: $target_path"
                exit 1
            fi
            
            for app_bundle in "${app_bundles[@]}"; do
                fix_app_bundle "$app_bundle"
            done
        else
            log_error "Invalid path provided: $target_path"
            exit 1
        fi
    else
        # Auto-discovery mode
        log_info "Auto-discovering app bundles with KSPlayer frameworks..."
        
        local derived_data=$(find_derived_data)
        if [ -z "$derived_data" ]; then
            log_error "Could not find DerivedData directory for mks-multiplatform-iptv projects"
            log_info "You can specify a path manually: $0 <path-to-app-bundle-or-derived-data>"
            exit 1
        fi
        
        log_info "Found DerivedData: $derived_data"
        
        local app_bundles=($(find_app_bundles "$derived_data"))
        if [ ${#app_bundles[@]} -eq 0 ]; then
            log_warning "No app bundles with KSPlayer frameworks found in DerivedData"
            log_info "This is normal for pre-build. Frameworks will be fixed after they are created."
            exit 0  # Exit successfully when no frameworks found (normal for pre-build)
        fi
        
        log_info "Found ${#app_bundles[@]} app bundle(s) with KSPlayer frameworks"
        echo ""
        
        local overall_success=true
        for app_bundle in "${app_bundles[@]}"; do
            if ! fix_app_bundle "$app_bundle"; then
                overall_success=false
            fi
            echo ""
        done
        
        if $overall_success; then
            log_success "All app bundles processed successfully!"
            log_info "You can now rebuild your project - the CFBundleIdentifier errors should be resolved"
        else
            log_error "Some app bundles had issues. Check the output above for details."
            exit 1
        fi
    fi
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"
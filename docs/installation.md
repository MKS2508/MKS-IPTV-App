# Installation Guide

Complete installation instructions for all supported platforms.

## iOS Installation (AltStore Method)

### Prerequisites
- iOS 26 Beta or later
- AltStore installed on your device
- Mac with AltServer running

### Steps
1. **Download IPA**: Get the latest [mks-multiplatform-iptv.ipa](../build/ios/mks-multiplatform-iptv.ipa)
2. **Transfer to Device**: Use AirDrop, iCloud, or email
3. **Install with AltStore**: 
   - Open the IPA file on your iOS device
   - Select "Share" → "AltStore"
   - Follow AltStore installation prompts
4. **Trust Certificate**:
   - Settings → General → VPN & Device Management
   - Trust your Apple ID certificate

### Detailed iOS Guide
For complete iOS installation instructions, see: [INSTALL-WITH-ALTSTORE.md](../build/ios/INSTALL-WITH-ALTSTORE.md)

## macOS Installation

### System Requirements
- macOS 26 Beta or later
- Apple Silicon or Intel Mac

### Installation
1. Download the macOS .app bundle from [Releases](https://github.com/mks2508/mks-multiplatform-iptv/releases)
2. Drag to Applications folder
3. Right-click → Open (first launch only)
4. Accept "Open from unidentified developer"

## tvOS Installation

### Requirements
- Apple TV with tvOS 26 Beta
- Xcode 16 Beta
- Apple Developer Account
- USB-C cable (Apple TV 4K 3rd gen)

### Steps
1. Connect Apple TV to Mac via USB-C
2. Open project in Xcode
3. Select tvOS scheme: `mks-multiplataforma-tvos-iptv`
4. Build and deploy to device

## Development Setup

### Prerequisites
- Xcode 16 Beta
- macOS 26 Beta
- Swift 6.0
- Apple Developer Account

### Build from Source
```bash
# Clone repository
git clone https://github.com/mks2508/mks-multiplatform-iptv.git
cd mks-multiplatform-iptv

# Build for macOS
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Debug

# Build for iOS (requires code signing)
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Release archive

# Build for tvOS
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplataforma-tvos-iptv -configuration Debug
```

## Configuration

### First Launch
1. Launch the app
2. The app will automatically load available categories
3. Navigate between Movies, Series, Live TV, and Downloads

### IPTV Service Configuration
The app comes pre-configured with demo credentials. For production use:
1. Modify `IPTVConfiguration.swift`
2. Update service endpoints and credentials
3. Rebuild the application

## Troubleshooting

### iOS Installation Issues
- **"Unable to install"**: Check you have fewer than 3 sideloaded apps
- **Certificate issues**: Revoke old certificates at appleid.apple.com
- **AltStore not appearing**: Ensure AltServer is running on your Mac

### macOS Security
- **"Cannot verify developer"**: System Preferences → Security → Allow anyway
- **App won't launch**: Right-click → Open instead of double-clicking

### tvOS Development
- **Build fails**: Ensure Apple TV is connected and in developer mode
- **Deployment issues**: Check Apple Developer account provisioning

## Support

Need help? Check these resources:
- [GitHub Issues](https://github.com/mks2508/mks-multiplatform-iptv/issues)
- [Community Discussions](https://github.com/mks2508/mks-multiplatform-iptv/discussions)
- [Project Wiki](https://github.com/mks2508/mks-multiplatform-iptv/wiki)
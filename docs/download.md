# Downloads

Download MKS-IPTV-App for your platform. All releases are signed and notarized for security.

## 📥 Latest Release: v1.0 Beta

### Quick Downloads

<div class="download-grid">
  <div class="download-card">
    <h3>📱 iOS</h3>
    <p>For iPhone and iPad</p>
    <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest/download/mks-iptv.ipa" class="btn">Download IPA</a>
    <small>iOS 26 Beta or later</small>
  </div>
  
  <div class="download-card">
    <h3>💻 macOS</h3>
    <p>For Mac computers</p>
    <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest/download/mks-iptv-macos-arm64.zip" class="btn">Apple Silicon</a>
    <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest/download/mks-iptv-macos-intel.zip" class="btn">Intel</a>
    <small>macOS 26 Beta or later</small>
  </div>
  
  <div class="download-card">
    <h3>📺 tvOS</h3>
    <p>For Apple TV</p>
    <a href="#tvos-installation" class="btn">Build Guide</a>
    <small>Requires Xcode</small>
  </div>
</div>

## Installation Methods

### iOS Installation Options

#### Method 1: AltStore (Recommended)
1. Download the IPA file above
2. Install [AltStore](https://altstore.io) on your device
3. Open the IPA with AltStore
4. Trust the certificate in Settings

[📖 Detailed AltStore Guide](iOS-Free-Installation-Guide.md)

#### Method 2: TestFlight (Coming Soon)
Join our beta testing program when available.

[📖 TestFlight Guide](TestFlight-Distribution-Guide.md)

#### Method 3: Xcode Installation
For developers with Apple Developer accounts.

### macOS Installation

1. Download the appropriate version for your Mac
2. Unzip the downloaded file
3. Drag MKS-IPTV-App to your Applications folder
4. Right-click and select "Open" on first launch
5. Click "Open" when macOS asks about unidentified developer

### tvOS Installation

Currently requires building from source:

1. Install Xcode 16 Beta
2. Clone the repository
3. Connect Apple TV via USB-C
4. Build and deploy using Xcode

[📖 Full tvOS Guide](installation.md#tvos-installation)

## System Requirements

### Minimum Requirements

| Platform | Minimum Version | Recommended |
|----------|----------------|-------------|
| iOS | iOS 26 Beta | Latest iOS 26 Beta |
| iPadOS | iPadOS 26 Beta | Latest iPadOS 26 Beta |
| macOS | macOS 26 Beta | Latest macOS 26 Beta |
| tvOS | tvOS 26 Beta | Latest tvOS 26 Beta |

### Hardware Requirements

- **iOS/iPadOS**: iPhone 12 or newer, iPad (9th gen) or newer
- **macOS**: Apple Silicon Mac or Intel Mac (2018 or newer)
- **tvOS**: Apple TV 4K (2nd generation or newer)

## Previous Versions

All previous releases are available on our [GitHub Releases](https://github.com/MKS2508/MKS-IPTV-App/releases) page.

## Verify Downloads

All releases are signed. To verify authenticity:

### iOS
- Check certificate in Settings → General → VPN & Device Management

### macOS
```bash
codesign -v /Applications/MKS-IPTV-App.app
```

## Troubleshooting

### Common Issues

**"Cannot be opened because the developer cannot be verified"** (macOS)
- Right-click the app and select "Open"
- Click "Open" in the dialog

**"Unable to install" error** (iOS)
- Ensure you have fewer than 3 sideloaded apps
- Check AltStore is properly configured

**App crashes on launch**
- Verify you're running the required OS version
- Check system requirements above

## Support

Need help with installation?

- 📧 [Open an Issue](https://github.com/MKS2508/MKS-IPTV-App/issues)
- 💬 [Join Discussions](https://github.com/MKS2508/MKS-IPTV-App/discussions)
- 📖 [Installation Guide](installation.md)

---

<style>
.download-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 20px;
  margin: 30px 0;
}

.download-card {
  border: 2px solid #00ff00;
  padding: 20px;
  text-align: center;
  background: rgba(0, 255, 0, 0.05);
  box-shadow: 0 0 20px rgba(0, 255, 0, 0.3);
}

.download-card h3 {
  margin-top: 0;
}

.download-card .btn {
  display: inline-block;
  margin: 10px 5px;
  padding: 10px 20px;
}
</style>
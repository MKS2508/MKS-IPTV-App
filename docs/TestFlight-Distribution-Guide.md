---
layout: default
title: TestFlight Guide
nav_order: 6
---


# ✈️ TestFlight Distribution Guide

This guide describes the complete process for distributing your IPTV app via TestFlight.

---

## 📋 Prerequisites

- **Apple Developer Account**: Required for App Store Connect access ($99/year).
- **Certificates & Profiles**: An Apple Distribution Certificate and an App Store Distribution Provisioning Profile.
- **App Store Connect Record**: You must have an app record created in App Store Connect.

---

## 🚀 Distribution Steps

### Step 1: Create the Archive
If you need to generate a new archive:
```bash
xcodebuild -project mks-multiplatform-iptv.xcodeproj \
           -scheme mks-multiplatform-iptv \
           -configuration Release \
           archive \
           -archivePath ./build/mks-iptv-appstore.xcarchive
```

### Step 2: Create ExportOptions.plist
Create an `ExportOptionsAppStore.plist` file:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

### Step 3: Upload to App Store Connect
You can upload the build using Xcode, Transporter, or the command line.

**Using `xcrun altool` (Command Line):**
```bash
xcrun altool --upload-app \
             -f "./build/appstore-export/mks-multiplatform-iptv.pkg" \
             -t macos \
             -u "your-apple-id@email.com" \
             -p "app-specific-password"
```

### Step 4: Configure TestFlight
Once the build is processed in App Store Connect:
1.  Navigate to your app's **TestFlight** tab.
2.  Complete any required compliance information.
3.  Add build notes under **"What to Test"**.
4.  Start inviting internal or external testers.

---

## ⚙️ Managing Testers

- **Internal Testers (up to 100)**: Team members with a role in App Store Connect. They get access immediately.
- **External Testers (up to 10,000)**: Any user you invite via email or a public link. The first build for external testers requires a beta review by Apple.

> **Note:** TestFlight builds expire after 90 days.

---

## 🔧 Troubleshooting

- **"Invalid Signature"**: Ensure you are using a Distribution Certificate, not a Development one.
- **"Provisioning Profile Mismatch"**: Regenerate the profile in the Apple Developer Portal and ensure it's linked to your App ID.
- **Build Not Processing**: Check your email for notifications from Apple regarding any issues with the build.

For more details, refer to the official [**TestFlight Documentation**](https://developer.apple.com/testflight/).

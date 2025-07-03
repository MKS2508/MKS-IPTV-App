---
layout: default
title: iOS Free Installation Guide
nav_order: 5
---

# 📱 iOS Free Installation Guide

This guide explains how to install the IPTV app on iOS devices for free using sideloading methods.

---

## Comparison of Sideloading Methods

| Method | App Duration | Renewal | App Limit | Requirements |
|:---|:---|:---|:---|:---|
| **AltStore** | 7 Days | Automatic (WiFi) | 3 Apps | Mac/PC + WiFi |
| **Sideloadly** | 7 Days | Manual (USB) | 3 Apps | Mac/PC + USB |
| **TrollStore** | Permanent | Not Required | Unlimited | Specific iOS versions |

---

## Method 1: AltStore (Recommended)

AltStore uses your free Apple ID to sign apps and automatically refreshes them in the background.

### Requirements
- A Mac or Windows PC running AltServer.
- iPhone or iPad with iOS 12.2 or later.
- Both devices must be on the same WiFi network for automatic refresh.

### Installation Steps

1.  **Install AltServer**: Download and install AltServer from [altstore.io](https://altstore.io) on your computer.
2.  **Install AltStore on iOS**: Connect your iPhone to your computer, open AltServer on your computer, and select "Install AltStore" → (Your iPhone).
3.  **Trust Developer**: On your iPhone, go to `Settings → General → VPN & Device Management` and trust the certificate associated with your Apple ID.
4.  **Install the App**: Download the `.ipa` file from the [Downloads page](download.html), then open it within the AltStore app on your iPhone to begin installation.

> **Note:** For AltStore to automatically refresh your apps, AltServer must be running on your computer and connected to the same WiFi network as your iPhone.

---

## Method 2: Sideloadly

Sideloadly is a popular alternative that works over a USB connection.

### Quick Steps

1.  **Download Sideloadly**: Get the app from [sideloadly.io](https://sideloadly.io).
2.  **Connect iPhone**: Connect your iPhone to your computer via USB.
3.  **Load IPA**: Drag the `.ipa` file into Sideloadly, enter your Apple ID, and click "Start".
4.  **Trust Developer**: Trust the certificate in your iPhone's settings as with AltStore.

> **Note:** You must manually re-install the app every 7 days by repeating these steps.

---

## Method 3: TrollStore (iOS 14.0 - 16.6.1)

TrollStore uses a system vulnerability to permanently sign apps, so they never expire. This method only works on specific, unpatched iOS versions.

### Compatibility
- **Supported**: iOS 14.0-15.4.1, 16.0-16.1.2, and some other specific versions.
- **Not Supported**: iOS 16.7 and newer.

> Check the official [TrollStore GitHub](https://github.com/opa334/TrollStore) for detailed compatibility and installation instructions.

---

## 🔧 Troubleshooting

- **"Unable to Verify App"**: Make sure you have trusted the developer certificate in your iPhone's settings.
- **"Maximum Number of Apps Installed"**: A free Apple ID only allows for 3 sideloaded apps to be active at one time.
- **AltStore Refresh Fails**: Ensure AltServer is running on your computer and both devices are on the same WiFi network.

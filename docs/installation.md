---
layout: default
title: Installation
nav_order: 3
---

# 🛠️ Installation Guide

This guide provides detailed installation instructions for all supported platforms.

---

## 📱 iOS & iPadOS Installation (AltStore Method)

This is the recommended method for installing the app on iPhone and iPad.

### Prerequisites
- An iPhone or iPad running iOS 26 Beta or later.
- A computer running AltServer.
- The latest `.ipa` file from our [**Downloads page**](download.html).

### Step-by-Step Instructions

1.  **Download the IPA**: Grab the latest `mks-iptv.ipa` from the [Downloads page](download.html).
2.  **Install with AltStore**: Open the `.ipa` file on your iOS device and choose to open it with AltStore.
3.  **Trust the Certificate**: After installation, navigate to `Settings → General → VPN & Device Management` and trust the certificate associated with your Apple ID.

> For a more detailed walkthrough, see the [official AltStore documentation](https://altstore.io).

---

## 💻 macOS Installation

Installing on a Mac is straightforward.

### Prerequisites
- A Mac running macOS 26 Beta or later.
- The latest `.zip` file for Apple Silicon from our [**Downloads page**](download.md).

### Step-by-Step Instructions

1.  **Download the App**: Get the `.zip` file from the [Downloads page](download.md).
2.  **Unzip the File**: Double-click the downloaded `.zip` file to extract the application.
3.  **Move to Applications**: Drag the `MKS-IPTV-App.app` file into your `/Applications` folder.
4.  **First Launch**: Right-click the app icon and select "Open". You may need to confirm that you want to run an application from an unidentified developer.

---

## 📺 tvOS Installation (Xcode Required)

Installing on tvOS requires a Mac with Xcode.

### Prerequisites
- An Apple TV running tvOS 26 Beta.
- A Mac with **Xcode 16 Beta** installed.
- An Apple Developer Account (a free account is sufficient).
- The project source code (cloned from GitHub).

### Step-by-Step Instructions

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/MKS2508/MKS-IPTV-App.git
    cd MKS-IPTV-App
    ```
2.  **Connect your Apple TV**: Connect the Apple TV to your Mac using a USB-C cable.
3.  **Open in Xcode**: Open the `.xcodeproj` file in Xcode.
4.  **Select the Target**: Choose the `mks-multiplataforma-tvos-iptv` scheme and your connected Apple TV as the target device.
5.  **Build and Deploy**: Click the "Run" button (▶) in Xcode to build and install the app on your Apple TV.

---

## 💬 Troubleshooting & Support

If you encounter any issues during installation, please:

- Double-check the system requirements on the [Downloads page](download.md).
- Open an issue on our [**GitHub Issues page**](https://github.com/MKS2508/MKS-IPTV-App/issues).
- Start a thread on our [**Discussions page**](https://github.com/MKS2508/MKS-IPTV-App/discussions).

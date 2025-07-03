---
layout: default
title: Downloads
nav_order: 2
---

# 📥 Downloads

Download the latest version of MKS-IPTV-App for your platform. All builds are compiled directly from the source in our private repository.

## Latest Release: v1.0 Beta

<div class="download-grid">
  <div class="download-card">
    <h3>📱 iOS & iPadOS</h3>
    <p>Requires iOS 26 Beta or later.</p>
    <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/ios_pre_mks-multiplatform-iptv.ipa" class="btn">Download IPA</a>
    <a href="installation.md#ios-installation-altstore-method" class="btn-secondary">Installation Guide</a>
  </div>
  <div class="download-card">
    <h3>💻 macOS</h3>
    <p>Requires macOS 26 Beta or later.</p>
    <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/mac-os-arm64_pre_mks-multiplatform-iptv.app.zip" class="btn">Download for Apple Silicon</a>
    <a href="installation.md#macos-installation" class="btn-secondary">Installation Guide</a>
  </div>
  <div class="download-card">
    <h3>📺 tvOS</h3>
    <p>Requires tvOS 26 Beta & Xcode.</p>
    <a href="installation.md#tvos-installation" class="btn">Build From Source Guide</a>
  </div>
</div>

---

## ⚙️ System Requirements

| Platform | Minimum Version |
|:---|:---|
| **iOS / iPadOS** | iOS 26 Beta |
| **macOS** | macOS 26 Beta |
| **tvOS** | tvOS 26 Beta |

> **Note:** An Apple Developer Account may be required for installation on some platforms.

---

## 📦 Previous Versions

All previous releases are available on our [**GitHub Releases**](https://github.com/MKS2508/MKS-IPTV-App/releases) page. You can find older builds and review changelogs there.

---

<style>
.download-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
  gap: 20px;
  margin: 30px 0;
}

.download-card {
  border: 1px solid #4a4a4a;
  border-radius: 8px;
  padding: 25px;
  text-align: center;
  background: #1a1a1a;
  transition: transform 0.2s, box-shadow 0.2s;
}

.download-card:hover {
  transform: translateY(-5px);
  box-shadow: 0 0 25px rgba(75, 200, 29, 0.5);
  border-color: #4BC51D;
}

.download-card h3 {
  margin-top: 0;
  color: #4BC51D;
}

.download-card p {
  margin-bottom: 20px;
}

.download-card .btn, .download-card .btn-secondary {
  display: block;
  margin: 10px auto;
  padding: 12px 20px;
  border-radius: 5px;
  text-decoration: none;
  font-weight: bold;
}

.btn {
  background-color: #4BC51D;
  color: #ffffff;
}

.btn-secondary {
  background-color: transparent;
  color: #cccccc;
  border: 1px solid #4a4a4a;
}
</style>

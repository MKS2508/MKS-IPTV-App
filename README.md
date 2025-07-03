<div align="center">
  <a href="https://github.com/MKS2508/MKS-IPTV-App">
    <img src="docs/imgs/banner3.webp" alt="MKS-IPTV-App Banner" width="800"/>
  </a>
  <h1>MKS-IPTV-App</h1>
  <p><strong>A native, multiplatform IPTV client for the Apple ecosystem, built with Swift 6 & SwiftUI.</strong></p>
</div>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-v1.0--beta-blueviolet?style=for-the-badge">
  <img alt="Platform" src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS-4BC51D?style=for-the-badge">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift">
  <img alt="License" src="https://img.shields.io/github/license/MKS2508/MKS-IPTV-App?style=for-the-badge&color=lightgrey">
  <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/MKS2508/MKS-IPTV-App?include_prereleases&style=for-the-badge&color=blue&logo=github">
  </a>
</p>

> [!NOTE]
> This repository contains the documentation, build artifacts, and installation guides for the MKS-IPTV-App. The Swift source code is maintained in a private repository.

---

<details open>
<summary><h2>🇬🇧 English Documentation</h2></summary>
<br>

This application provides comprehensive IPTV streaming capabilities including live TV, video-on-demand (VOD), and advanced download management across Apple's ecosystem, featuring an early adoption of iOS/macOS/tvOS 26 Beta with Liquid Glass design patterns.

### 📥 Downloads & Installation

| Platform | Download | Installation Guide |
|----------|----------|--------------------|
| **iOS** | [Download IPA](https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/ios_pre_mks-multiplatform-iptv.ipa) | [AltStore Guide](./build/ios/INSTALL-WITH-ALTSTORE.md) |
| **macOS** | [Download .zip](https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/mac-os-arm64_pre_mks-multiplatform-iptv.app.zip) | [See Instructions](#-macos-installation) |
| **tvOS** | Build from source | [Developer Guide](#-tvos-installation) |

> **Note**: All official releases are available on the [**Releases page**](https://github.com/MKS2508/MKS-IPTV-App/releases). For alternative installation methods, see the [TestFlight Guide](docs/TestFlight-Distribution-Guide.md) or the [iOS Free Installation Guide](docs/iOS-Free-Installation-Guide.md).

### 🚀 Core Features

- **Native Live TV Streaming**: Real-time playback using `StreamManager` and `AVPlayer`.
- **Advanced Download System**: Local downloads with integrated HTTP server for streaming and progress tracking.
- **Smart Stream Management**: Automatic redirect resolution and optimized headers for IPTV services.
- **iOS 26 Liquid Glass Navigation**: Early implementation of Apple's newest design patterns.
- **macOS TouchBar Support**: Native controls for categories, search, and playback.
- **MOV Conversion**: Automatic conversion to `.MOV` for optimal AirPlay and Apple TV integration.

### 🛠️ Technical Architecture

- **Language**: Swift 6.0 with modern concurrency (async/await).
- **Frameworks**: SwiftUI, AVKit, Network framework.
- **Architecture**: MVVM with an Actor-based concurrency model.
- **Platform Support**: iOS 26+, macOS 26+, tvOS 26+.

### 📸 Screenshots

<details>
<summary>Click to view macOS Screenshots</summary>

| Download Manager | Download Modal |
| :---: | :---: |
| ![Downloads Section](./docs/imgs/v0.0.1-alpha/macos/DownloadsSection_1.png) | ![Download Modal](./docs/imgs/v0.0.1-alpha/macos/download_modal.png) |
| **Liquid Glass Navigation** | **Series Detail View** |
| ![Liquid Glass Navigation](./docs/imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png) | ![Series Detail](./docs/imgs/v0.0.1-alpha/macos/seriesdetail_1.png) |

</details>

### 📈 Feature Status

<details>
<summary>Click to view Feature Roadmap</summary>

#### ✅ **Production Ready**
- [x] Live TV Streaming
- [x] Download Management
- [x] Cross-Platform Navigation
- [x] iOS 26 Beta Liquid Glass
- [x] macOS TouchBar Integration
- [x] Real-time Search & Filtering

#### 🔜 **Next Release (v1.1)**
- [ ] VOD Streaming Integration
- [ ] Enhanced AirPlay Support
- [ ] Background Download Support
- [ ] Favorites System

#### 📋 **Future Roadmap (v1.2+)**
- [ ] Multiple Playback Engines (AVPlayer/VLC/FFmpeg)
- [ ] Offline Playback Mode
- [ ] Advanced Content Filtering
- [ ] Subtitle Management

</details>

### 🏗️ Build & Installation

<details>
<summary>Click to view Build & Installation Instructions</summary>

#### **Development Requirements**
- Xcode 16 Beta
- macOS 15 Beta+
- Swift 6.0
- Apple Developer Account

#### **Build Commands**
```bash
# macOS Build
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Debug

# iOS Build (Archive + Export)
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Release -archivePath build/ios/mks-iptv.xcarchive archive

# tvOS Build
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplataforma-tvos-iptv -configuration Debug
```

#### **End User Installation**

##### **iOS (AltStore Method)**
1. Download the `.ipa` file from the [Releases page](https://github.com/MKS2508/MKS-IPTV-App/releases/latest).
2. Install using AltStore following the [**detailed installation guide**](./build/ios/INSTALL-WITH-ALTSTORE.md).
3. Trust the developer certificate in `Settings → General → VPN & Device Management`.

##### **macOS Installation**
1. Download the `.zip` file from Releases and unzip it.
2. Drag the `.app` bundle to your `/Applications` folder.
3. Right-click the app and select "Open", then accept the "unidentified developer" prompt.

##### **tvOS Installation**
- Requires Xcode installation with an Apple Developer account.
- Connect Apple TV via USB-C and deploy the build through Xcode.

</details>

### 🤝 Contributing

This project is primarily a personal learning endeavor, but contributions are welcome. Please follow the standard `Fork -> Branch -> PR` workflow. Ensure changes are tested across all platforms and adhere to the existing MVVM architecture and Swift 6 concurrency patterns.

</details>

---

<details>
<summary><h2>🇪🇸 Documentación en Español</h2></summary>
<br>

Esta aplicación ofrece capacidades completas de streaming IPTV, incluyendo TV en vivo, vídeo bajo demanda (VOD) y un sistema de descargas avanzado para todo el ecosistema de Apple, destacando por la adopción temprana del diseño Liquid Glass de iOS/macOS/tvOS 26.

### 📥 Descargas e Instalación

| Plataforma | Descarga | Guía de Instalación |
|------------|----------|---------------------|
| **iOS** | [Descargar IPA](https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/ios_pre_mks-multiplatform-iptv.ipa) | [Guía AltStore](./build/ios/INSTALL-WITH-ALTSTORE.md) |
| **macOS** | [Descargar .zip](https://github.com/MKS2508/MKS-IPTV-App/releases/download/v1.0.0-alpha/mac-os-arm64_pre_mks-multiplatform-iptv.app.zip) | [Ver Instrucciones](#-instalación-en-macos) |
| **tvOS** | Compilar desde código | [Guía para Desarrolladores](#-instalación-en-tvos) |

> **Nota**: Todas las versiones oficiales están en la [**página de Releases**](https://github.com/MKS2508/MKS-IPTV-App/releases). Para métodos alternativos, consulta la [Guía de TestFlight](docs/TestFlight-Distribution-Guide.md) o la [Guía de Instalación Gratuita para iOS](docs/iOS-Free-Installation-Guide.md).

### 🚀 Características Principales

- **Streaming de TV en Vivo Nativo**: Reproducción en tiempo real con `StreamManager` y `AVPlayer`.
- **Sistema de Descargas Avanzado**: Descargas locales con servidor HTTP integrado para streaming y seguimiento del progreso.
- **Gestión Inteligente de Streams**: Resolución automática de redirecciones y cabeceras optimizadas.
- **Navegación Liquid Glass de iOS 26**: Implementación temprana de los nuevos patrones de diseño de Apple.
- **Soporte para TouchBar en macOS**: Controles nativos para categorías, búsqueda y reproducción.
- **Conversión a MOV**: Conversión automática a `.MOV` para una integración óptima con AirPlay y Apple TV.

### 🛠️ Arquitectura Técnica

- **Lenguaje**: Swift 6.0 con concurrencia moderna (async/await).
- **Frameworks**: SwiftUI, AVKit, Network.
- **Arquitectura**: MVVM con un modelo de concurrencia basado en Actores.
- **Soporte de Plataformas**: iOS 26+, macOS 26+, tvOS 26+.

### 📸 Capturas de Pantalla

<details>
<summary>Haz clic para ver las capturas de macOS</summary>

| Gestor de Descargas | Modal de Descarga |
| :---: | :---: |
| ![Sección de Descargas](./docs/imgs/v0.0.1-alpha/macos/DownloadsSection_1.png) | ![Modal de Descarga](./docs/imgs/v0.0.1-alpha/macos/download_modal.png) |
| **Navegación Liquid Glass** | **Vista de Detalle de Serie** |
| ![Navegación Liquid Glass](./docs/imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png) | ![Detalle de Serie](./docs/imgs/v0.0.1-alpha/macos/seriesdetail_1.png) |

</details>

### 📈 Estado de las Funcionalidades

<details>
<summary>Haz clic para ver el Roadmap de Funcionalidades</summary>

#### ✅ **Listo para Producción**
- [x] Streaming de TV en Vivo
- [x] Gestión de Descargas
- [x] Navegación Multiplataforma
- [x] Liquid Glass de iOS 26 Beta
- [x] Integración con TouchBar de macOS
- [x] Búsqueda y Filtrado en Tiempo Real

#### 🔜 **Próxima Versión (v1.1)**
- [ ] Integración de Streaming VOD
- [ ] Soporte Mejorado para AirPlay
- [ ] Soporte para Descargas en Segundo Plano
- [ ] Sistema de Favoritos

#### 📋 **Roadmap Futuro (v1.2+)**
- [ ] Múltiples Motores de Reproducción (AVPlayer/VLC/FFmpeg)
- [ ] Modo de Reproducción Offline
- [ ] Filtrado Avanzado de Contenido
- [ ] Gestión de Subtítulos

</details>

### 🏗️ Compilación e Instalación

<details>
<summary>Haz clic para ver las Instrucciones de Compilación e Instalación</summary>

#### **Requisitos de Desarrollo**
- Xcode 16 Beta
- macOS 15 Beta+
- Swift 6.0
- Cuenta de Desarrollador de Apple

#### **Comandos de Compilación**
```bash
# Compilar para macOS
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Debug

# Compilar para iOS (Archivar y Exportar)
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplatform-iptv -configuration Release -archivePath build/ios/mks-iptv.xcarchive archive

# Compilar para tvOS
xcodebuild -project mks-multiplatform-iptv.xcodeproj -scheme mks-multiplataforma-tvos-iptv -configuration Debug
```

#### **Instalación para Usuario Final**

##### **Instalación en iOS (Método AltStore)**
1. Descarga el archivo `.ipa` desde la [página de Releases](https://github.com/MKS2508/MKS-IPTV-App/releases/latest).
2. Instálalo usando AltStore, siguiendo la [**guía de instalación detallada**](./build/ios/INSTALL-WITH-ALTSTORE.md).
3. Confía en el certificado de desarrollador en `Ajustes → General → VPN y Gestión de Dispositivos`.

##### **Instalación en macOS**
1. Descarga el archivo `.zip` de la página de Releases y descomprímelo.
2. Arrastra la aplicación `.app` a tu carpeta de `/Aplicaciones`.
3. Haz clic derecho en la app, selecciona "Abrir" y acepta el aviso de "desarrollador no identificado".

##### **Instalación en tvOS**
- Requiere instalación con Xcode y una cuenta de Desarrollador de Apple.
- Conecta el Apple TV por USB-C y despliega la compilación a través de Xcode.

</details>

### 🤝 Contribuciones

Este proyecto es principalmente un esfuerzo de aprendizaje personal, pero las contribuciones son bienvenidas. Por favor, sigue el flujo de trabajo estándar `Fork -> Branch -> PR`. Asegúrate de que los cambios se prueben en todas las plataformas y se adhieran a la arquitectura MVVM y los patrones de concurrencia de Swift 6 existentes.

</details>

---

<div align="center">
  <p><em>Licenciado bajo la <strong>GNU General Public License v3.0</strong>.</em></p>
  <p>
    <a href="https://github.com/MKS2508"><strong>Desarrollador: @MKS2508</strong></a> &nbsp;&middot;&nbsp;
    <a href="https://github.com/MKS2508/MKS-IPTV-App/issues">Reportar un Bug</a> &nbsp;&middot;&nbsp;
    <a href="https://github.com/MKS2508/MKS-IPTV-App/discussions">Solicitar una Característica</a>
  </p>
  <br>
  <p><em>Construido con ❤️ usando Swift 6, SwiftUI, y mucho ☕️</em></p>
</div>
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

<table>
  <tr>
    <td valign="top">
      <h3>A Powerful, Native IPTV Experience</h3>
      <p>MKS-IPTV-App is a client built from the ground up for the Apple ecosystem. It provides a seamless, high-performance experience for streaming IPTV content, complete with modern features and a design that feels right at home on iOS, macOS, and tvOS.</p>
      <ul>
        <li><strong> Native Performance:</strong> Built with Swift & SwiftUI for a fast, responsive UI.</li>
        <li><strong>📥 Offline Downloads:</strong> Save content directly to your device for offline viewing.</li>
        <li><strong>🎨 Modern "Liquid Glass" UI:</strong> Features the latest design patterns from Apple.</li>
        <li><strong>🔗 Smart Stream Handling:</strong> Automatically manages redirects and proxies for smooth playback.</li>
      </ul>
    </td>
    <td width="500" align="center">
      <img src="./docs/imgs/v0.0.1-alpha/macos/listview_liquidglasstopbar.png" alt="Liquid Glass Navigation" />
    </td>
  </tr>
</table>

## 📥 Get the App

Download the latest version for your platform. For installation help, see the guides in the documentation below.

| Platform | Download | Installation Guide |
|:---|:---|:---|
| **iOS & iPadOS** | <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest/download/mks-iptv.ipa">**Download IPA**</a> | [AltStore Guide](./docs/iOS-Free-Installation-Guide.md) |
| **macOS** | <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest/download/mks-iptv-macos-arm64.zip">**Download for Apple Silicon**</a> | [See Instructions](#-macos-installation) |
| **tvOS** | Build from source | [Developer Guide](#-tvos-installation) |

> [!NOTE]
> This repository contains the documentation and build artifacts. The source code is in a private repository.

<p align="center">
  <!-- Stars -->
  <a href="https://github.com/MKS2508/MKS-IPTV-App/stargazers"><img src="https://img.shields.io/github/stars/MKS2508/MKS-IPTV-App?style=social" alt="Stars"></a>
  <!-- Forks -->
  <a href="https://github.com/MKS2508/MKS-IPTV-App/network/members"><img src="https://img.shields.io/github/forks/MKS2508/MKS-IPTV-App?style=social" alt="Forks"></a>
  <!-- Watchers -->
  <a href="https://github.com/MKS2508/MKS-IPTV-App/watchers"><img src="https://img.shields.io/github/watchers/MKS2508/MKS-IPTV-App?style=social" alt="Watchers"></a>
  <!-- Downloads -->
  <a href="https://github.com/MKS2508/MKS-IPTV-App/releases/latest"><img src="https://img.shields.io/github/downloads/MKS2508/MKS-IPTV-App/total?style=social&logo=github" alt="Total Downloads"></a>
  <!-- Follow -->
  <a href="https://github.com/MKS2508"><img src="https://img.shields.io/github/followers/MKS2508?style=social" alt="Follow @MKS2508"></a>
</p>

<img src="https://i.imgur.com/f0I61D8.gif" width="100%">

<details>
<summary><h3>👩‍💻 Technical Documentation (English)</h3></summary>
<br>

### 🚀 Core Features

- **Native Live TV Streaming**: Real-time playback using `StreamManager` and `AVPlayer`.
- **Advanced Download System**: Local downloads with integrated HTTP server for streaming and progress tracking.
- **Smart Stream Management**: Automatic redirect resolution and optimized headers for IPTV services.
- **iOS 26 Liquid Glass Navigation**: Early implementation of Apple's newest design patterns.
- **macOS TouchBar Support**: Native controls for categories, search, and playback.
- **MOV Conversion**: Automatic conversion to `.MOV` for optimal AirPlay and Apple TV integration.

### 🛠️ Tech Stack

| Logo | Technology | Description |
| :---: | :--- | :--- |
| <img src="https://img.shields.io/badge/-Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift"> | **Swift 6.0** | Core application language, using modern concurrency (async/await). |
| <img src="https://img.shields.io/badge/-SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"> | **SwiftUI** | Framework for building the user interface across all Apple platforms. |
| <img src="https://img.shields.io/badge/-Actors-4BC51D?style=for-the-badge" alt="Actors"> | **Actor Model** | For safe and structured concurrency, preventing data races. |
| <img src="https://img.shields.io/badge/-MVVM-F7DF1E?style=for-the-badge" alt="MVVM"> | **MVVM** | Architectural pattern for a clean separation of concerns. |
| <img src="https://img.shields.io/badge/-Network-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Network"> | **Network.framework** | Apple's native framework for all networking tasks. |

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
2. Install using AltStore following the [**detailed installation guide**](./docs/iOS-Free-Installation-Guide.md).
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
<summary><h3>👩‍💻 Documentación Técnica (Español)</h3></summary>
<br>

### 🚀 Características Principales

- **Streaming de TV en Vivo Nativo**: Reproducción en tiempo real con `StreamManager` y `AVPlayer`.
- **Sistema de Descargas Avanzado**: Descargas locales con servidor HTTP integrado para streaming y seguimiento del progreso.
- **Gestión Inteligente de Streams**: Resolución automática de redirecciones y cabeceras optimizadas.
- **Navegación Liquid Glass de iOS 26**: Implementación temprana de los nuevos patrones de diseño de Apple.
- **Soporte para TouchBar en macOS**: Controles nativos para categorías, búsqueda y reproducción.
- **Conversión a MOV**: Conversión automática a `.MOV` para una integración óptima con AirPlay y Apple TV.

### 🛠️ Stack Tecnológico

| Logo | Tecnología | Descripción |
| :---: | :--- | :--- |
| <img src="https://img.shields.io/badge/-Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift"> | **Swift 6.0** | Lenguaje principal de la aplicación, usando concurrencia moderna (async/await). |
| <img src="https://img.shields.io/badge/-SwiftUI-007AFF?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"> | **SwiftUI** | Framework para construir la interfaz de usuario en todas las plataformas de Apple. |
| <img src="https://img.shields.io/badge/-Actors-4BC51D?style=for-the-badge" alt="Actors"> | **Modelo de Actores** | Para una concurrencia segura y estructurada, previniendo "data races". |
| <img src="https://img.shields.io/badge/-MVVM-F7DF1E?style=for-the-badge" alt="MVVM"> | **MVVM** | Patrón de arquitectura para una clara separación de responsabilidades. |
| <img src="https://img.shields.io/badge/-Network-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Network"> | **Network.framework** | Framework nativo de Apple para todas las tareas de red. |

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
2. Instálalo usando AltStore, siguiendo la [**guía de instalación detallada**](./docs/iOS-Free-Installation-Guide.md).
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
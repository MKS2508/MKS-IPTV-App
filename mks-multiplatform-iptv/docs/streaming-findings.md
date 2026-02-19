# Streaming Libraries Research - MKS-IPTV-App

> Fecha: 17 Feb 2026 | Proyecto: mks-multiplatform-iptv | Plataformas: iOS 26, macOS 26, tvOS 26

---

## Tabla de contenidos

1. [Contexto y problema](#1-contexto-y-problema)
2. [Intentos previos (fallidos)](#2-intentos-previos-fallidos)
3. [Estado actual del codebase](#3-estado-actual-del-codebase)
4. [Opciones evaluadas](#4-opciones-evaluadas)
   - [4.1 KSPlayer](#41-ksplayer)
   - [4.2 VLCKit / MobileVLCKit](#42-vlckit--mobilevlckit)
   - [4.3 MPVKit (libmpv)](#43-mpvkit-libmpv)
   - [4.4 mdk-sdk](#44-mdk-sdk)
   - [4.5 AVPlayer + Transmux local](#45-avplayer--transmux-local-mkv-to-fmp4-hls)
5. [Tabla comparativa](#5-tabla-comparativa)
6. [Estrategia recomendada](#6-estrategia-recomendada)
7. [Decision pendiente: licencia](#7-decision-pendiente-licencia)
8. [Archivos relevantes del proyecto](#8-archivos-relevantes-del-proyecto)
9. [Pasos para implementar](#9-pasos-para-implementar)
10. [Referencias y fuentes](#10-referencias-y-fuentes)

---

## 1. Contexto y problema

MKS-IPTV es un cliente IPTV nativo Apple que conecta con servidores Xtream Codes API para reproducir peliculas, series y canales en directo. Los streams IPTV vienen en formatos variados:

- **VOD (peliculas/series)**: Tipicamente MKV con H.264/H.265 + AAC/AC3/DTS
- **Live TV**: HLS (.m3u8), MPEG-TS (.ts) sobre HTTP, RTSP, o HTTP progressive
- **URLs directas**: `{baseURL}/{movie|series|live}/{username}/{password}/{id}.{extension}`

### El problema fundamental

**AVPlayer (el reproductor nativo de Apple) no soporta MKV.** Solo reproduce MP4, MOV, M4V y HLS (M3U8).

Consecuencias:
- No se puede reproducir VOD en MKV directamente
- Algunos live streams en TS/MKV tampoco funcionan
- PiP (Picture-in-Picture) y AirPlay **solo funcionan con AVPlayer**, no con reproductores alternativos que renderizan por Metal/OpenGL

### Requisitos del reproductor

| Requisito | Prioridad | Notas |
|-----------|-----------|-------|
| MKV playback | Critica | La mayoria de VOD viene en MKV |
| PiP en iOS | Alta | Multitasking mientras se ve contenido |
| AirPlay | Media-Alta | Enviar a Apple TV/AirPlay speakers |
| Live TV (HLS/TS/RTSP) | Critica | Core del producto |
| HTTP reconnect/keep-alive | Critica | Streams IPTV cortan conexion frecuentemente |
| Range requests / seeking | Alta | Seeking en VOD |
| Custom HTTP headers | Alta | User-Agent, cookies, referer para algunos servers |
| Subtitulos embebidos | Media | SRT, SSA/ASS dentro de MKV |
| Multiple audio tracks | Media | Idiomas alternativos en MKV |
| tvOS soporte | Media | Apple TV como plataforma secundaria |
| SwiftUI integration | Alta | La app usa SwiftUI |

---

## 2. Intentos previos (fallidos)

Se intentaron **5 servidores HTTP proxy / transmuxing** diferentes y **4 implementaciones de player**. Todos eliminados o abandonados.

### 2.1 Players intentados

| Player | Estado | Problema |
|--------|--------|----------|
| **AVPlayer** (nativo) | Activo, unico funcional | Solo MP4/M4V/MOV/M3U8. No MKV |
| **KSPlayer** | Stub `#if canImport` | Modulo nunca instalado via SPM |
| **VLCKit** | Stub `#if canImport(VLCKitSPM)` | SPM no resolvio. CocoaPods solo macOS en Podfile |
| **FFmpegKit** | Comentado/abandonado | Licencia comercial para iOS. Proyecto original archivado Jun 2025 |

### 2.2 Proxies HTTP eliminados (git status: deleted)

Todos intentaban resolver: AVPlayer no soporta MKV -> transmuxing MKV a MP4 en tiempo real via servidor HTTP local.

| Archivo (eliminado) | Enfoque | Problema |
|---------------------|---------|----------|
| `HTTPStreamServer.swift` | `NWListener` (Network framework) + transmuxing | Streaming chunked poco fiable |
| `HTTPStreamProxyServer.swift` | Python HTTP server + FFmpeg process (~350 lineas) | Range requests y seeking fallaban |
| `DirectHTTPProxy.swift` | Python + pipe directo FFmpeg | Sin range requests |
| `AVPlayerCompatibleProxy.swift` | Python + conversion a archivo temporal | Modelo file-based incompatible con streaming |
| `SimpleHTTPStreamServer.swift` | `NWListener` simplificado | Solo debug, no produccion |

### 2.3 Leccion aprendida

El enfoque de "FFmpeg externo como proceso + servidor HTTP Python" es fragil y no escala. La solucion correcta es usar una libreria que **integre FFmpeg como framework nativo** (KSPlayer, VLCKit) o hacer transmuxing a fMP4 HLS con FFmpeg bundled.

---

## 3. Estado actual del codebase

### Arquitectura de players

```
IPTVDownloader/Core/Player/
  PlayerProtocol.swift          # Protocol VideoPlayerProtocol
  PlayerFactory.swift           # Factory pattern, auto-seleccion
  AVPlayerImplementation.swift  # UNICO FUNCIONAL - Nativo Apple
  KSPlayerImplementation.swift  # Stub con #if canImport(KSPlayer)
  VLCPlayerImplementation.swift # Stub con #if canImport(VLCKitSPM)
  FFmpegPlayerImplementation.swift # Simplificado a wrapper de AVPlayer
```

### Utilidades activas

```
IPTVDownloader/Utils/
  FFProbeUtilities.swift          # Analisis de streams (solo macOS, usa /opt/homebrew/bin/ffprobe)
  FFmpegTransmuxer.swift          # MKV->MP4 via FFmpeg process (existe pero no se llama)
  StreamCompatibilityHandler.swift # Detecta compatibilidad, simplificado a devolver URL original
  VLCHelper.swift                 # Detecta VLC externo instalado, abre URLs en VLC app
```

### Dependencias actuales

```
Podfile: VLCKit ~> 3.6.0 (solo macOS, NO instalado en iOS)
SPM: Ninguna dependencia de player
```

### PlayerFactory flow actual

```
URL -> PlayerFactory.createPlayer(for:)
  -> Si formato nativo (MP4/M4V/MOV/M3U8) -> AVPlayerImplementation
  -> Si MKV/TS y macOS -> FFmpegPlayerImplementation (wrapper de AVPlayer, sin transmuxing real)
  -> Fallback -> AVPlayerImplementation (falla silenciosamente con MKV)
```

---

## 4. Opciones evaluadas

### 4.1 KSPlayer

**Repositorio**: https://github.com/kingslay/KSPlayer
**Ultimo commit**: 28 Ene 2026 | **Stars**: 1,468 | **Issues abiertas**: 11

#### Arquitectura dual-engine

KSPlayer tiene dos motores internos que se seleccionan automaticamente:

- **KSAVPlayer**: Wrapper sobre AVPlayer nativo. Soporta MP4/HLS. PiP y AirPlay nativos.
- **KSMEPlayer**: Motor FFmpeg propio. Soporta MKV, TS, AVI, WebM, RTSP, etc. PiP via `AVSampleBufferDisplayLayer`. **Sin AirPlay.**

#### Integracion SPM

```swift
// Package.swift o Xcode > Add Package Dependencies
.package(url: "https://github.com/kingslay/KSPlayer.git", .branch("main"))
```

- Solo soporta `.branch("main")`, no hay tags semver estables
- Descarga binarios FFmpeg precompilados (~grande, puede tardar)
- Dependencia: `kingslay/FFmpegKit` con xcframeworks para todas las plataformas

#### Configuracion basica

```swift
import KSPlayer

// Habilitar motor FFmpeg para MKV
KSOptions.secondPlayerType = KSMEPlayer.self

// SwiftUI
KSVideoPlayerView(url: streamURL, options: KSOptions())
```

#### PiP

- **KSAVPlayer**: PiP nativo via `AVPictureInPictureController(playerLayer:)` - iOS/tvOS
- **KSMEPlayer**: PiP via `AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer:playbackDelegate:)` - requiere iOS 15+, tvOS 15+, macOS 12+
- **macOS**: PiP **NO soportado** (confirmado por el desarrollador, Dic 2024)
- PiP con subtitulos: solo version LGPL de pago

#### AirPlay

- **KSAVPlayer**: AirPlay nativo completo (`allowsExternalPlayback`, `usesExternalPlaybackWhileExternalScreenIsActive`)
- **KSMEPlayer**: AirPlay **NO soportado** (`isExternalPlaybackActive` siempre retorna `false`). Renderiza por `AVSampleBufferDisplayLayer` que no se enruta a AirPlay

#### Live streaming / IPTV

| Protocolo | Soporte | Motor |
|-----------|---------|-------|
| HLS | SI | KSAVPlayer + KSMEPlayer |
| RTSP | SI | KSMEPlayer (FFmpeg) |
| RTMP | SI | KSMEPlayer (FFmpeg) |
| DASH | SI | KSMEPlayer (FFmpeg) |
| HTTP Progressive | SI | Ambos |
| SRT | SI | KSMEPlayer (libsrt bundled) |
| MPEG-TS | SI | KSMEPlayer (FFmpeg) |

Opciones para live streams:
```swift
// Auto-configurado en KSOptions.init()
formatContextOptions["reconnect"] = 1          // Auto-reconnect para TS
formatContextOptions["reconnect_streamed"] = 1 // Reconectar contenido streamed
formatContextOptions["scan_all_pmts"] = 1      // Deteccion de programas TS
```

HTTP headers custom:
```swift
let options = KSOptions()
options.appendHeader(["Referer": "https://server.com"])
options.userAgent = "IPTVClient/1.0"
options.setCookie([httpCookie])
```

#### Plataformas

| Plataforma | Min version | Estado |
|------------|-------------|--------|
| iOS | 13.0+ | Completo |
| macOS | 10.15+ | Completo |
| tvOS | 13.0+ | Completo (bugs reportados en tvOS 26) |
| visionOS | 1.0+ | Soportado |

#### Licencia

| Licencia | Coste | Implicacion |
|----------|-------|-------------|
| **GPL v3** (default) | Gratis | Tu app DEBE ser open-source bajo GPL |
| **LGPL** | De pago (contactar kingslay@icloud.com) | App cerrada permitida + features extra |
| **Comercial** | Negociable | Flexibilidad total |

Features exclusivas LGPL de pago:
- Dolby AC-4, AV1 HW decode, 8K/120fps
- PiP con subtitulos, dual subtitles
- ASS rendering completo (libass)
- FFmpeg 8.0 (vs 6.1 en GPL)
- Live streaming rewind
- Annex-B async HW decode (live)
- Memory cache para fast seek

#### Issues conocidas (Feb 2026)

- `#891`: Comportamiento raro en tvOS Apple TV
- `#890`: Build issues con ultima version de Xcode
- `#458`: Cambio lento de stream con AirPlay audio (abierto desde 2023)
- `#848`: Frame drops en apps IPTV (resuelto)
- `#888`: Problemas con live sources (resuelto)

#### Apps que lo usan

IPTV+, Snappier IPTV, APTV, homeTV, TracyPlayer (~12+ apps en App Store)

---

### 4.2 VLCKit / MobileVLCKit

**Repositorio oficial**: https://code.videolan.org/videolan/VLCKit
**GitHub mirror**: https://github.com/videolan/vlckit
**Version estable**: 3.7.2 (21 Ene 2026) | **Version alpha**: 4.0.0a18 (15 Dic 2025)

#### Integracion

**CocoaPods (oficial):**
```ruby
# iOS
pod 'MobileVLCKit', '~> 3.7.0'
# macOS
pod 'VLCKit', '~> 3.7.0'
# tvOS
pod 'TVVLCKit', '~> 3.7.0'
```

**SPM (community, funciona):**
```swift
// iOS only - MobileVLCKit-SPM (v3.7.2, Feb 2026, 38 releases)
.package(url: "https://github.com/MobileVLCKit-SPM/MobileVLCKit-SPM", from: "3.7.0")
// Variante lite sin dSYMs ni simulator: MobileVLCKit-SPM-Lite (~200MB vs ~1-2GB)

// Multi-plataforma (iOS/macOS/tvOS) pero version 3.5.1
.package(url: "https://github.com/tylerjonesio/vlckit-spm", from: "3.5.1")
```

**SPM oficial**: No disponible. Issue #302 abierta. Planeado para VLCKit 4.0.

#### MKV

Soporte completo via libVLC:
- Todos los codecs que VLC desktop soporta
- VideoToolbox HW accel para H.264/H.265
- Multiple audio tracks
- Subtitulos: SRT, SSA/ASS, WebVTT, bitmap, RTL, complex text
- v4.0 anade dual subtitle tracks simultaneos

#### PiP

- **v3.x**: NO soportado nativamente. VLCKit renderiza por su propio pipeline (OpenGL/Metal), no por AVPlayerLayer
- **v4.0 alpha**: PiP anadido via `AVPictureInPictureSampleBufferPlaybackDelegate` con `VLCPictureInPictureController`. Requiere iOS 15+
- **Estado**: v4.0 alpha inestable. Crashes reportados con RTSP+audio (#730)

#### AirPlay

- **NO soportado nativamente** en ninguna version
- Existe branch experimental `Airplay` en GitLab, no mergeado
- Workaround: transmuxar a formato nativo y handoff a AVPlayer

#### Live streaming / IPTV

| Protocolo | Soporte | Notas |
|-----------|---------|-------|
| HLS | SI | M3U8, adaptive bitrate |
| RTSP | SI | Regresion en 3.3.17/iOS14, arreglado |
| HTTP Progressive | SI | - |
| MPEG-TS | SI | HTTP, UDP, multicast |
| RTMP | SI | - |
| UDP/Multicast | SI | DVB signals |

Opciones IPTV (ya configuradas en tu VLCPlayerImplementation.swift):
```swift
"network-caching": 3000      // Buffer de red
"live-caching": 1000          // Cache live
"rtsp-caching": 2000          // Cache RTSP
"http-reconnect": true        // Auto-reconexion
"http-user-agent": "VLC/3.0"  // User-Agent custom
```

Problemas con Xtream Codes:
- Algunos servers no manejan bien range requests de VLCKit
- Flood protection puede activarse con reconexiones automaticas
- Connection limits por usuario pueden alcanzarse

#### SwiftUI

- VLCKit NO tiene SwiftUI nativo
- Wrapper community: [VLCUI](https://github.com/LePips/VLCUI) (MIT, v0.7.4, Sep 2025): `VLCVideoPlayer(url:)`
- Tu implementacion actual en `VLCPlayerImplementation.swift` ya tiene wrappers NSViewRepresentable/UIViewRepresentable correctos

#### Licencia

**LGPLv2.1** - la mas permisiva para App Store:
- Puede usarse en apps cerradas/comerciales
- Debe publicar modificaciones a VLCKit
- Debe informar al usuario que VLCKit esta embebido (Acknowledgments)
- Debate legal sobre relinking en dispositivos bloqueados (en practica, VLC iOS esta en App Store desde 2013 sin problemas legales)

#### Issues conocidas

- Simulator crash iOS 17.4+ (OpenGL, no afecta devices fisicos)
- OPUS audio regresion en 3.6.0 (usar 3.7.x)
- v4.0 alpha: crash con RTSP+audio
- tvOS: TS streams a veces inician solo-audio (requiere pause/resume)

#### tvOS

- TVVLCKit disponible via CocoaPods
- API identica a MobileVLCKit
- Focus navigation es responsabilidad de la app
- v4.0 unificara todos los frameworks en uno solo

---

### 4.3 MPVKit (libmpv)

**Repositorio principal**: https://github.com/mpvkit/MPVKit
**Swift bindings**: https://github.com/karelrooted/MPVKit

#### Resumen

mpv es el engine mas robusto para formatos raros. IINA (macOS) lo usa. Dos variantes:

| Variante | Enfoque | SwiftUI | Nota |
|----------|---------|---------|------|
| mpvkit/MPVKit | Build scripts + xcframeworks | C API only | "solo para aprender libmpv" segun autor |
| karelrooted/MPVKit | Swift bindings sobre libmpv | `MPVVideoPlayer` | API compatible con VLCUI |

#### Capacidades

- MKV: Completo via FFmpeg
- PiP: NO nativo (Metal rendering, no AVPlayerLayer)
- AirPlay: NO
- Live/IPTV: RTSP, HLS, HTTP via FFmpeg
- SPM: SI
- Licencia: **LGPLv3**

#### Limitaciones

- Metal support en mpv solo como patch no-oficial (PR #7857)
- iOS PiP requiere `AVSampleBufferDisplayLayer` que mpv no integra nativamente
- Mas complejo de integrar que KSPlayer
- Mantenimiento esporadico

#### Veredicto

No recomendado como player principal. Util como fallback para streams especialmente problematicos, similar a como IPTV+ lo usa junto a KSPlayer y VLC.

---

### 4.4 mdk-sdk

**Repositorio**: https://github.com/wang-bin/mdk-sdk
**Swift SPM**: https://github.com/wang-bin/swift-mdk

#### Resumen

SDK multimedia cross-platform del autor de QtAV. Usa FFmpeg internamente con rendering Metal.

- MKV: SI (Matroska demuxer explicito)
- PiP: NO nativo
- AirPlay: NO nativo
- Live/IPTV: HLS, RTSP, DASH
- SPM: SI via swift-mdk
- Features pro: HDR/DV rendering, Blackmagic RAW, VideoToolbox HW decode

#### Licencia

- Gratis para: open-source, no-comercial, Flutter, QtAV donors
- **Comercial**: De pago, por app, por plataforma
- NO es fully open-source (binarios precompilados)

#### Veredicto

Tecnicamente excelente pero licencia comercial es barrera. Sin PiP/AirPlay nativo. No recomendado salvo necesidad de codecs profesionales.

---

### 4.5 AVPlayer + Transmux local (MKV to fMP4 HLS)

#### Concepto

Este es el enfoque que usan Plex y Jellyfin:

1. Servidor HTTP local en el dispositivo (GCDWebServer en `localhost:PORT`)
2. FFmpeg transmuxea MKV a **fMP4 HLS** en tiempo real (sin re-encoding si codec es H.264/H.265)
3. AVPlayer consume segmentos HLS del localhost
4. Al ser AVPlayer nativo: **PiP + AirPlay gratis**

#### Ventajas

- Unica forma de tener MKV + AirPlay + PiP simultaneamente
- Sin problemas de licencia GPL (AVPlayer es de Apple)
- Funciona con el PlayerFactory existente (solo AVPlayerImplementation)

#### Limitaciones

- Requiere servidor HTTP local corriendo en el device
- Solo funciona si MKV contiene codecs que AVPlayer entiende (H.264, H.265, AAC)
- VP9, AV1 sin HW support requieren transcoding real (muy lento en iOS)
- `AVAssetResourceLoaderDelegate` es dificil de implementar correctamente
- Latencia inicial por generacion de primer segmento
- **Es exactamente lo que intentamos con los 5 proxies eliminados**, pero ahora KSPlayer trae FFmpeg bundled via SPM (no necesitas binarios externos)

#### Diferencia vs intentos anteriores

Los 5 proxies eliminados usaban:
- FFmpeg como proceso externo (`/opt/homebrew/bin/ffmpeg`)
- Python como servidor HTTP
- Solo macOS (FFmpeg no disponible como binario en iOS)

La diferencia ahora:
- KSPlayer/FFmpegKit provee FFmpeg como **framework nativo iOS**
- Se puede hacer transmuxing in-process (no spawn de procesos)
- Funciona en iOS, no solo macOS

#### Referencia

- [kevinjameshunt/AVPlayer-HTTP-Headers-Example](https://github.com/kevinjameshunt/AVPlayer-HTTP-Headers-Example) - patron local reverse proxy
- [Jared Sinclair - AVAssetResourceLoaderDelegate](https://jaredsinclair.com/2016/09/03/implementing-avassetresourceload.html) - guia de implementacion

---

## 5. Tabla comparativa

| Feature | KSPlayer | VLCKit 3.7 | VLCKit 4.0a | MPVKit | mdk-sdk | AVPlayer+Transmux |
|---------|----------|------------|-------------|--------|---------|-------------------|
| **MKV** | SI | SI | SI | SI | SI | SI* |
| **PiP iOS** | SI (15+) | NO | SI (inestable) | NO | NO | SI |
| **PiP macOS** | NO | NO | ? | NO | NO | SI |
| **AirPlay** | Solo nativo | NO | NO | NO | NO | SI |
| **Live IPTV** | Excelente | Bueno | Bueno | Bueno | Bueno | Parcial |
| **HTTP reconnect** | SI (auto) | SI (config) | SI | SI | SI | Manual |
| **TS streams** | SI | SI | SI | SI | SI | Via transmux |
| **Range requests** | SI (FFmpeg) | SI (libVLC) | SI | SI | SI | SI (AVPlayer) |
| **Custom headers** | SI | SI | SI | SI | SI | SI |
| **SwiftUI** | Nativo | Via VLCUI | Via VLCUI | Parcial | Manual | Nativo |
| **SPM** | SI (.branch) | Community | ? | SI | SI | N/A |
| **Licencia** | GPL/LGPL$ | LGPLv2.1 | LGPLv2.1 | LGPLv3 | Comercial | N/A |
| **Mantenimiento** | Activo (1 dev) | Activo (VideoLAN) | Alpha | Esporadico | Activo | DIY |
| **tvOS** | SI | SI | SI | SI | Problemas | SI |
| **Binary size** | Grande (FFmpeg) | Grande (libVLC) | Grande | Grande | Medio | Minimo** |

*Solo si codec interno es compatible con AVPlayer (H.264/H.265+AAC)
**Si usas FFmpegKit solo para transmux, el binary es mas pequeno que un player completo

---

## 6. Estrategia recomendada

### Opcion A: KSPlayer como engine unico (recomendada)

```
Stream -> detectar formato via KSOptions
  |
  +-- HLS/MP4/M3U8 -> KSAVPlayer (PiP + AirPlay nativos)
  |
  +-- MKV/TS/RTSP  -> KSMEPlayer (PiP si, AirPlay no)
```

**Pros**: Una sola dependencia, SwiftUI nativo, PiP en iOS, usado por 12+ apps IPTV
**Contras**: GPL (open-source tu app) o pagar LGPL. AirPlay solo con formatos nativos

### Opcion B: KSPlayer + transmux para AirPlay con MKV

```
Stream -> detectar formato
  |
  +-- HLS/MP4/M3U8 -> KSAVPlayer directo (PiP + AirPlay)
  |
  +-- MKV/TS con H.264/H.265 -> transmux fMP4 HLS via FFmpeg -> AVPlayer (PiP + AirPlay)
  |
  +-- MKV/TS con codecs raros -> KSMEPlayer (PiP si, AirPlay no)
```

**Pros**: AirPlay funciona con el 95%+ de streams MKV (la mayoria usa H.264/H.265)
**Contras**: Complejidad adicional del transmuxing local. Latencia inicial

### Opcion C: VLCKit 3.7 + AVPlayer (sin PiP en VLC)

```
Stream -> detectar formato
  |
  +-- HLS/MP4/M3U8 -> AVPlayerImplementation (PiP + AirPlay)
  |
  +-- MKV/TS/RTSP  -> VLCPlayerImplementation (sin PiP, sin AirPlay)
```

**Pros**: LGPL gratis, codigo VLC ya existe en el proyecto, maduro
**Contras**: Sin PiP ni AirPlay para MKV. Dos engines separados

### Opcion D: Hibrido KSPlayer + VLCKit fallback

```
Stream -> detectar formato
  |
  +-- HLS/MP4   -> KSAVPlayer (PiP + AirPlay)
  |
  +-- MKV/TS    -> KSMEPlayer (PiP, sin AirPlay)
  |
  +-- Fallback  -> VLCKit (si KSPlayer falla con stream especifico)
```

**Pros**: Maxima compatibilidad. Es como funciona IPTV+ (3 players)
**Contras**: Dos dependencias grandes, complejidad

---

## 7. Decision pendiente: licencia

Antes de implementar, decidir:

### Si la app sera open-source

-> KSPlayer GPL gratis. Sin restricciones. Opcion A o B.

### Si la app sera cerrada/comercial

| Opcion | Coste | Resultado |
|--------|-------|-----------|
| KSPlayer LGPL | De pago (contactar kingslay@icloud.com) | Mejor integracion |
| VLCKit 3.7 | Gratis (LGPLv2.1) | Sin PiP/AirPlay en MKV |
| VLCKit + KSPlayer LGPL | Pago KSPlayer | Maxima compatibilidad |

### Contacto KSPlayer LGPL

Email: kingslay@icloud.com
Preguntar por: Precio licencia LGPL para app iOS/macOS/tvOS, single app

---

## 8. Archivos relevantes del proyecto

### Player implementations

| Archivo | Path | Estado |
|---------|------|--------|
| Player Protocol | `IPTVDownloader/Core/Player/PlayerProtocol.swift` | Activo |
| Player Factory | `IPTVDownloader/Core/Player/PlayerFactory.swift` | Activo, fallback a AVPlayer |
| AVPlayer | `IPTVDownloader/Core/Player/AVPlayerImplementation.swift` | Activo, unico funcional |
| KSPlayer | `IPTVDownloader/Core/Player/KSPlayerImplementation.swift` | Stub `#if canImport` |
| VLCKit | `IPTVDownloader/Core/Player/VLCPlayerImplementation.swift` | Stub `#if canImport(VLCKitSPM)` |
| FFmpeg | `IPTVDownloader/Core/Player/FFmpegPlayerImplementation.swift` | Wrapper AVPlayer simplificado |

### Utilidades streaming

| Archivo | Path | Estado |
|---------|------|--------|
| FFProbe | `IPTVDownloader/Utils/FFProbeUtilities.swift` | Activo, solo macOS |
| FFmpeg Transmuxer | `IPTVDownloader/Utils/FFmpegTransmuxer.swift` | Existe pero no se usa |
| Stream Compat | `IPTVDownloader/Utils/StreamCompatibilityHandler.swift` | Simplificado, devuelve URL original |
| VLC Helper | `IPTVDownloader/Utils/VLCHelper.swift` | Abre streams en VLC externo |
| Stream Manager | `IPTVDownloader/Features/Download/ViewModels/StreamManager.swift` | Resolucion URLs live |

### Configuracion

| Archivo | Path | Nota |
|---------|------|------|
| Podfile | `Podfile` | VLCKit ~> 3.6.0 (macOS only). ACTUALIZAR a 3.7.0 |
| Xcode Project | `mks-multiplatform-iptv.xcodeproj` | Sin SPM packages de player |

### Archivos eliminados (en git status)

```
D IPTVDownloader/Utils/AVPlayerCompatibleProxy.swift
D IPTVDownloader/Utils/DirectHTTPProxy.swift
D IPTVDownloader/Utils/HTTPStreamProxyServer.swift
D IPTVDownloader/Utils/HTTPStreamServer.swift
D IPTVDownloader/Utils/SimpleHTTPStreamServer.swift
```

---

## 9. Pasos para implementar

### Paso 1: Decidir licencia y opcion (A/B/C/D)

Ver seccion 7. Esto determina todo lo demas.

### Paso 2: Agregar dependencia SPM

**Para KSPlayer (Opcion A/B/D):**
1. Xcode > File > Add Package Dependencies
2. URL: `https://github.com/kingslay/KSPlayer.git`
3. Branch: `main`
4. Esperar resolucion (descarga FFmpegKit binaries, varios minutos)
5. Target: mks-multiplatform-iptv

**Para VLCKit iOS (Opcion C/D):**
1. Xcode > File > Add Package Dependencies
2. URL: `https://github.com/MobileVLCKit-SPM/MobileVLCKit-SPM`
3. Version: from 3.7.0
4. Target: mks-multiplatform-iptv

**Para VLCKit macOS:** Actualizar Podfile de `~> 3.6.0` a `~> 3.7.0`

### Paso 3: Configurar player

**KSPlayer:**
```swift
import KSPlayer

// En AppDelegate o App init
KSOptions.secondPlayerType = KSMEPlayer.self  // Habilitar FFmpeg engine
KSOptions.canStartPictureInPictureAutomaticallyFromInline = true

// Headers IPTV
let options = KSOptions()
options.appendHeader(["User-Agent": "VLC/3.0.18"])
options.formatContextOptions["reconnect"] = 1
options.formatContextOptions["reconnect_streamed"] = 1
```

### Paso 4: Actualizar PlayerFactory

Reemplazar los stubs actuales por implementaciones reales. El pattern `#if canImport` existente facilita esto - una vez el modulo esta en SPM, el codigo stub se activa automaticamente.

### Paso 5: Actualizar PlayerFactory.createBestPlayer()

Implementar logica de seleccion inteligente:
```
1. Analizar URL: extension, scheme, path patterns (/live/, .m3u8, etc)
2. Si formato nativo -> KSAVPlayer / AVPlayer (PiP + AirPlay)
3. Si MKV/TS -> KSMEPlayer (PiP, sin AirPlay)
4. Si falla -> fallback a siguiente player
```

### Paso 6: Testing

Probar con:
- VOD movie en MKV (H.264 + AAC)
- VOD movie en MKV (H.265 + DTS)
- Live TV HLS (.m3u8)
- Live TV TS sobre HTTP
- Live TV RTSP (si aplica)
- PiP en iOS
- AirPlay con stream HLS
- Reconexion automatica (desconectar/reconectar WiFi)
- Seeking en VOD

---

## 10. Referencias y fuentes

### Repositorios principales

- KSPlayer: https://github.com/kingslay/KSPlayer
- KSPlayer FFmpegKit: https://github.com/kingslay/FFmpegKit
- VLCKit (oficial): https://code.videolan.org/videolan/VLCKit
- VLCKit (GitHub mirror): https://github.com/videolan/vlckit
- MobileVLCKit-SPM: https://github.com/MobileVLCKit-SPM/MobileVLCKit-SPM
- vlckit-spm: https://github.com/tylerjonesio/vlckit-spm
- VLCUI (SwiftUI wrapper): https://github.com/LePips/VLCUI
- MPVKit: https://github.com/mpvkit/MPVKit
- MPVKit Swift: https://github.com/karelrooted/MPVKit
- mdk-sdk: https://github.com/wang-bin/mdk-sdk
- swift-mdk: https://github.com/wang-bin/swift-mdk

### Documentacion tecnica

- KSPlayer docs: https://zread.ai/kingslay/KSPlayer
- VLCKit Wiki: https://wiki.videolan.org/VLCKit/
- VLCKit NEWS: https://github.com/videolan/vlckit/blob/master/NEWS
- VLCKit tags: https://code.videolan.org/videolan/VLCKit/-/tags
- Apple PiP docs: https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-custom-player
- AVAssetResourceLoaderDelegate guide: https://jaredsinclair.com/2016/09/03/implementing-avassetresourceload.html
- AVPlayer local proxy example: https://github.com/kevinjameshunt/AVPlayer-HTTP-Headers-Example

### Issues relevantes

- VLCKit SPM: https://code.videolan.org/videolan/VLCKit/-/issues/302
- VLCKit PiP: https://code.videolan.org/videolan/VLCKit/-/issues/582
- KSPlayer AirPlay: https://github.com/kingslay/KSPlayer/issues/458
- KSPlayer Xcode 26: https://github.com/kingslay/KSPlayer/issues/874
- FFmpegKit retirement: https://tanersener.medium.com/saying-goodbye-to-ffmpegkit-33ae939767e1

### Apps de referencia

- IPTV+ (usa KSPlayer + VLC + MPV): https://apps.apple.com/us/app/iptv-my-smart-iptv-player/id1525121231
- Snappier IPTV (usa KSPlayer): https://apps.apple.com/us/app/snappier-iptv/id1579702567
- TracyPlayer (KSPlayer demo): https://apps.apple.com/us/app/ksplayer-tracy/id6450770064
- Infuse (motor propietario): https://apps.apple.com/us/app/infuse/id1136220934
- Swiftfin/Jellyfin (usa VLCKit): https://github.com/jellyfin/Swiftfin

# Inventario y Comparativa Tecnica: MKS-IPTV-App

**Version Marzo 2026 v3 -- Auditoria profunda TransmuxCore + KSPlayer + optimizaciones + roadmap ampliado**
**Enfoque: Portfolio/Open-Source + Optimizacion del core antes de nuevas features**

> Contexto: Primera app nativa Swift 6 multi-plataforma (iOS 26/tvOS 26/macOS 26).
> Objetivo: No monetizar como prioridad, sino ser el mejor tecnicamente en el ecosistema Apple, construir portfolio solido como dev multi-plataforma (web -> Swift), y open-source lo que merezca la pena.

---

## 1. Inventario de Capacidades Actuales (Auditoria Real del Codigo -- Marzo 2026)

> Datos verificados contra el codebase real: **185 ficheros Swift**, ~17,000+ LOC en modulos core.

### Nucleo de Transmision (TransmuxCore) -- 6,685 LOC, 8 ficheros

El moat tecnico principal. **No existe equivalente open-source** que haga transmux MKV->fMP4 on-device para AVPlayer nativo.

| Fichero | LOC | Funcion |
|---------|-----|---------|
| `TransmuxingService.swift` | 2,436 | Actor-based FFmpeg wrapper. Pipeline completo de remuxing MKV/AVI/TS -> fMP4 |
| `TransmuxServer.swift` | 2,065 | NWListener HTTP nativo. Sirve HLS/fMP4 con range requests. DLNA headers |
| `HLSSegmenter.swift` | 859 | Parsing de MP4 boxes en tiempo real. Genera playlists m3u8 VOD |
| `LiveHLSProxy.swift` | 633 | **NUEVO**: Proxy single-connection para live streams. Caching de segmentos en RAM |
| `TransmuxLog.swift` | 297 | Logging estructurado del pipeline |
| `ActiveTransmux.swift` | 186 | Handle de sesion con senalizacion de seek |
| `MP4BoxParser.swift` | 107 | Parsing bajo nivel de boxes fMP4 (moof+mdat) |
| `SegmentCache.swift` | 102 | Gestion de cache en memoria para segmentos |

**Capacidades verificadas:**
- Contenedores de entrada: MKV, MP4, AVI, TS
- Salida: fMP4 fragmentado (moof+mdat) + HLS m3u8
- Codecs audio: AAC passthrough, AC3/EAC3/DTS -> AAC transcoding
- Codecs video: H.264, H.265 passthrough
- Timestamp rebasing global para A/V sync entre streams
- Fullness gate: solo sirve segmentos completos
- Progressive fMP4: seeking instantaneo sin reabrir conexion

### Modulo de Reproduccion -- 3,538 LOC, 11+ ficheros

| Fichero | Funcion |
|---------|---------|
| `AVPlayerImplementation.swift` | AVPlayer nativo con Combine. PiP, AirPlay 2, External Seek Detection, Reload Recovery |
| `TransmuxResourceLoader.swift` | `AVAssetResourceLoaderDelegate` para alimentar AVPlayer desde archivos en crecimiento |
| `GlitchDetector.swift` + `GlitchTypes.swift` | Monitoreo real-time: buffer starvation, freezes, A/V desync, frame drops |
| `PlayerFactory.swift` | Auto-seleccion de backend: AVPlayer nativo / FFmpeg transmux / VLC fallback |
| `FFmpegPlayerImplementation.swift` | Pipeline Transmux + AVPlayer |
| `VLCPlayerImplementation.swift` | Fallback VLC para edge cases |
| `StreamProxyAdapter.swift` | HTTP proxy wrapping para streams |
| `NativePlayerRepresentable.swift` | Bridge SwiftUI <-> AVPlayer |

**Diferencial clave**: El `GlitchDetector` no solo detecta problemas -- retroalimenta al pipeline de transmux con acciones correctivas (flush, cooldown adjustment). Esto es significativamente mas sofisticado que el simple "buffering spinner" de la competencia.

### Remote Play -- DLNA & Cast -- 3,888 LOC

**DLNA (1,832 LOC):**
- `DLNAController.swift` -- AVTransport SOAP control
- `DLNASOAPClient.swift` -- Serializacion SOAP
- `DLNADeviceParser.swift` -- UPnP discovery + parsing
- `DLNAMetadataAdapter.swift` -- DIDL-Lite metadata
- `DLNAEventSubscriber.swift` -- GENA event subscription

**Cast/Chromecast (2,056 LOC):**
- `CastController.swift` -- Google Cast V2 protocol over TLS (puerto 8009)
- `CastSocket.swift` -- Gestion TLS socket
- `CastChannel.swift` -- Cast V2 message framing + state machine
- `CastProtobuf.swift` -- Protocol buffer encoding
- `CastMetadataAdapter.swift` -- Metadata formatting

**Capa unificada:**
- `RemotePlayManager.swift` -- Discovery + device management
- `RemoteDeviceController.swift` -- Protocolo abstracto (DLNA y Cast conforman)
- `RemotePlaybackState.swift` -- State machine (idle/connecting/loading/playing/error)

### TouchBar -- COMPLETO Y SOFISTICADO (macOS)

| Fichero | Funcion |
|---------|---------|
| `TouchBarManager.swift` | Estado central con context switching por pantalla (~200 LOC) |
| `TouchBarAccessor.swift` | NSViewRepresentable bridge SwiftUI <-> NSTouchBar (~900 LOC) |
| `DownloadsTouchBarView.swift` | Progreso en tiempo real: conteo activo, barra, velocidad/ETA, pause/resume/cancel |
| `MediaListTouchBarView.swift` | Busqueda, filtros de categoria (scrollable popover), ordenacion |

**Contextos implementados:**
- **Downloads**: Contador de descargas activas, barra de progreso, velocidad/ETA, botones pause/resume/cancel
- **Media List**: Campo de busqueda, filtros de categoria con NSPopoverTouchBarItem scrollable, sort (Name A-Z, Newest, Rating)
- **Live TV**: Play/pause, slider de volumen, channel picker
- **Movie/Serie Detail**: Boton play, boton download, rating display
- **Smart Context Switching**: Cambia automaticamente el layout segun pantalla activa

Usa NSTouchBar delegate + NSHostingControllers para vistas SwiftUI, Combine subscriptions para updates reactivos, y first responder management completo.

### Football Integration -- 6 ficheros, ~40KB

| Fichero | Funcion |
|---------|---------|
| `FootballConfig.swift` | Configuracion de provider (API-Football, mock) |
| `FootballService.swift` | Actor principal: carga de fixtures y matching |
| `FootballDataProvider.swift` | Abstraccion de provider + mock |
| `FootballModels.swift` | Modelos: Fixture, Team, Event |
| `FootballChannelMatching.swift` | Fuzzy matching canales <-> partidos |
| `FootballEventBadge.swift` | **NUEVO**: Badge visual de partido en curso sobre canales |

- Cache con TTL de 4 horas
- Refresh de scores cada 60s (configurable)
- Soporte: Champions League, La Liga, Premier League, Serie A, Bundesliga, Ligue 1

### Sistema de Descargas -- PUNTO FUERTE DIFERENCIAL

**Capacidades verificadas (ningun competidor ofrece todas juntas):**
- Descargas concurrentes con limite configurable
- Pause/resume/cancel por descarga individual
- Progreso en tiempo real: velocidad, ETA, porcentaje (rolling averages)
- **Live Activities en Dynamic Island** (`DownloadLiveActivityManager.swift`) -- progreso visible sin abrir la app
- **TouchBar integration** -- progreso y controles en macOS Touch Bar
- Conversion de formato de salida: MP4/MKV/MOV (MOV optimizado para AirPlay)
- **FFmpeg transmux en descarga**: H.264/H.265 video, AAC/AC3/EAC3/DTS audio
- Cache manager para evitar re-descargas
- Persistencia entre reinicios de app
- File sharing habilitado para acceso desde Finder/Files

**Metadata en descargas:**
- Enriquecimiento via TMDB + TheTVDB + iTunes Search (`MetadataEnrichmentService.swift`)
- Posters, artwork, fanart, sinopsis, ratings, cast, director, genero
- Metadata inyectada en MPNowPlayingInfoCenter (Control Center, Lock Screen)
- AVPlayerItem.externalMetadata para integracion nativa iOS/tvOS
- Artwork en Control Center y AirPlay

> **Nota**: Guardar en Photos Library o ubicacion personalizada es una mejora planificada (ver Roadmap). Actualmente guarda en el sandbox de la app con file sharing.

### Funcionalidades de App (Verificadas)

- **Liquid Glass UI**: SwiftUI 6 puro, iOS 26 Beta, glassmorphism, haptics, context menus
- **Multi-perfil IPTV**: `IPTVProfilesManager.shared` (un perfil activo simultaneo, persistence en UserDefaults)
- **Live Activities**: Dynamic Island para descargas (implementado), scoreboards deportivos (planificado)
- **Live Channels**: Grid con categorias dinamicas, EPG, badges de football, favoritos, busqueda
- **Metadata multi-provider**: TMDB + TheTVDB + iTunes Search con orquestador

---

## 2. Comparativa de Mercado Exhaustiva (Investigacion Independiente Marzo 2026)

> Fuentes: App Store, GitHub, sitios oficiales, changelogs, foros Reddit/MacRumors, reviews TROYPOINT.

### Competidores Principales (Estado Real Verificado)

#### IPTVX -- El lider establecido
- **Version**: v21.5.1 (actualizado febrero 2026, frecuencia semanal)
- **Rating**: 4.38/5 (2,600+ ratings)
- **Precio**: Freemium. Pro ~$99.99/ano o $199.99 lifetime
- **Plataformas**: iOS, tvOS, macOS, Vision Pro
- **Player**: Hibrido (Apple Native + VLCKit + Metal -- elige segun formato)
- **Puntos fuertes**: UI Netflix-style pulida, recordings via Media Server (novedad 2025-26), iCloud sync excelente, EPG grid completo, catchup, multi-screen, TMDB metadata, parental controls, Xtream + M3U + PLEX + SMB
- **Debilidades reales**: MKV via VLC pierde integracion nativa (PiP/AirPlay/Siri no 100% seamless al cambiar player). No tiene single-connection proxy. Precio alto.

#### UHF -- El challenger en ascenso
- **Version**: Actualizado regularmente (2026)
- **Rating**: 4.3/5 (635 ratings)
- **Precio**: Free (generoso) / Pro $1.99/mes o $17.99/ano
- **Plataformas**: iOS, tvOS, macOS
- **Puntos fuertes**: Free tier completo sin paywall agresivo, **soporte Stremio addons** (unico en IPTV apps), VPN integrado, EPG reinventado para touch, Trakt integration, DVR companion, smart reconnect
- **Debilidades reales**: Scrolling causa freezes del player (reportado), sin busqueda fiable en VOD, sin marcado de temporadas completas

#### Snappier IPTV
- **Version**: v5.3.3 (actualizado 2026)
- **Precio**: Free (corta playback a 240s) / Pro one-time
- **Player**: 3 built-in: **KSPlayer** (PiP nativo + HDR), VLC, MPV
- **Puntos fuertes**: Multi-screen (2x2), iCloud sync parcial, EPG, deinterlace, Trakt, recording via companion
- **Debilidades**: Free tier inutilizable (240s limit). No transmux nativo. Depende de KSPlayer/VLC/MPV sin unificacion real.

#### Chillio IPTV Smart Player Pro
- **Precio**: Freemium
- **Puntos fuertes**: Netflix-style UI, **merge de multiples cuentas** Xtream + M3U + FTP + WebDAV + RealDebrid en una sola experiencia, descarga offline, sin watermarks en free
- **Puntos debiles**: Relativamente nuevo, ecosistema menos probado

#### GSE Smart IPTV
- **Estado**: Mantenimiento bajo (~2023 ultima actualizacion significativa)
- **Puntos fuertes historicos**: DLNA mejor que la competencia, M3U/JSON/Database playlists, multiplataforma
- **Puntos debiles**: UI legacy "Android portada", sin iCloud, sin actualizaciones relevantes

#### IINA (solo macOS)
- **Version**: v1.4.1 (septiembre 2025 + nightlies 2026 con soporte macOS 26)
- **Motor**: mpv (no AVPlayer)
- **Puntos fuertes**: El mejor reproductor nativo macOS (UI, Touch Bar, PiP, plugin system JS). Soporta M3U/IPTV basico
- **Limitaciones IPTV**: Sin EPG, sin Xtream, sin AirPlay, sin iOS/tvOS (AppKit != UIKit), sin categorias de canales. No es un IPTV player -- es un media player que acepta M3U

#### KSPlayer (Framework, no app)
- **Estado**: Activo en GitHub (issues enero 2026)
- **Licencia**: GPL (obliga open-source tu app) o LGPL de pago
- **Arquitectura**: AVPlayer (KSAVPlayer) + FFmpeg (MEPlayer) dual-backend con seleccion automatica
- **PiP**: KSPictureInPictureController wrapping AVPictureInPictureController con navigation restoration
- **Multi-plataforma**: iOS/tvOS/macOS/visionOS/Mac Catalyst via compilacion condicional (#if canImport)
- **Uso**: Base de Snappier y otras apps. Buen codigo para estudiar.

### Tabla Comparativa

| Caracteristica | MKS-IPTV | IPTVX | UHF | Snappier | Chillio | GSE |
|:---|:---|:---|:---|:---|:---|:---|
| **MKV en AVPlayer nativo** | **SI (Transmux)** | No (VLCKit) | No | No (KSPlayer) | No | No (VLCKit) |
| **PiP/AirPlay seamless** | **SI (Total)** | Parcial (cambia player) | Si | Si (KSPlayer) | Parcial | Parcial |
| **Single upstream proxy** | **SI (LiveHLSProxy)** | No | No | No | No | No |
| **Glitch detection + recovery** | **SI (Reactivo)** | No | Smart reconnect | No | No | No |
| **Multi-source merge** | Pendiente | Xtream+M3U+PLEX+SMB | M3U+Xtream+Stremio | M3U+Xtream | **Xtream+M3U+FTP+WebDAV+RD** | M3U+JSON |
| **Stremio addons** | Pendiente | No | **Si (unico)** | No | No | No |
| **iCloud Sync** | Pendiente | **Excelente** | Si (cross-device) | Parcial | No | No |
| **EPG Grid completo** | Basico | **Excelente** | Reinventado | Si | Si | Si |
| **Recordings/Catchup** | No | **Si (Media Server)** | Si (DVR companion) | Si (companion) | No | No |
| **Football + Live Activities** | **SI** | No | No | No | No | No |
| **DLNA/Cast nativo** | **SI (ambos)** | No explicito | No | No | Si | **Si (historico)** |
| **TouchBar (macOS)** | **SI (4 contextos)** | ? | ? | ? | N/A | N/A |
| **Descargas + Live Activity** | **SI (completo)** | Si | Si | Si | Si | Si |
| **Metadata multi-provider** | **SI (TMDB+TVDB+iTunes)** | TMDB | ? | ? | ? | No |
| **Diseno** | Liquid Glass (iOS 26) | Netflix-style | Apple-like | Funcional | Netflix-style | Legacy |
| **Precio** | Free/Open-source | $99-199/ano | Free/$18/ano | Free(240s)/$$ | Freemium | Free/Pro barato |

### Diferenciadores Reales (Verificados)

1. **MKV Nativo Perfecto**: Ninguna app en el App Store hace transmux MKV->fMP4 on-device para AVPlayer. Todas usan VLCKit o KSPlayer como decoders separados, perdiendo integracion nativa (Siri, controles de sistema, PiP consistente).

2. **LiveHLSProxy (Anti-Ban)**: Problema real y documentado -- los providers IPTV banean por "too many connections" cuando AirPlay abre una segunda conexion. Existen proxies server-side (tuliprox, iptv-proxy en GitHub) pero **ninguno integrado en una app iOS**. Es genuinamente unico.

3. **Glitch Detection Reactivo**: UHF tiene "smart reconnect" pero es basico. Tu GlitchDetector monitorea buffer starvation, freezes, A/V desync y frame drops con feedback loop al pipeline de transmux. Significativamente mas avanzado.

4. **Football + Dynamic Island**: Ninguna app IPTV integra datos deportivos en tiempo real con Live Activities. Es un diferencial de nicho fuerte para el usuario de IPTV deportivo.

5. **DLNA + Cast nativos en Swift**: GSE lo tenia pero esta estancado. Tu implementacion (3,888 LOC con protocolo unificado) es moderna y extensible. Cast V2 nativo sin Google Cast SDK pesado es diferencial.

6. **Descargas con metadata enriquecida + Live Activities**: El pipeline de descarga (concurrente, pause/resume, conversion de formato, metadata TMDB+TVDB inyectada, Live Activities en Dynamic Island, TouchBar controls en macOS) es el mas completo del mercado IPTV. Ningun competidor combina todo esto.

7. **TouchBar nativo con 4 contextos**: Mientras IINA tiene TouchBar basico, tu implementacion con context-switching automatico (Downloads/Media/LiveTV/Detail) es mas sofisticada que cualquier app IPTV en macOS.

---

## 3. Features de Competencia a Adoptar (Investigacion Marzo 2026)

### 3.1 Multi-Source Merge (inspirado en Chillio)

**Que hace Chillio**: Merge de multiples cuentas Xtream + M3U + FTP + WebDAV + RealDebrid en una sola experiencia unificada. El usuario ve un catalogo unico con contenido de todas sus fuentes.

**Estado actual en MKS-IPTV**: Solo Xtream Codes API. `IPTVProfilesManager` maneja multiples perfiles pero cada uno es Xtream-only, y solo uno activo a la vez. No hay M3U parser, no hay FTP/WebDAV client.

**Implementacion propuesta:**

```
ContentSourceManager (nuevo)
├── XtreamCodesSource (existente, refactorizar)
├── M3USource (nuevo -- parser M3U/M3U8 + EPG XML)
├── WebDAVSource (nuevo -- basado en amosavian/FileProvider)
├── FTPSource (nuevo -- basado en amosavian/FileProvider)
├── SMBSource (nuevo -- basado en amosavian/FileProvider, parcial)
├── RealDebridSource (nuevo -- API REST, OAuth2)
├── StremioAddonSource (nuevo -- HTTP JSON protocol)
└── UnifiedCatalog -- merge y deduplicacion de todas las fuentes
```

**Libreria de referencia**: [amosavian/FileProvider](https://github.com/amosavian/FileProvider) (MIT license)
- WebDAV, FTP, SMB2, Dropbox, OneDrive, iCloud en una API unificada
- `contentsOfDirectory()`, `contents(path:offset:length:)` (streaming parcial!), `copyItem()`
- iOS/macOS/tvOS compatible
- Async callbacks con Progress tracking

### 3.2 Stremio Addons (inspirado en UHF)

**Que hace UHF**: Consume Stremio addons como fuente de contenido adicional. Los addons de Stremio son servidores HTTP que devuelven JSON con catalogos, metadata y streams.

**Protocolo Stremio** (investigado del SDK oficial + Stremio-iOS):

```
Endpoints HTTP (GET, respuesta JSON):
├── GET /manifest.json                          -- Manifest del addon
├── GET /catalog/{type}/{id}.json               -- Catalogo (metas[])
├── GET /catalog/{type}/{id}/{extra}.json       -- Catalogo con filtros/search
├── GET /meta/{type}/{id}.json                  -- Metadata completa
├── GET /stream/{type}/{id}.json                -- Streams disponibles
└── GET /subtitles/{type}/{id}.json             -- Subtitulos

Tipos: movie, series, channel, tv
IDs: Tipicamente IMDb (tt1234567) o custom (yt_id:xxx)

Manifest: { id, name, version, description, resources[], types[], catalogs[], idPrefixes[] }
Stream: { url?, infoHash?, fileIdx?, title?, behaviorHints? }
```

**Referencia estudiada**: [rcastriotta/Stremio-iOS](https://github.com/rcastriotta/Stremio-iOS) (React Native)
- `useStremio` hook: login Stremio API, fetch addons, resolve streams via addon URL
- `useCatalog` hook: fetch catalogos de cinemeta (cinemeta-catalogs.strem.io), busqueda, paginacion
- Stream resolution: addon URL -> `/stream/{type}/{id}.json` -> array de streams con URLs directas o infoHash+fileIdx
- Torrent streaming: via Stremio streaming server (`/hlsv2/{id}/master.m3u8?mediaURL=...`)

**Implementacion propuesta en Swift:**

```swift
// StremioAddonClient.swift
actor StremioAddonClient {
    func fetchManifest(from url: URL) async throws -> StremioManifest
    func fetchCatalog(addon: StremioAddon, type: String, id: String) async throws -> [StremioMeta]
    func fetchStreams(addon: StremioAddon, type: String, id: String) async throws -> [StremioStream]
    func searchCatalog(addon: StremioAddon, query: String) async throws -> [StremioMeta]
}

// Los addons son simples HTTP endpoints -- no necesitas SDK, solo Codable models
```

### 3.3 RealDebrid Integration

**Que es**: Servicio de unrestrict de links (premium hosters -> direct download URLs). Chillio lo integra como fuente de contenido.

**API investigada** (api.real-debrid.com):

```
Autenticacion: OAuth2 variant (device flow para mobile)
Rate limit: 250 req/min
Endpoints clave:
├── POST /rest/1.0/unrestrict/link     -- Link -> direct download URL
│   Response: { id, filename, mimeType, filesize, download, streamable }
├── GET  /rest/1.0/torrents            -- Lista de torrents activos
├── POST /rest/1.0/torrents/addMagnet  -- Anadir magnet link
├── GET  /rest/1.0/streaming/transcode/{id} -- Stream transcodificado
├── GET  /rest/1.0/user                -- Info de usuario
└── GET  /rest/1.0/traffic             -- Traffic remaining
```

**Implementacion propuesta:**

```swift
actor RealDebridService {
    func authenticate(deviceCode: String) async throws -> RDToken
    func unrestrictLink(_ url: URL) async throws -> RDUnrestrictedLink
    func getStreamURL(for link: RDUnrestrictedLink) -> URL  // .download field
    func listTorrents() async throws -> [RDTorrent]
}
```

### 3.4 WebDAV/FTP/SMB Browse + Stream (inspirado en IPTVX/Infuse)

**Que hacen IPTVX/Infuse**: Browse NAS/servidores de red, navegar carpetas, reproducir directamente sin descargar.

**Libreria de referencia**: [amosavian/FileProvider](https://github.com/amosavian/FileProvider)
- `WebDAVFileProvider`: Browse, download, upload, streaming parcial via `contents(path:offset:length:)`
- `FTPFileProvider`: Browse y download (FTP deprecated pero aun usado en hosting)
- `SMBFileProvider`: SMB2 parcialmente implementado -- browse y operaciones basicas
- API unificada: `FileProviderBasicRemote` protocol
- MIT license, iOS/macOS/tvOS compatible

**Integracion con AVPlayer:**
1. Browse via FileProvider -> listar archivos de video
2. Para archivos HTTP-accessible (WebDAV): URL directa a AVPlayer
3. Para archivos no-HTTP (FTP/SMB): descargar a temp o proxy via TransmuxServer

### 3.5 Guardar en Photos Library / Ubicacion Custom

**Estado actual**: Descargas guardadas en app sandbox con file sharing habilitado.

**Mejora propuesta:**
- `PHPhotoLibrary` para guardar videos en la libreria de fotos del usuario (requiere entitlement)
- `UIDocumentPickerViewController` para elegir ubicacion custom (Files, iCloud Drive, NAS montado)
- Metadata preservada en el archivo de salida (titulo, artwork embebido via AVAssetExportSession)
- Opcion de "guardar una copia" vs "mover" para no duplicar espacio

---

## 4. Repositorios de Referencia (Clonados en `references/`)

> Carpeta `references/` anadida a `.gitignore`. Repos clonados con `--depth 1` para estudio.

### 4.1 KSPlayer (`references/KSPlayer`)

**Repo**: [kingslay/KSPlayer](https://github.com/kingslay/KSPlayer) -- GPL/LGPL
**Commit**: Enero 2026 (activo)

**Hallazgos clave del estudio:**

| Area | Detalle |
|------|---------|
| **Arquitectura dual** | `KSAVPlayer` (AVPlayer nativo) + `MEPlayer` (FFmpeg kernel). Seleccion por formato. |
| **PiP** | `KSPictureInPictureController` extiende `AVPictureInPictureController`. Maneja navigation restoration (pop/push/present). Disponible tvOS 14+. |
| **Multi-plataforma** | `#if canImport(UIKit)` / `#if os(macOS)` / `#if os(xrOS)` para adaptar. Misma codebase, compilacion condicional. |
| **External playback** | AirPlay via `player.allowsExternalPlayback` + `usesExternalPlaybackWhileExternalScreenIsActive`. Deshabilitado en visionOS. |
| **Buffering** | `MediaLoadState` enum (idle/loading/playable/loaded). `bufferingProgress` 0-100 con delegates. |
| **Rate/Volume** | Rate aplicado solo durante playback. Volume sync bidireccional con AVPlayer. |
| **KSOptions** | Configuracion centralizada: `isLoopPlay`, `readyTime`, `avOptions` (para AVURLAsset). |
| **Playback coordinator** | `AVPlaybackCoordinator` expuesto para SharePlay (macOS 12+, iOS 15+, tvOS 15+). |

**Que aprender / Posibles PRs:**
- PiP navigation restoration pattern (util para mejorar tu PiP)
- `KSOptions` como configuracion centralizada -- tu app podria beneficiarse de un patron similar
- SharePlay via `AVPlaybackCoordinator` -- ya expuesto en KSPlayer, pasar a tu app
- **Gap en KSPlayer que tu llenas**: No tiene single-connection proxy, no tiene transmux MKV->fMP4 (usa FFmpeg como decoder directo), no tiene glitch detection

### 4.2 Stremio Addon SDK (`references/stremio-addon-sdk`)

**Repo**: [Stremio/stremio-addon-sdk](https://github.com/Stremio/stremio-addon-sdk) -- MIT
**Uso**: Documentacion del protocolo HTTP para implementar cliente Swift.

**Protocolo completo documentado en seccion 3.2.**

### 4.3 Stremio-iOS (`references/Stremio-iOS`)

**Repo**: [rcastriotta/Stremio-iOS](https://github.com/rcastriotta/Stremio-iOS) -- Unofficial
**Uso**: Referencia de como consumir Stremio addons y catalogs desde una app mobile.

**Hallazgos clave:**
- `useStremio.ts`: Login API Stremio, fetch addons del usuario, resolve streams via torrentio URL
- `useCatalog.ts`: Fetch catalogs de cinemeta (top movies/series, Netflix, Hulu), busqueda, paginacion con skip
- Stream resolution: `addon.transportUrl.replace('/manifest.json', '/stream/{type}/{id}.json')`
- Torrent streaming via Stremio server: `/hlsv2/{randomId}/master.m3u8?mediaURL={torrentUrl}&videoCodecs=h264,h265&audioCodecs=aac,mp3`
- VideoPlayer usa VLCPlayer (React Native) -- tu tendrias AVPlayer nativo (ventaja)

### 4.4 FileProvider-Swift (`references/FileProvider-Swift`)

**Repo**: [amosavian/FileProvider](https://github.com/amosavian/FileProvider) -- MIT
**Uso**: Implementar WebDAV/FTP/SMB browse + streaming.

**Hallazgos clave:**
- `HTTPFileProvider`: Clase base abstracta para WebDAV y otros HTTP-based providers
- `WebDAVFileProvider`: PROPFIND para listing, GET para download, PUT para upload. Range requests soportados.
- `FTPFileProvider`: LIST/MLST para listing, RETR para download. Deprecated pero funcional.
- `SMBFileProvider`: SMB2 parcial -- browse funciona, pero muchas operaciones devuelven `NotImplemented()`
- `FileObject`: Modelo unificado con URL, name, path, size, dates, type
- **Streaming**: `contents(path:offset:length:)` permite lectura parcial -- util para streaming
- Session management con URLSession delegates, cache configurable
- `FileProviderBasicRemote` protocol unifica todos los providers

---

## 5. Valoracion Critica Independiente

### Lo que el analisis acierta

- **El moat tecnico es real**. TransmuxCore + LiveHLSProxy resuelven problemas que la competencia ignora por complejidad. Confirmado: no existe equivalente open-source.
- **La arquitectura es solida**. 185 ficheros, separacion clara en modulos, actors para concurrencia, protocol abstraction para DLNA/Cast. No es un prototipo.
- **Como portfolio es excepcional**. Primera app Swift -> multi-plataforma con FFmpeg wrapper, NWListener HTTP server, Cast V2 protocol, CloudKit (pendiente), Intents (pendiente). Demuestra capacidad real.
- **Las descargas son un punto fuerte subestimado**. Ningun competidor combina: descarga concurrente + transmux en descarga + Live Activities + TouchBar + metadata multi-provider. Es un diferencial real.

### Lo que el analisis exagera o ignora

1. **IPTVX esta mucho mas adelantado en UX y features completas**. Recordings, catchup, multi-screen, TMDB, parental, y actualizaciones semanales. No es solo "bonito" -- es funcionalmente superior excepto en playback puro.

2. **"500-2000 usuarios activos" es optimista** sin marketing. UHF con anos de presencia tiene ~635 ratings. Una app nueva empieza en decenas.

3. **El DLNA/Cast esta implementado pero no battle-tested**. La compatibilidad real con Smart TVs requiere testing contra docenas de dispositivos reales.

4. **Tests practicamente inexistentes**. TransmuxCoreTests es minimal. Para 2,436 LOC de transmuxing critico, esto es riesgo real.

5. **El riesgo de App Store es real**. Apple ha retirado apps IPTV. Open-source el core mitiga parcialmente.

6. **La API actual es Xtream-only**. `MovieService` asume `.player_api.php`. Anadir M3U/Stremio/WebDAV requiere refactorizar a un provider factory pattern abstracto.

### Gaps reales que cerrar

| Gap | Impacto | Esfuerzo |
|-----|---------|----------|
| **Multi-source merge** | Critico (Chillio/IPTVX ya lo tienen) | Alto (requiere provider factory) |
| **M3U parser** | Critico (formato mas comun de IPTV) | Medio |
| **iCloud Sync** | Critico (IPTVX/UHF ya lo tienen) | Medio |
| **Stremio addons** | Alto (UHF es unico -- igualar y superar) | Medio (protocolo HTTP simple) |
| **EPG Grid completo** | Alto (expectativa basica) | Medio-Alto |
| **Tests automatizados** | Alto (riesgo de regresion) | Medio |
| **WebDAV/FTP/SMB browse** | Medio-Alto (NAS users) | Medio (FileProvider lib) |
| **RealDebrid** | Medio (nicho pero creciente) | Bajo (API REST simple) |
| **Siri Shortcuts** | Medio (diferenciador) | Bajo (App Intents) |
| **Photos Library save** | Medio (conveniencia) | Bajo |

---

## 6. Roadmap Priorizado (Actualizado v3 -- Marzo 2026)

> **Principio rector**: Solidificar el core tecnico ANTES de anadir features nuevas. TransmuxCore es el moat -- hacerlo state-of-the-art primero.

### Fase 0 -- TransmuxCore State-of-the-Art (PRIORIDAD MAXIMA)

> Sin esto, todo lo demas se construye sobre una base sin optimizar.

1. **Build minimo de FFmpeg + fixes criticos**
   - **FIX CRITICO**: Eliminar `--disable-audiotoolbox --disable-videotoolbox` de `3-build-ffmpeg-ios.sh:97-98`
   - **FIX**: Eliminar `-fembed-bitcode` de `3-build-ffmpeg-ios.sh:68` (Apple elimino bitcode en Xcode 14)
   - **FIX**: Subir deployment targets a macOS 14.0, iOS 17.0 en `0-config.sh:56-57`
   - Aplicar `--disable-everything` + enable selectivo de demuxers/muxers/codecs usados
   - Resultado: -60% tamano binario, menor superficie de ataque
   - Anadir `-O3 -mcpu=apple-m1` (macOS) / `-mcpu=apple-a15` (iOS) en CFLAGS
   - Habilitar `--enable-lto --enable-asm --enable-neon --enable-stripping`
   - Crear `5-build-ffmpeg-tvos.sh` dedicado (actualmente reutiliza iOS arm64)

2. **Optimizacion del pipeline de transmuxing**
   - Subir QoS del remux thread a `.userInteractive`
   - Probesize/analyzeduration adaptativos: 5MB/5s (local) vs 32MB/30s (red)
   - HDR side_data passthrough en el remux loop (actualmente se pierde)
   - Audio bitrate adaptativo en transcoding AC3/EAC3/DTS→AAC

3. **Robustez de red**
   - Retry logic en `av_read_frame` para streams IPTV (EAGAIN retry, timeout reconexion)
   - Reabrir conexion buscando ultimo keyframe en caso de timeout

4. **Refactor FFI / Type Safety**
   - `~Copyable` wrappers para `AVFormatContext`, `AVPacket` (prevenir use-after-free)
   - `TransmuxError` enum granular con todos los failure modes
   - Verificar si runtime layout detection (s_stream_shift/s_cp_shift) sigue siendo necesario con build propio
   - `TransmuxOptions` struct centralizada (inspirado en KSOptions de KSPlayer)
   - `TransmuxState` enum formal para estados del pipeline

5. **xcframeworks + distribucion**
   - Activar `4-build-xcframeworks.sh` y migrar Package.swift a binary targets
   - Eliminar `unsafeFlags(["-L", ...])` del Package.swift
   - Resultado: distribucion limpia, compatible con SPM binary targets

6. **Tests de TransmuxCore**
   - Unit tests: seeking accuracy, A/V sync, timestamp rebasing
   - Tests de codec coverage: H.264, H.265, AAC, AC3, EAC3, DTS
   - Integration tests: AVPlayer + transmux pipeline completo
   - Benchmark suite: medir tiempo de inicio, throughput MB/s, latencia de seek

7. **Benchmarks y profiling**
   - Instruments: CPU, memoria, I/O durante transmux de archivos representativos
   - Comparar antes/despues de optimizaciones
   - Documentar: throughput en M1 vs A15 vs A17 Pro

### Fase 1 -- Features Estructurales (v1.0)

1. **Provider Factory + Multi-source merge**
   - Refactorizar `MovieService` a protocolo abstracto `ContentSourceProtocol`
   - Implementar `XtreamCodesSource` (refactor del existente)
   - Implementar `M3USource` con parser M3U/M3U8 + EPG XML
   - `UnifiedCatalogManager` para merge y deduplicacion
   - UI de gestion de fuentes (anadir/editar/eliminar)

2. **iCloud Sync full**
   - CloudKit para favoritos, progreso VOD, playlists, settings
   - `NSUbiquitousKeyValueStore` para settings ligeros
   - Sincronizacion bidireccional iOS/tvOS/macOS

3. **EPG mejorado**
   - Grid view completo con timeline
   - Soporte EPG externo (URL custom por fuente)
   - La infraestructura existe (`EPGService.swift`, `EPGXMLParser.swift`)

4. **MP4 nativo bypass**
   - Skip transmux para archivos que ya son MP4/MOV nativos
   - Usar `AVAssetReader` directo → AVPlayer sin overhead de FFmpeg
   - Deteccion automatica en `PlayerFactory`

### Fase 2 -- Features de Competencia (v1.1)

1. **Stremio Addon Client**
   - `StremioAddonClient` actor con fetch manifest/catalog/streams/search
   - Modelos Codable para todo el protocolo
   - UI para anadir addons por URL
   - Integracion en `UnifiedCatalogManager`

2. **WebDAV/FTP/SMB Browse + Stream**
   - Integrar `amosavian/FileProvider` como SPM dependency
   - UI de browse de red local (NAS/servidores)
   - Playback directo via URL (WebDAV) o proxy (FTP/SMB)
   - Discovery Bonjour/mDNS para servidores locales

3. **RealDebrid Integration**
   - OAuth2 device flow authentication
   - Unrestrict link → stream URL
   - Como fuente en `UnifiedCatalogManager`

4. **Siri Shortcuts + App Intents**
   - "Oye Siri, pon la F1 en MKS"
   - "Siri, reproduce canal noticias"
   - "Siri, anade a favoritos"
   - Donation de intents para sugerencias proactivas

5. **Live Activity Sports avanzado**
   - Scoreboards en Dynamic Island con modulo Football existente

6. **Guardar descargas en Photos / ubicacion custom**
   - PHPhotoLibrary integration
   - UIDocumentPickerViewController
   - Metadata preservada en archivo

### Fase 3 -- Liderazgo (v2.0)

1. **SharePlay** -- Ver streams sincronizados via FaceTime (referencia: KSPlayer expone `AVPlaybackCoordinator`)
2. **Recording ligero local** -- Usando pipeline de transmux existente
3. **DLNA/Cast testing real + refinamiento** -- Samsung Tizen, LG webOS, Sony, Chromecast Gen 3+
4. **Parental controls** -- PIN por perfil, filtro por categoria
5. **Trakt integration** -- Scrobbling automatico, historial sincronizado
6. **PiP navigation restoration** -- Copiar patron KSPlayer (pop/push/present al cerrar PiP)

### Lo que NO priorizaria

- **VPN integrado (como UHF)**: Scope creep. Los usuarios tienen VPNs dedicadas.
- **SMB2 completo al nivel de Infuse**: La lib FileProvider tiene SMB2 parcial. No invertir en completarlo -- WebDAV cubre el 90% de NAS modernos.
- **Vision Pro**: Mercado tiny. Foco en iOS/tvOS/macOS primero.
- **Reescribir TransmuxCore en Swift puro**: FFmpeg es insustituible para multi-formato. No hay alternativa viable (ver seccion 7.6).
- **VideoToolbox en TransmuxCore**: No decodifica video -- AVPlayer maneja su propio rendering. VideoToolbox es irrelevante para transmuxing.

---

## 7. Auditoria Tecnica Profunda: TransmuxCore vs KSPlayer (Marzo 2026)

> Basado en estudio exhaustivo del codigo fuente de ambos proyectos. TransmuxCore: 6,960 LOC (4 ficheros principales). KSPlayer MEPlayer: ~15,000+ LOC de integracion FFmpeg.

### 7.1 Diferencia Fundamental de Arquitectura

**KSPlayer (MEPlayer)**: FFmpeg como **decoder** -- decodifica video/audio a frames raw, renderiza via Metal/AudioUnit.
```
Archivo → FFmpeg avcodec_send_packet/receive_frame → CVPixelBuffer (VideoToolbox GPU) → Metal Texture → Pantalla
```

**MKS TransmuxCore**: FFmpeg como **transmuxer** -- reempaqueta sin decodificar, alimenta AVPlayer nativo.
```
Archivo → FFmpeg av_read_frame → av_interleaved_write_frame (fMP4) → NWListener HTTP → AVPlayer nativo
```

**Implicacion critica**: TransmuxCore NO decodifica video. No necesita VideoToolbox ni Metal. Su cuello de botella es I/O (lectura de red/disco + escritura de fMP4), no GPU. Esto es una ventaja (menos CPU, sin GPU) pero limita las optimizaciones aplicables: muchos trucos de KSPlayer (VideoToolbox HW accel, pixel buffer pools, Metal shaders) son irrelevantes para transmuxing.

### 7.2 Auditoria del C Bridge (FFmpegStreamHelper.c -- 1,600 LOC)

**Estado actual: Produccion-grade con una solucion ingeniosa pero fragil.**

#### Runtime Layout Detection (Lineas 127-266)

**Problema**: Los headers de FFmpeg pueden definir `AVStream` y `AVCodecParameters` con o sin el campo `av_class` como primer miembro. Si los headers no coinciden con el binario compilado, todos los offsets de campos se desplazan ±8 bytes.

**Solucion actual**: Probing de memoria raw en runtime. Lee punteros candidatos en dos offsets posibles, valida que `codec_type` y `codec_id` esten en posiciones consecutivas con valores sanos.

```c
static int s_stream_shift = 0;    // 0 u 8
static int s_cp_shift = 0;        // -8, 0, u 8
// Tres shifts independientes para AVStream y AVCodecParameters
```

**Evaluacion**:
- **Pros**: Funciona contra CUALQUIER combinacion de header/binary mismatch. Extremadamente defensivo.
- **Contras**: Es un workaround por usar headers que no corresponden al binario. Si compilas FFmpeg 8 desde source con tus propios headers (como ya haces), este problema **no deberia existir**. El runtime detection es herencia de cuando usabas binarios pre-compilados de FFmpegKit.
- **Recomendacion**: Mantener como safety net pero investigar si con tu build propio (Scripts/0-config.sh → FFmpeg 8.0.1 source) el shift es siempre 0. Si es asi, simplificar a un assert en debug builds.

#### Field Access Pattern (Lineas 268-299)

Todos los accesos a campos de FFmpeg pasan por funciones wrapper:

```c
static void *read_stream_ptr(const AVStream *s, size_t header_offset);
static int read_cp_int(const AVCodecParameters *cp, size_t header_offset);
static AVRational read_stream_rational(const AVStream *s, size_t header_offset);
```

**Evaluacion**: Correcto y necesario dado el layout detection. Si se confirma shift=0 con builds propios, podria simplificarse a acceso directo a campos.

#### Codecpar Copy Fallback (Lineas 438-514)

```c
// Intenta avcodec_parameters_copy() primero
// Si produce basura, fallback a raw memcpy() + duplicacion manual de extradata
```

**Evaluacion**: memcpy de un struct opaco de FFmpeg es fragil entre versiones. Funciona en FFmpeg 8.0.1 pero podria romper en 9.x si cambia el layout interno de AVCodecParameters. Documentar la version de FFmpeg contra la que se valido.

#### Audio Transcoding (AC3/EAC3/DTS → AAC)

```c
mks_audio_transcoder_create()   // Decoder + SwrContext + AAC encoder
mks_audio_transcoder_send()     // Decode → resample → encode
mks_audio_transcoder_receive()  // Get AAC packet
```

**Evaluacion**: Implementacion correcta. AAC a 192kbps fijo. Podria beneficiarse de:
- Bitrate adaptativo segun input (DTS 5.1 a 192k pierde mucho)
- Opcion de AAC-LC vs HE-AAC para streams de bajo bitrate

### 7.3 Build System: FFmpeg 8.0.1 desde Source

**Scripts/0-config.sh** (verificado):

```bash
FFMPEG_VERSION="8.0.1"
MACOS_DEPLOYMENT_TARGET="12.0"
IOS_DEPLOYMENT_TARGET="12.0"

FFMPEG_CONFIGURE_FLAGS="
    --disable-debug
    --disable-programs
    --disable-doc
    --enable-pic
    --disable-encoder=vvc
    --disable-decoder=vvc
    --enable-cross-compile
"
```

**HALLAZGOS CRITICOS en build scripts (verificados en codigo):**

| Problema | Fichero:Linea | Detalle |
|----------|---------------|---------|
| **iOS DESHABILITA VideoToolbox y AudioToolbox** | `3-build-ffmpeg-ios.sh:97-98` | `--disable-audiotoolbox --disable-videotoolbox` -- bloquea futuro HW accel en iOS |
| **Bitcode habilitado en iOS** | `3-build-ffmpeg-ios.sh:68` | `-fembed-bitcode` -- Apple elimino bitcode en Xcode 14, hincha binary sin beneficio |
| **Deployment targets obsoletos** | `0-config.sh:56-57` | macOS 12.0, iOS 12.0 pero app target es macOS 14+, iOS 17+ -- pierde optimizaciones de compilador |
| **tvOS reutiliza iOS binary** | `Package.swift:59` | `-L .../ios/arm64` para tvOS -- build incorrecto (diferente SDK/runtime) |
| **Sin optimizacion de CPU** | `2/3-build-ffmpeg-*.sh` | Falta `-mcpu=apple-m1` (macOS) / `-mcpu=apple-a15` (iOS) |
| **Sin LTO** | `0-config.sh` | Falta `--enable-lto` -- 5-15% binary mas grande, peor inlining |
| **Sin nivel O3** | `2/3-build-ffmpeg-*.sh` | Default `-O2` probable -- suboptimo para hotpaths de parsing |

**Evaluacion critica -- flags que FALTAN en 0-config.sh:**

| Flag | Efecto | Impacto |
|------|--------|---------|
| `--disable-avdevice` | No se usa (no capturas video). Ahorra ~500KB en .a | Tamano binario |
| `--disable-swscale` | No se usa (no reescalas video). Ahorra ~1MB | Tamano binario |
| `--disable-avfilter` | Solo se usa el BSF de AAC ADTS→ASC, que esta en avcodec, no avfilter | Tamano binario |
| `--enable-videotoolbox` | **Habilita hwaccel aunque no decodifiques** -- util para future-proofing | Futuro |
| `--enable-lto` | Link-Time Optimization cross translation units | +10-20% reduccion |
| `--enable-asm --enable-neon` | Garantiza SIMD paths ARM NEON activos | Rendimiento |
| `--enable-stripping` | Dead code elimination | Tamano binario |
| `--disable-everything` + `--enable-demuxer=...` | Build minimo: solo demuxers/muxers/codecs que usas | Tamano: ~60% reduccion |

**Build minimo recomendado para transmuxing puro:**

```bash
# Solo lo que TransmuxCore realmente usa
--disable-everything
--enable-demuxer=matroska,mov,mpegts,avi,flv,hls
--enable-muxer=mp4,mov,mpegts,hls
--enable-decoder=aac,ac3,eac3,dts
--enable-encoder=aac
--enable-parser=aac,h264,hevc,ac3
--enable-bsf=aac_adtstoasc,h264_mp4toannexb,hevc_mp4toannexb
--enable-protocol=file,http,https,hls,tcp,tls
--enable-filter=aresample
```

**Impacto estimado**: Binario de ~3-5MB en lugar de ~15-20MB (con todos los codecs).

### 7.4 Lo que KSPlayer hace bien y es aplicable a TransmuxCore

#### A) Aplicable directamente

| Optimizacion KSPlayer | Aplicacion en TransmuxCore | Prioridad |
|------------------------|---------------------------|-----------|
| **`AV_CODEC_FLAG2_FAST`** en decoders | Aplicar al decoder AAC interno cuando se hace transcoding AC3→AAC | Media |
| **`lowres` option** | No aplica (no decodifica video) | N/A |
| **CVPixelBuffer pools** | No aplica (no genera frames) | N/A |
| **Circular buffer lock-free** | Podria reemplazar la cola de segmentos en HLSSegmenter.segments para reducir contention | Baja |
| **Serial OperationQueue** (QoS .userInteractive) | Tu DispatchQueue.global(qos: .userInitiated) es equivalente. Subir a .userInteractive para el remux thread | Alta |
| **VideoToolbox HW accel** | No aplica para transmuxing. PERO: si en futuro decodificas para thumbnails/preview, copiar este patron | Futuro |
| **HDR metadata propagation** | Copiar side_data de input a output en el remux loop (actualmente se ignora). Importante para HDR passthrough | Alta |
| **Error recovery (session recreation)** | Anadir retry logic en av_read_frame failures para streams de red inestables. Actualmente falla y cierra | Alta |
| **`swr_alloc_set_opts2`** | Tu audio transcoder ya usa SwrContext pero no se verifico si usa la API v2. Migrar si no. | Media |

#### B) Patrones de arquitectura a adoptar

| Patron KSPlayer | Como implementar en MKS |
|-----------------|-------------------------|
| **`KSOptions` centralizada** | Crear `TransmuxOptions` struct con todas las settings: `targetSegmentDuration`, `maxProbeSize`, `audioTranscodeBitrate`, `seekCooldown`, etc. Actualmente dispersas como constantes. |
| **`MediaLoadState` enum** | Tu `ActiveTransmux` tiene estados implicitos. Formalizar: `.preparing` → `.probing` → `.headerReady` → `.streaming` → `.complete` → `.error(TransmuxError)` |
| **PiP navigation restoration** | Ya tienes PiP. Copiar el patron pop/push/present de KSPictureInPictureController para restore seamless. |
| **Dual-backend selection** | Tu `PlayerFactory` ya selecciona. Refinar: si formato es MP4 nativo → AVPlayer directo (sin transmux). Si MKV → transmux. Si stream inestable → VLC fallback. Decision automatica con override manual. |
| **Sendable protocol** | TransmuxingService es `actor` (bien). Pero ActiveTransmux no es Sendable — podria causar warnings en Swift 6 strict. Auditar. |

#### C) No aplicable / No copiar

| KSPlayer | Por que no |
|----------|-----------|
| Metal shaders para YUV→RGB | TransmuxCore no renderiza — AVPlayer hace su propio rendering |
| FFmpegKit como SPM dependency | Tu ya compilas FFmpeg 8 desde source. FFmpegKit usa FFmpeg 6.x y trae overhead de wrappers ObjC innecesarios |
| `VTDecompressionSession` | No decodificas video. Si lo hicieras, ya usarias AVPlayer que maneja VideoToolbox internamente |
| NAL unit size conversion | Tu transmuxer copia video as-is. AVPlayer maneja NAL parsing |
| Auto-deinterlace via yadif | No aplica — no filtras video |

### 7.5 Optimizaciones de Rendimiento para TransmuxCore

#### Nivel 1: Immediato (sin cambiar FFmpeg build)

1. **QoS del remux thread**: Subir de `.userInitiated` a `.userInteractive`
   - Impacto: Prioridad de scheduling mas alta, menos latencia de inicio
   - Riesgo: Minimo

2. **Probesize y analyzeduration adaptivos**:
   - Actual: probesize=32MB, analyzeduration=30s (fijos)
   - Optimizacion: Para archivos locales → 5MB/5s. Para streams de red → 32MB/30s.
   - Impacto: Reduccion de tiempo de inicio de ~2-5s para archivos locales

3. **HDR metadata passthrough en remux loop**:
   - Copiar side_data (HDR10, HDR10+, Dolby Vision) de input packets a output packets
   - Actualmente se pierden. AVPlayer puede aprovecharlas para tone mapping correcto

4. **Retry logic en av_read_frame**:
   - Actual: fallo → cierra transmux
   - Mejora: Para EAGAIN → reintentar 3 veces con backoff. Para timeout → reabrir conexion y buscar ultimo keyframe.

5. **Audio bitrate adaptativo**:
   - Actual: 192kbps AAC fijo
   - Mejora: DTS 5.1 → 384kbps AAC. AC3 stereo → 128kbps AAC. EAC3 → 256kbps AAC.

#### Nivel 2: Optimizacion del build FFmpeg

6. **Build minimo** (ver seccion 7.3):
   - Solo demuxers/muxers/codecs que se usan realmente
   - Reduccion de ~70% en tamano de binario estático
   - Beneficio colateral: menos superficie de ataque de seguridad

7. **Flags de optimizacion de compilacion**:
   ```bash
   # Para Apple Silicon (arm64)
   --extra-cflags="-O3 -march=armv8.4-a+crypto+sha3 -mtune=apple-m1"
   # Para iOS (arm64 generico)
   --extra-cflags="-O3 -march=armv8-a"
   ```
   - Impacto: 5-15% mas rapido en operaciones de parsing/remuxing
   - Nota: `armv8.4-a` es el minimo de M1. Si soportas A11+ (iPhone 8+) usa `armv8.2-a`

8. **Platform detection en runtime**:
   ```swift
   // Detectar Apple Silicon vs Intel vs A-series
   import Darwin
   var sysinfo = utsname()
   uname(&sysinfo)
   let machine = String(cString: &sysinfo.machine.0)
   // "arm64" en todos los Apple Silicon, pero puedes diferenciar:
   // ProcessInfo.processInfo.activeProcessorCount para thread tuning
   ```

9. **Link-Time Optimization (LTO)**:
   ```bash
   --enable-lto  # FFmpeg configure flag
   --extra-cflags="-flto=thin"
   ```
   - Permite al compilador optimizar across translation units
   - Puede reducir binario 10-20% adicional

#### Nivel 3: Arquitectura avanzada

10. **Mmap para lectura de archivos locales**:
    - Actual: FFmpeg usa read() syscalls via avio
    - Alternativa: Para archivos locales, usar mmap() para zero-copy I/O
    - Implementacion: Custom AVIOContext con read_packet callback que usa mmap
    - Impacto: Significativo para archivos grandes (10GB+ MKV)

11. **DispatchIO para escritura de fMP4**:
    - Actual: FFmpeg escribe via avio a archivo
    - Alternativa: Custom avio_write callback que usa DispatchIO para escritura asincrona
    - Beneficio: No bloquea el remux thread en I/O de disco

12. **Pipeline con double-buffering**:
    - Actual: lee → escribe → lee → escribe (secuencial)
    - Mejora: Buffer de N packets, lee en batch, escribe en batch
    - Implementacion: Circular buffer entre reader y writer threads

### 7.6 Alternativas y Complementos a FFmpeg

#### Alternativas evaluadas

| Alternativa | Descripcion | Viabilidad para TransmuxCore |
|-------------|-------------|------------------------------|
| **libav** (fork de FFmpeg) | Mismo codebase, divergio en 2011 | **No**. Comunidad muerta, FFmpeg es estrictamente superior. |
| **GStreamer** | Pipeline multimedia modular | **No para iOS**. Sin soporte oficial Apple. Binarios enormes (~100MB). |
| **MediaParser (Apple)** | AVAssetReader + AVAssetWriter | **Parcial**. Solo MP4→MP4. No soporta MKV input. No soporta MPEG-TS input bien. |
| **MP4Box (GPAC)** | Herramienta de manipulacion MP4 | **No como libreria**. CLI-only. Compilar como lib requiere esfuerzo enorme. |
| **libmatroska + libebml** | Parser MKV nativo C++ | **Posible complemento**. Para parsing de MKV puro sin FFmpeg. Pero FFmpeg ya lo hace bien. |
| **swift-media (hipotetico)** | Parser puro Swift | **No existe**. Escribir un MKV→fMP4 transmuxer en Swift puro seria ~10K LOC y anos de debugging. |

#### Veredicto: FFmpeg es la unica opcion viable

FFmpeg 8 es insustituible para transmuxing multi-formato en Apple platforms. No hay alternativa realista. Lo que SI se puede hacer:

1. **Reducir dependencia**: Build minimo con solo los demuxers/muxers/codecs necesarios
2. **Complementar con Apple APIs**: Usar `AVAssetReader` para archivos que ya son MP4 nativos (skip transmux entirely)
3. **Abstraer el bridge**: Aislar toda la interaccion FFmpeg en `CFFmpegHelper` (ya hecho) para que si surge alternativa futura, solo se reemplaza ese modulo

### 7.7 Auditoria FFI / xcframeworks

#### Estado actual del FFI

| Aspecto | Estado | Evaluacion |
|---------|--------|-----------|
| **C → Swift bridge** | Via SPM target `CFFmpegHelper` con `publicHeadersPath` | Correcto. Patron estandar. |
| **Tipo de punteros** | `void*` para AVFormatContext (evita conflictos de header) | Correcto pero pierde type safety. |
| **Memory ownership** | C alloca, C libera (avformat_close_input, av_packet_free) | Correcto. No hay mixed ownership. |
| **Thread safety** | Un AVFormatContext por thread. No comparten contextos. | Correcto. FFmpeg no es thread-safe por contexto. |
| **Error propagation** | FFmpeg int → Swift throw TransmuxError | Correcto. Podria mapear errores FFmpeg a enum cases mas granulares. |
| **Static libs** | .a files per-platform, linked via -L paths | Correcto. xcframeworks NO usados actualmente (static .a directos). |

#### Recomendaciones FFI

1. **Migrar a xcframeworks**: Los scripts ya tienen `4-build-xcframeworks.sh` pero no se usan. xcframeworks permitirian:
   - Un solo artefacto con todas las platforms (macOS arm64 + iOS arm64 + iOS simulator)
   - Distribucion mas limpia via SPM binary targets
   - Eliminacion de los `unsafeFlags(["-L", ...])` en Package.swift

2. **Type-safe wrappers**: Reemplazar `void*` por tipos opacos Swift:
   ```swift
   struct FFmpegInputContext: ~Copyable {
       private let ptr: OpaquePointer
       deinit { /* avformat_close_input */ }
   }
   ```
   - Previene use-after-free por diseno
   - Swift 6 `~Copyable` es perfecto para esto

3. **Error enum granular**:
   ```swift
   enum TransmuxError {
       case inputOpenFailed(ffmpegCode: Int32, url: String)
       case streamInfoFailed(ffmpegCode: Int32)
       case noVideoStream
       case noAudioStream
       case headerWriteFailed(ffmpegCode: Int32)
       case readFrameTimeout
       case readFrameEOF
       case audioTranscodeFailed(codec: String, ffmpegCode: Int32)
       // etc.
   }
   ```

### 7.8 KSPlayer -- Estudio Completo de Arquitectura

#### Arquitectura (verificada del codigo fuente)

```
KSPlayer/Sources/KSPlayer/
├── AVPlayer/
│   ├── KSAVPlayer.swift            -- AVPlayer wrapper (PiP, AirPlay, rate, volume)
│   ├── KSPictureInPictureController.swift -- PiP con navigation restoration (pop/push/present)
│   ├── KSPlayerLayer.swift         -- State machine (8 estados), Published properties para SwiftUI
│   └── KSPlayerLayerDelegate       -- Callbacks: state, currentTime, finish, bufferedCount
├── MEPlayer/
│   ├── FFmpegDecode.swift          -- avcodec_send_packet/receive_frame loop
│   ├── VideoToolboxDecode.swift    -- VTDecompressionSession con async decode
│   ├── Resample.swift              -- sws_scale + CVPixelBuffer pool + Audio SwrContext
│   ├── Filter.swift                -- AVFilterGraph (yadif deinterlace, scale, atempo)
│   ├── CircularBuffer.swift        -- Ring buffer lock-free, power-of-2, sorted option
│   └── AVFFmpegExtension.swift     -- Swift-C bridge, 40+ pixel format mappings
├── SwiftUI/                        -- SwiftUI views
└── Subtitle/                       -- Subtitle handling
```

#### Pipeline MEPlayer (FFmpeg decode path)

```
av_read_frame(packet)
    → avcodec_send_packet(codecContext, packet)
    → avcodec_receive_frame(codecContext, frame)
    → [Optional] AVFilterGraph (deinterlace, scale)
    → [Video] VTDecompressionSession → CVPixelBuffer (IOSurface-backed, Metal-compatible)
    → [Audio] swr_convert() → AudioFrame → AudioUnit
    → CircularBuffer<VideoFrame> / CircularBuffer<AudioFrame>
    → Render thread: Metal texture from CVPixelBuffer (zero-copy)
```

#### Key Technical Details

| Area | Detalle |
|------|---------|
| **FFmpeg version** | FFmpegKit 6.1.3+ via SPM (FFmpeg 6.x, no 8.x) |
| **Hardware accel** | `AV_HWDEVICE_TYPE_VIDEOTOOLBOX` + `VTDecompressionSessionDecodeFrame(flags: ._EnableAsynchronousDecompression)` |
| **Metal integration** | `kCVPixelBufferMetalCompatibilityKey: true` + `kCVPixelBufferIOSurfacePropertiesKey` → zero-copy GPU |
| **HDR support** | Per-frame extraction: HDR10, HDR10+, Dolby Vision, ambient viewing environment metadata |
| **Closed captions** | Auto-detect via `FF_CODEC_PROPERTY_CLOSED_CAPTIONS` → create subtitle track dynamically |
| **Buffer strategy** | `CircularBuffer<T>` con `ContiguousArray`, power-of-2 capacity, `UInt wrapping subtraction` para counters |
| **Thread model** | Serial `OperationQueue` (maxConcurrent=1, QoS=.userInteractive) para open/read/close. Decoders en threads dedicados. |
| **Clock sync** | Audio-primary: audio clock es referencia, video se ajusta (skip/duplicate frames) |
| **Error recovery** | `VTInvalidSessionErr` → recrear session automaticamente. Background/foreground transitions manejados. |
| **Codec flags** | `AV_CODEC_FLAG2_FAST` siempre. `AV_CODEC_FLAG_LOW_DELAY` opcional. `lowres` 1-4 para resolucion reducida. |
| **Pixel formats** | 40+ mappings AVPixelFormat → CVPixelFormatType (NV12, P010LE, BGRA, etc.) |
| **macOS extras** | `VTRegisterProfessionalVideoWorkflowVideoDecoders()` + supplemental decoders |
| **Color space** | BT.709, BT.2020, SMPTE-C, DCI-P3 con fallback a `CVColorPrimariesGetStringForIntegerCodePoint` |

### 7.9 Patrones Utiles para MKS-IPTV (Resumen Accionable)

| # | Accion | Origen | Esfuerzo | Impacto |
|---|--------|--------|----------|---------|
| 1 | Subir QoS remux thread a `.userInteractive` | KSPlayer threading | Trivial | Latencia |
| 2 | Probesize/analyzeduration adaptativos (local vs red) | Analisis propio | Bajo | Tiempo inicio |
| 3 | HDR side_data passthrough en remux loop | KSPlayer HDR propagation | Medio | Calidad HDR |
| 4 | Retry logic en av_read_frame para streams de red | KSPlayer error recovery | Medio | Estabilidad |
| 5 | Audio bitrate adaptativo en transcoding | Analisis propio | Bajo | Calidad audio |
| 6 | Build minimo FFmpeg (solo codecs usados) | Analisis propio | Medio | -70% tamano |
| 7 | `-O3 -march=armv8.2-a` en CFLAGS | Optimizacion estandar | Bajo | +5-15% velocidad |
| 8 | LTO (`--enable-lto`) | Optimizacion estandar | Bajo | +10-20% tamano |
| 9 | `TransmuxOptions` struct centralizada | KSPlayer KSOptions | Medio | Mantenibilidad |
| 10 | `TransmuxState` enum formal | KSPlayer MediaLoadState | Bajo | Claridad |
| 11 | `~Copyable` type-safe FFmpeg wrappers | Swift 6 best practice | Alto | Seguridad |
| 12 | Migrar a xcframeworks | Build system maturity | Medio | Distribucion |
| 13 | Verificar si runtime shift detection sigue siendo necesario | Analisis propio | Bajo | Simplificacion |
| 14 | PiP navigation restoration pattern | KSPlayer PiP controller | Medio | UX |
| 15 | Skip transmux para MP4 nativo (AVAssetReader directo) | Analisis propio | Alto | Performance |

### Posibles Contribuciones Open-Source a KSPlayer

1. **Single-connection proxy pattern** -- Documentar como hacer proxy HLS para evitar double-connection en AirPlay
2. **GlitchDetector integration** -- Proponer interface para monitoring reactivo de playback
3. **Transmux MKV→fMP4 pipeline** -- Si open-sources TransmuxCore, podria integrarse como alternativa al decode directo

---

## 8. Estrategia Open-Source + Portfolio

### Open-source inmediato (GitHub, MIT o LGPL)

| Componente | Justificacion |
|------------|---------------|
| **TransmuxCore** | No existe equivalente open-source. Atrae contribuciones y visibilidad. |
| **LiveHLSProxy** | Resuelve problema real documentado. Util para cualquier app IPTV. |
| **GlitchDetector** | Componente reutilizable para cualquier AVPlayer app. |
| **StremioAddonClient** (cuando este listo) | Primer cliente Stremio nativo en Swift. Alto impacto. |

### Contribuciones externas

- **KSPlayer**: PRs de single-connection proxy, glitch detection, transmux pipeline
- **amosavian/FileProvider**: PRs de SMB2 completeness si se encuentra necesidad

### App completa

- GitHub source-available + App Store gratis + IAP Pro

---

## 9. Monetizacion Minima (Realista)

**Objetivo**: Recuperar los 99EUR/ano de Apple Developer, no mas.

| Modelo | Detalle |
|--------|---------|
| **Free + Tip Jar** | IAP "Coffee for the dev" (2.99EUR one-time) |
| **Pro unlock** (opcional) | 5.99EUR one-time: multi-source merge, iCloud Sync, Stremio addons |
| **GitHub Sponsors** | Para el core open-source |

---

## 10. Conclusion: Valoracion Final (v3)

### Es un producto viable? SI, con matices.

**Fortalezas reales verificadas:**
- TransmuxCore es genuinamente unico. No existe equivalente open-source ni comercial en iOS.
- LiveHLSProxy resuelve un dolor real y documentado que la competencia ignora.
- La arquitectura es produccion-grade (185 ficheros, modulos separados, actors, protocol abstraction).
- El stack Football + Live Activities + Liquid Glass + TouchBar es diferenciador.
- El sistema de descargas (concurrente + transmux + Live Activities + metadata multi-provider) es el mas completo.
- DLNA + Cast nativos en Swift (sin SDK pesado) es tecnica avanzada.

**Estado del core tecnico (post-auditoria):**
- El C bridge (FFmpegStreamHelper.c) es **produccion-grade** con runtime layout detection ingeniosa.
- El build de FFmpeg esta **sobredimensionado**: compila TODOS los codecs cuando solo usa ~10. Build minimo reduciria ~70% el tamano.
- No hay optimizaciones de compilacion arm64 (faltan -O3 -march flags).
- El pipeline de transmuxing es correcto pero falta: HDR passthrough, retry logic, probesize adaptativo.
- El FFI es funcional pero no type-safe: void* pointers, error codes como Int.
- No hay xcframeworks -- distribucion con unsafeFlags.
- KSPlayer usa FFmpeg como **decoder** (irrelevante para transmuxing) pero sus patrones de arquitectura (KSOptions, MediaLoadState, error recovery, PiP restoration) son directamente aplicables.

**Riesgos reales que gestionar:**
- IPTVX tiene anos de ventaja. No vas a igualarlo en v1.0.
- Discovery/marketing es el cuello de botella, no la tecnologia.
- Apple puede retirar apps IPTV. Open-source el core mitiga.
- Tests insuficientes para TransmuxCore.
- La API es Xtream-only -- el refactor a multi-source es el primer paso critico.
- **El binario FFmpeg es ~15-20MB innecesariamente** -- afecta tamano de app y review de App Store.

**Veredicto:**

**Solidificar TransmuxCore primero** es la decision correcta. Es tu moat tecnico y todo lo demas depende de el. Las optimizaciones identificadas (build minimo, CFLAGS, HDR passthrough, retry logic, type-safe FFI, xcframeworks) no son enormes individualmente pero en conjunto transforman TransmuxCore de "funciona" a "state of the art".

Publicar merece la pena como **proyecto tecnico + portfolio**. El retorno real no es financiero -- es demostracion de capacidad.

Con las adiciones del roadmap (primero optimizar core, luego multi-source merge, Stremio addons, WebDAV/FTP, RealDebrid, iCloud Sync), la app pasa de ser un "player superior" a ser un **hub de contenido completo** que combina las mejores ideas de cada competidor (Chillio: multi-source, UHF: Stremio, IPTVX: iCloud/EPG, GSE: DLNA) con tu ventaja tecnica unica (transmux nativo + single proxy + glitch detection).

Open-source TransmuxCore + LiveHLSProxy + (futuro) StremioAddonClient puede tener mas impacto que la app en el App Store.

**La app es el showcase. Los frameworks son el producto real. Primero hazlos impecables. Luego anade features.**

---

## Fuentes de Investigacion

- [IPTVX App Store](https://apps.apple.com/us/app/iptvx/id1451470024) -- v21.5.1, changelog verificado
- [UHF App Store](https://apps.apple.com/us/app/uhf-love-your-iptv/id6443751726) -- Features y reviews
- [Snappier IPTV App Store](https://apps.apple.com/us/app/snappier-iptv/id1579702567) -- KSPlayer/VLC/MPV confirmado
- [Chillio App Store](https://apps.apple.com/us/app/chillio-iptv-smart-player-pro/id6478813450) -- Multi-source merge
- [KSPlayer GitHub](https://github.com/kingslay/KSPlayer) -- Clonado y estudiado, GPL/LGPL
- [Stremio Addon SDK](https://github.com/Stremio/stremio-addon-sdk) -- Protocolo completo documentado
- [Stremio-iOS (unofficial)](https://github.com/rcastriotta/Stremio-iOS) -- Referencia consumo addons
- [amosavian/FileProvider](https://github.com/amosavian/FileProvider) -- WebDAV/FTP/SMB Swift, MIT
- [Real-Debrid API](https://api.real-debrid.com/) -- Documentacion oficial
- [IINA GitHub](https://github.com/iina/iina) -- v1.4.1, macOS-only
- [TROYPOINT - UHF Review](https://troypoint.com/uhf-iptv-app/) -- Features y pricing 2026
- [TROYPOINT - Snappier Review](https://troypoint.com/snappier-iptv/) -- Player backends
- [TROYPOINT - RealDebrid Guide](https://troypoint.com/real-debrid/) -- Setup 2026
- [iptv-proxy (kvaster)](https://github.com/kvaster/iptv-proxy) -- Proxy server-side referencia
- [tuliprox](https://github.com/euzu/tuliprox) -- Proxy Rust con grace period
- [IPTV-Restream](https://github.com/antebrl/IPTV-Restream) -- Restream con ffmpeg
- [Empire Metrics - Best IPTV Players 2026](https://empire-metrics.com/best-iptv-players/)
- [StreamMaster - Best IPTV Apps iPhone 2026](https://streammaster.app/blog/best-iptv-player-apps-iphone-2026/)
- [Stremio Addon Protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md)

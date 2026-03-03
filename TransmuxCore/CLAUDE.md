# TransmuxCore — CLAUDE.md

Swift Package que envuelve FFmpeg 8.0.1 (compilado desde source como static libraries) para hacer transmuxing de contenedores (MKV → fMP4/HLS) sin re-encoding. Se integra como dependencia local del proyecto principal MKS-IPTV-App (iOS, macOS, tvOS).

## Contexto en el proyecto

TransmuxCore es un **módulo aislado** dentro del monorepo MKS-IPTV-App. Su única responsabilidad es:

1. Abrir un input (fichero local o URL HTTP/S)
2. Remuxear video+audio a fMP4 fragmentado (progressive MP4)
3. Generar playlist HLS VOD sobre ese fMP4
4. Servir los segmentos via HTTP local (TransmuxServer)
5. Soportar seeking con rebase de timestamps sin reabrir el output

Los targets finales que consumirán este módulo son los ya existentes en el `.xcodeproj` raíz:
- **mks-multiplatform-iptv** (macOS + iOS)
- **mks-multiplataforma-tvos-iptv** (tvOS)

## Build

```bash
# macOS CLI (debug)
cd TransmuxCore
swift build --product transmux-cli

# Ejecutar
.build/debug/transmux-cli "/path/to/file.mkv" --verbose
.build/debug/transmux-cli "/path/to/file.mkv" --seek 300 --duration 20

# Rebuild FFmpeg desde source (solo si es necesario)
cd Scripts && ./build-all.sh --force --skip-download
```

No hay `bun`, `npm`, ni dependencias JS en este módulo. Es Swift + C puro.

## Arquitectura

```
TransmuxCore/
├── Package.swift                     # SPM manifest
├── Frameworks/FFmpeg/
│   ├── include/                      # Headers FFmpeg 8.0.1 (todas las plataformas)
│   ├── lib/
│   │   ├── macos-arm64/              # Static .a (macOS nativo)
│   │   └── ios-universal/            # Fat .a (arm64 device + x86_64 sim)
│   └── xcframeworks/                 # XCFrameworks (para integración Xcode)
├── Scripts/
│   ├── 0-config.sh                   # Variables, helpers, deployment targets
│   ├── 1-download-ffmpeg.sh          # Descarga FFmpeg 8.0.1 source
│   ├── 2-build-ffmpeg-macos.sh       # Build macOS arm64
│   ├── 3-build-ffmpeg-ios.sh         # Build iOS arm64 + x86_64
│   ├── 4-build-xcframeworks.sh       # Crea XCFrameworks + copia libs
│   └── build-all.sh                  # Orquestador (--force, --skip-download, etc.)
└── Sources/
    ├── CFFmpegHelper/                # Wrapper C sobre FFmpeg
    │   ├── FFmpegStreamHelper.c      # Acceso seguro a structs con detección de layout
    │   └── include/
    │       ├── FFmpegStreamHelper.h
    │       └── module.modulemap      # Expone módulos CFFmpegHelper + FFmpeg a Swift
    ├── TransmuxCore/
    │   ├── Core/
    │   │   ├── TransmuxingService.swift   # Entrada principal: open → remux → fMP4
    │   │   ├── TransmuxServer.swift       # HTTP server local + HLS serving
    │   │   ├── HLSSegmenter.swift         # Parseo fMP4 boxes, genera m3u8 VOD
    │   │   ├── ActiveTransmux.swift       # Handle de sesión (cancel, seek signal)
    │   │   └── TransmuxLog.swift          # Logging estructurado
    │   ├── Protocols/
    │   │   └── StreamProxyProtocol.swift  # Protocolo para proxy HTTPS→HTTP
    │   └── TransmuxCore.swift             # Re-exports públicos
    └── transmux-cli/
        └── main.swift                     # CLI de testing
```

### Flujo de datos

```
Input (MKV/MP4 local o URL)
  → avformat_open_input + find_stream_info
  → selección best video + audio streams
  → avformat_write_header (fMP4 fragmented: frag_keyframe+empty_moov)
  → loop av_read_frame → av_interleaved_write_frame
  → HLSSegmenter parsea moof/mdat boxes en tiempo real
  → genera m3u8 VOD con segmentos virtuales
  → TransmuxServer sirve via HTTP (range requests)
  → Seeking: signal via ActiveTransmux → av_seek_frame → rebase DTS/PTS
```

### CFFmpegHelper — Runtime layout detection

`FFmpegStreamHelper.c` no accede a campos de `AVStream`/`AVCodecParameters` directamente. Detecta en runtime si hay un offset de ±8 bytes entre los headers compilados y el binario real (problema histórico de av_class mismatch entre versiones). Con nuestro propio build de FFmpeg 8.0.1 los offsets son 0/0 (match perfecto), pero el mecanismo queda como safety net.

## Pipeline de testing

La CLI es la **primera etapa** de un pipeline de validación:

```
1. transmux-cli (este módulo)
   └─ Valida: remux correcto, seeking, timestamps, A/V sync a nivel FFmpeg
   └─ Output: fMP4 + m3u8 en /tmp/

2. transmux-log-viewer + HLS.js (Vite frontend)
   └─ Valida: serving HTTP, range requests, playback real en browser
   └─ Mide: buffering, segment loading, visual A/V sync
   └─ Consume logs de TransmuxServer para diagnostics

3. Swift AVPlayer (app final)
   └─ Valida: integración real con AVPlayer en iOS/macOS/tvOS
   └─ Mide: start time, seek latency, playback smoothness
```

### Archivos de test

Los ficheros de prueba están en `/Volumes/KODAK1TB/`:

| Fichero | Formato | Uso |
|---------|---------|-----|
| `Crímenes Bellvitge (2026) 1x03.mkv` | MKV (H.264 + 2xAAC) | **Primary** — MKV transmux testing |
| `Crímenes Bellvitge (2026) 1x0{1,2,3}.mp4` | MP4 | Passthrough / baseline |
| `FBI 1080P S63E04.mp4` | MP4 1080p | Bitrate alto |
| Otros `.mp4` en KODAK1TB | MP4 | Variedad de codecs |

Definidos en: `transmux-log-viewer/packages/frontend/mks-iptv-client/src/lib/test-files.ts`

## Trabajo pendiente

### Corto plazo
- **Análisis de serving**: medir cómo se sirve el fMP4 via range requests (byte ranges, timing, cache)
- **Análisis de ficheros**: inspeccionar boxes del fMP4 generado (moov, moof, mdat) para validar estructura
- **Seek testing**: probar --seek a múltiples posiciones, medir precisión de keyframe alignment

### Medio plazo
- **Benchmarks A/V sync**: medir DTS/PTS drift entre video y audio a lo largo del fichero completo
- **Tests con URLs remotas**: validar con streams IPTV reales via StreamProxy
- **Integración log-viewer**: conectar output de TransmuxServer con el frontend HLS.js

### Largo plazo
- **Tests automatizados**: suite de tests con fixtures MKV/MP4 que validen sync, seeking, edge cases
- **Métricas de rendimiento**: throughput (MB/s), latencia de seek, tiempo de primer segmento
- **Integración AVPlayer**: probar en la app Swift real con el TransmuxServer sirviendo localmente

## Convenciones

- **No console.log** — este módulo es Swift/C puro, usa `fprintf(stderr, ...)` en C y `TransmuxLog` en Swift
- **No re-encoding** — TransmuxCore SOLO remuxea, nunca transcodifica
- **Paths relativos en Package.swift** — los `-L` flags apuntan a `Frameworks/FFmpeg/lib/` relativo al package
- **Module map paths** — relativos a `Sources/CFFmpegHelper/include/` (3 niveles hasta package root: `../../../`)

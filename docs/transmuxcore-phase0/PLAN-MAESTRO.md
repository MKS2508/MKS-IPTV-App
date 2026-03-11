# TransmuxCore Phase 0 - Plan Maestro para Superar a KSPlayer

## Resumen Ejecutivo

**Objetivo**: Superar a KSPlayer en rendimiento, eficiencia y patrones de código manteniendo AVPlayer como renderer nativo, soportando el 98%+ de codecs a través de un pipeline inteligente de tiers de encoding/transcoding.

**Ventaja Estratégica**: Tenemos acceso a todo el core y módulos de KSPlayer como referencia, versiones modernas de FFmpeg 6→8, y tiempo/obsesión para superarlo con un enfoque más inteligente.

**Tradeoff Esperado**: Mínimo (<2%) - TransmuxCore será ligeramente menos maduro pero significativamente más eficiente para el 98%+ de casos de uso.

---

## Visión Arquitectural

### Enfoque: TransmuxCore v3 vs KSPlayer

| Aspecto | KSPlayer | TransmuxCore v3 |
|---------|----------|-----------------|
| **Renderer** | Metal propio | AVPlayer nativo (PiP, AirPlay, HDR, Spatial Audio) |
| **Codec Support** | 100% (FFmpeg decode + Metal render) | 98%+ (smart passthrough + selective transcode) |
| **CPU Usage (H.264/H.265)** | FFmpeg decode + Metal | Zero (passthrough) |
| **CPU Usage (VP9/AV1)** | FFmpeg decode + Metal | FFmpeg decode + VideoToolbox encode |
| **Battery** | High | Low (passthrough 85% del tiempo) |
| **Binary Size** | ~50MB+ | ~3-5MB (FFmpeg optimized) |
| **Code Complexity** | Alta (double pipeline) | Media-Arquitectura modular con tiers inteligentes |
| **Maintenance** | Compleja (FFmpeg + Metal + AVPlayer fallback) | Focalizada (FFmpeg + VideoToolbox + AVPlayer) |

### Tiers de Encoding

```
┌─────────────────────────────────────────────────────────────────┐
│                    Decision Matrix por Tier                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Tier 0: Native Passthrough (85% de streams)                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input: H.264/H.265 + AAC/AC3/EAC3 + MP4/MOV/TS          │    │
│  │ Action: Remux only (zero encoding)                      │    │
│  │ Output: Original codec, AVPlayer native decode          │    │
│  │ Performance: 0% CPU, 0% battery impact                 │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Tier 1: Audio-Only Transcode (8% de streams)                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input: Unsupported audio codec (DTS, FLAC, OPUS)        │    │
│  │ Action: Transcode audio to AAC/EAC3 (VideoToolbox)      │    │
│  │ Output: Native video + transcoded audio                  │    │
│  │ Performance: <5% CPU, minimal battery                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Tier 2: Video Transcode Selectivo (5% de streams)              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input: VP9, AV1 (pre-A17/M3), MPEG-2, etc.            │    │
│  │ Action: FFmpeg decode → VideoToolbox encode H.264/H.265 │    │
│  │ Output: H.264/H.265 + audio optimized                   │    │
│  │ Performance: 15-25% CPU, moderate battery               │    │
│  │ Adaptive: Resolution/bitrate según dispositivo/capacidad│  │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Tier 3: Full Transcode (2% de streams)                        │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input: Legacy codecs, corrupted streams, etc.         │    │
│  │ Action: Full pipeline optimization                      │    │
│  │ Output: H.264/H.265 + AAC/EAC3                         │    │
│  │ Performance: 25-40% CPU, higher battery (último recurso)│  │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Fase Preliminar: Research Exhaustivo

### Objetivo
Estudiar a fondo FFmpeg 6→8, VideoToolbox, AVPlayer, y KSPlayer para tomar decisiones arquitectónicas informadas.

### Áreas de Research

#### 1. FFmpeg 6→8 Deep Dive
**Objetivos**:
- Mapear todas las mejoras de FFmpeg 6, 7, y 8 relevantes para video streaming
- Identificar nuevas APIs de VideoToolbox integration
- Documentar mejoras de performance en decoders/encoders
- Analizar nuevas codec capabilities (AV1, VVC, EVC)

**Recursos**:
- [FFmpeg Changelog](https://ffmpeg.org/gitweb) (v6.0 → v8.0)
- FFmpeg API Documentation (avcodec, avformat, avutil, swscale)
- FFmpeg Wiki - Hardware Acceleration
- FFmpeg Source Code (libavcodec, libavformat, libavutil)
- FFmpeg Mailing List Archives
- FFmpeg Conference Talks (VDD, FOSDEM)

**Deliverables**:
- `docs/ffmpeg-research.md` - Documento técnico completo
- Tabla comparativa FFmpeg 6 vs 7 vs 8 (APIs, codecs, performance)
- Listado de nuevas features relevantes para iOS/macOS
- Benchmarks de performance (si disponibles en research)

#### 2. VideoToolbox Mastery
**Objetivos**:
- Mapear todas las capabilities de VideoToolbox en iOS 26/macOS 26
- Documentar APIs de hardware encoding/decoding
- Entender adaptive bitrate con VTCompressionSession
- Investigar low-latency modes para live streaming
- Documentar HDR/10-bit capabilities y limitations

**Recursos**:
- Apple VideoToolbox Framework Documentation
- WWDC Sessions: "Advances in Video Coding", "Hardware Video Encoding"
- Apple Developer Forums (VideoToolbox discussions)
- Technical Notes TN2224, TN2267
- Open Source Projects using VideoToolbox

**Deliverables**:
- `docs/videotoolbox-research.md` - Documento completo de capacidades
- Matrix de capabilities por dispositivo (A17, M1, M2, M3, etc.)
- Code examples: encoder setup, adaptive bitrate, HDR handling
- Performance expectations y limitations

#### 3. AVPlayer Deep Dive
**Objetivos**:
- Documentar todas las codecs nativamente soportados por AVPlayer
- Entender AVPlayer vs AVQueuePlayer vs AVSampleBufferDisplayLayer
- Investigar seamless codec switching (H.264→H.265→VP9)
- Mapear limitations y workarounds conocidos
- Documentar PiP, AirPlay, Spatial Audio, HDR features

**Recursos**:
- Apple AVFoundation Documentation
- AVPlayer Technical Guide (TN2225)
- WWDC Sessions: "Advances in AVFoundation", "Optimizing for AirPlay"
- Apple Developer Forums (AVPlayer discussions)
- Technical Q&A QA1776, QA1808

**Deliverables**:
- `docs/avplayer-research.md` - Documento completo
- Matrix de codec support por platform/version
- Guía de workarounds para unsupported codecs
- Best practices para low-latency streaming

#### 4. KSPlayer Architecture Analysis
**Objetivos**:
- Entender el pipeline completo de decodificación y renderizado
- Identificar patrones de código reutilizables
- Mapear todas las optimizations implementadas
- Documentar decisiones arquitectónicas y tradeoffs
- Extraer lecciones aprendidas

**Recursos**:
- KSPlayer Source Code (repo clonado en `references/KSPlayer`)
- KSPlayer GitHub Issues y Discussions
- KSPlayer Wiki y Documentation
- KSPlayer Release Notes (changelog)
- Code review de módulos clave (FFmpegDecode.swift, VideoToolboxDecode.swift, KSMEPlayer.swift)

**Deliverables**:
- `docs/ksplayer-analysis.md` - Análisis arquitectónico completo
- Diagrama del pipeline KSPlayer vs TransmuxCore propuesto
- Listado de patrones de código a adoptar/adaptar
- Identificación de optimizations críticas
- Lessons learned document

#### 5. Industry Best Practices
**Objetivos**:
- Investigar cómo otras apps IPTV/video manejan codecs
- Documentar trends en video streaming optimization
- Analizar soluciones de competidores (VLC, Infuse, nPlayer, Plex)
- Investigar academic research en video transcoding optimization
- Mapear industry standards y specifications

**Recursos**:
- VLC Source Code (libvlc, mobile modules)
- Infuse Blog y Technical Documentation
- Plex Media Server Code (transcoding logic)
- IEEE/ACM Research Papers (video streaming optimization)
- Streaming Media Blogs (Netflix, YouTube engineering blogs)
- FFmpeg and VideoToolbox Forums (Stack Overflow, Reddit)

**Deliverables**:
- `docs/industry-best-practices.md` - Documento comparativo
- Analysis de competidores (strengths/weaknesses)
- Listado de innovative patterns y approaches
- Recommendations basadas en industry trends

### Timeline de Research

```mermaid
gantt
    title Research Phase Timeline
    dateFormat  YYYY-MM-DD
    section FFmpeg Research
    Changelog analysis       :done,    ff1, 2024-03-11, 2d
    API documentation       :active,  ff2, 2024-03-13, 3d
    Performance benchmarks   :         ff3, after ff2, 2d
    section VideoToolbox
    Framework docs           :active,  vt1, 2024-03-11, 3d
    WWDC sessions review     :         vt2, after vt1, 1d
    Code examples            :         vt3, after vt2, 2d
    section AVPlayer
    Codec support matrix     :active,  av1, 2024-03-11, 2d
    Workarounds research     :         av2, after av1, 2d
    section KSPlayer Analysis
    Architecture review      :active,  ks1, 2024-03-11, 3d
    Key modules deep dive     :         ks2, after ks1, 3d
    Industry Comparison
    Competitor analysis      :         ind1, after ks2, 3d
    Best practices document  :         ind2, after ind1, 2d
    section Synthesis
    Technical architecture   :         syn1, after ind2, 3d
    Implementation plan      :         syn2, after syn1, 2d
```

---

## Fase Principal: Implementación

### Fase 1: Foundation (Weeks 1-2)

#### 1.1 Optimización del Build FFmpeg
**Objetivos**:
- Compilar FFmpeg 8.x con optimizations específicas para Apple platforms
- Reducir tamaño binario de 15-20MB → 3-5MB (70-80% reduction)
- Configurar deployment targets: macOS 14+, iOS 17+, tvOS 17+
- Habilitar solo codecs y features esenciales

**Tasks**:
- [ ] Crear scripts de build por platform (`scripts/build-ffmpeg.sh`)
- [ ] Configurar cross-compilation para arm64 (iOS/macOS/tvOS)
- [ ] Habilitar VideoToolbox (`--enable-videotoolbox`)
- [ ] Habilitar decoders: VP9, VP8, AV1, MPEG-2, Theora, etc.
- [ ] Habilitar encoders: h264_videotoolbox, hevc_videotoolbox
- [ ] Deshabilitar codecs irrelevantes (formatos de audio obsoletos, etc.)
- [ ] Optimizar flags de compilation (`-O3`, `-flto`, `-ffunction-sections`)
- [ ] Crear xcframeworks para fácil integración en Xcode
- [ ] Documentar proceso de build en `docs/ffmpeg-build-guide.md`

**Deliverables**:
- `TransmuxCore/FFmpeg/FFmpeg.xcframework` - xcframework optimizado
- `scripts/build-ffmpeg.sh` - Script reproducible
- `docs/ffmpeg-build-guide.md` - Guía completa
- Package.swift actualizado con FFmpeg dependencies

#### 1.2 Suite C Foundation
**Objetivos**:
- Crear capas C bien estructuradas para FFmpeg y VideoToolbox
- Implementar abstracciones limpias para FFmpeg APIs
- Crear bridges eficientes C ↔ Swift (FFI)
- Establecer patrones de error handling robustos

**Architecture**:
```
TransmuxCore/C/
├── include/
│   ├── transmux_core.h           # Main header público
│   ├── transmux_types.h          # Type definitions
│   ├── transmux_error.h          # Error codes y mensajes
│   ├── transmux_config.h         # Configuration constants
│   ├── transmux_decoder.h         # Decoder abstraction
│   ├── transmux_encoder.h         # Encoder abstraction
│   └── transmux_mixer.h           # Audio/video mixer
├── src/
│   ├── core/
│   │   ├── transmux_core.c       # Main initialization
│   │   ├── transmux_error.c     # Error handling
│   │   ├── transmux_config.c     # Configuration parsing
│   │   └── transmux_utils.c      # Utility functions
│   ├── ffmpeg/
│   │   ├── ffmpeg_wrapper.h      # FFmpeg bridge header
│   │   ├── ffmpeg_wrapper.c      # FFmpeg initialization
│   │   ├── ffmpeg_demuxer.c      # Demuxing (avformat)
│   │   ├── ffmpeg_decoder.c      # Decoding (avcodec)
│   │   ├── ffmpeg_encoder.c      # Encoding (avcodec)
│   │   ├── ffmpeg_swscale.c      # Pixel format conversion
│   │   └── ffmpeg_utils.c        # FFmpeg utilities
│   ├── videotoolbox/
│   │   ├── vt_wrapper.h          # VideoToolbox bridge header
│   │   ├── vt_wrapper.c          # VideoToolbox initialization
│   │   ├── vt_decoder.c          # Hardware decoding
│   │   ├── vt_encoder.c          # Hardware encoding
│   │   ├── vt_compress.c        # VTCompressionSession
│   │   └── vt_utils.c            # VideoToolbox utilities
│   ├── audio/
│   │   ├── audio_transcoder.c    # Audio transcoding pipeline
│   │   ├── audio_mixer.c         # Audio mixing
│   │   ├── audio_resampler.c     # Sample rate conversion
│   │   └── audio_utils.c         # Audio utilities
│   ├── video/
│   │   ├── video_transcoder.c    # Video transcoding pipeline
│   │   ├── video_scaler.c        # Video scaling
│   │   ├── video_encoder.c       # Video encoding logic
│   │   └── video_utils.c         # Video utilities
│   └── format/
│       ├── mp4_muxer.c           # MP4/TS/MOV demuxing
│       ├── hls_parser.c          # HLS parsing
│       ├── dash_parser.c         # DASH parsing
│       └── stream_detector.c     # Format detection
└── tests/
    ├── test_core.c               # Core functionality tests
    ├── test_ffmpeg.c             # FFmpeg bridge tests
    ├── test_videotoolbox.c       # VideoToolbox tests
    ├── test_audio.c               # Audio tests
    └── test_video.c               # Video tests
```

**Tasks**:
- [ ] Crear estructura de directorios `TransmuxCore/C/`
- [ ] Implementar error handling robusto con códigos y mensajes
- [ ] Crear wrappers C para FFmpeg APIs principales
- [ ] Implementar VideoToolbox bridge con session management
- [ ] Crear abstracción de decoder (FFmpeg software + VideoToolbox hardware)
- [ ] Implementar abstracción de encoder (VideoToolbox priority)
- [ ] Crear layer de audio transcoding (FFmpeg → VideoToolbox)
- [ ] Crear layer de video transcoding (FFmpeg decode → VT encode)
- [ ] Implementar format detection y demuxing
- [ ] Escribir unit tests para todos los módulos C
- [ ] Documentar APIs en headers con Doxygen comments

**Deliverables**:
- Suite C completa y bien estructurada
- Headers públicos bien documentados
- Unit tests con >80% coverage
- `docs/c-architecture.md` - Documentación arquitectónica

### Fase 2: Swift Integration (Weeks 3-4)

#### 2.1 Swift-C Bridge (FFI)
**Objetivos**:
- Crear bindings Swift eficientes para capas C
- Implementar type mapping seguro (Swift ↔ C)
- Usar modern Swift concurrency (async/await, actors)
- Mantener memory safety sin overhead significativo

**Architecture**:
```
TransmuxCore/Sources/TransmuxCore/
├── Core/
│   ├── TransmuxCore.swift           # Main facade
│   ├── TransmuxError.swift          # Swift error types
│   ├── TransmuxConfig.swift         # Configuration model
│   └── TransmuxSession.swift        # Session management (actor)
├── FFmpeg/
│   ├── FFmpegBridge.swift           # FFmpeg C bindings
│   ├── FFmpegDemuxer.swift          # Demuxer wrapper
│   ├── FFmpegDecoder.swift          # Decoder wrapper
│   ├── FFmpegEncoder.swift          # Encoder wrapper
│   └── FFmpegUtils.swift            # Utilities
├── VideoToolbox/
│   ├── VideoToolboxBridge.swift     # VT C bindings
│   ├── VTDecoder.swift              # Hardware decoder
│   ├── VTEncoder.swift              # Hardware encoder
│   ├── VTCompressionSession.swift   # Compression session
│   └── VTUtils.swift                # Utilities
├── Audio/
│   ├── AudioTranscoder.swift        # Audio transcoding
│   ├── AudioMixer.swift             # Audio mixing
│   ├── AudioResampler.swift         # Sample rate conversion
│   └── AudioUtils.swift             # Utilities
├── Video/
│   ├── VideoTranscoder.swift        # Video transcoding
│   ├── VideoScaler.swift            # Video scaling
│   ├── VideoEncoder.swift           # Video encoding
│   └── VideoUtils.swift             # Utilities
├── Format/
│   ├── FormatDetector.swift         # Format detection
│   ├── MP4Demuxer.swift             # MP4/TS/MOV parsing
│   ├── HLSParser.swift              # HLS parsing
│   └── DASHParser.swift             # DASH parsing
├── Pipeline/
│   ├── TransmuxPipeline.swift       # Main pipeline coordinator
│   ├── PipelineContext.swift        # Pipeline state
│   ├── PipelineStage.swift          # Pipeline stage protocol
│   ├── TierDecision.swift           # Tier selection logic
│   └── PipelineMonitor.swift        # Performance monitoring
└── AVPlayer/
    ├── AVPlayerAdapter.swift        # AVPlayer integration
    ├── SampleBufferGenerator.swift  # Sample buffer generation
    └── AVAssetGenerator.swift        # AVAsset creation
```

**Tasks**:
- [ ] Crear módulos Swift para cada capa C
- [ ] Implementar `@_cdecl` bindings para funciones C críticas
- [ ] Mapear C types a Swift types seguros
- [ ] Implementar memory management automático (deinit, defer)
- [ ] Usar `withUnsafeBytes`/`withUnsafeMutableBytes` para efficient data access
- [ ] Implementar error handling Swift (throw + C error codes)
- [ ] Crear actor para thread-safe session management
- [ ] Implementar async wrappers para operaciones blocking de C
- [ ] Escribir Swift tests con XCTest
- [ ] Documentar Swift APIs con comments

**Deliverables**:
- Swift-C bridge completo y type-safe
- Actors para thread-safety
- Async APIs para todas las operaciones
- Unit tests Swift
- `docs/swift-c-bridge.md` - Documentación de bindings

#### 2.2 Integration con TransmuxingService Existente
**Objetivos**:
- Integrar nuevo pipeline en `TransmuxingService.swift`
- Migrar logic existente a nueva arquitectura
- Mantener backward compatibility si es necesario
- Optimizar performance con QoS y threading

**Tasks**:
- [ ] Revisar `TransmuxingService.swift` actual
- [ ] Identificar puntos de integración
- [ ] Migrar audio transcoding existente a nuevo pipeline
- [ ] Agregar video transcoding con tier decision
- [ ] Implementar adaptive bitrate logic
- [ ] Optimizar threading con QoS `.userInteractive`
- [ ] Agregar performance monitoring
- [ ] Implementar retry logic robusto
- [ ] Actualizar `TransmuxOptions.swift` y `TransmuxState.swift`
- [ ] Escribir integration tests

**Deliverables**:
- `TransmuxingService.swift` actualizado
- `TransmuxOptions.swift` extendido
- `TransmuxState.swift` extendido
- Integration tests

### Fase 3: Advanced Features (Weeks 5-6)

#### 3.1 Smart Tier Decision Engine
**Objetivos**:
- Implementar inteligencia para seleccionar tier óptimo
- Usar heurísticas basadas en device capabilities, network, content
- Aprender de performance metrics (si es viable)
- Optimizar battery life y CPU usage

**Decision Factors**:
```
┌────────────────────────────────────────────────────────────────┐
│                  Tier Decision Factors                          │
├────────────────────────────────────────────────────────────────┤
│ 1. Codec Analysis                                               │
│    - Video codec (H.264, H.265, VP9, AV1, MPEG-2, etc.)        │
│    - Audio codec (AAC, AC3, EAC3, DTS, FLAC, OPUS, etc.)       │
│    - Container format (MP4, MOV, TS, MKV, etc.)                │
│    - Codec profile/level (High, Main, Baseline, etc.)          │
│                                                                │
│ 2. Device Capabilities                                          │
│    - Hardware decoder availability (VideoToolbox)              │
│    - Hardware encoder availability (VTCompressionSession)       │
│    - Processor capabilities (A17, M1, M2, M3, etc.)           │
│    - Device class (iPhone, iPad, Mac, Apple TV)                │
│    - OS version (iOS 26, macOS 26, tvOS 26)                     │
│                                                                │
│ 3. Network Conditions                                           │
│    - Bandwidth (detected/provided)                             │
│    - Latency requirements (live vs VOD)                         │
│    - Connection type (WiFi, Cellular, Ethernet)                │
│                                                                │
│ 4. Content Characteristics                                      │
│    - Resolution (720p, 1080p, 4K, 8K)                           │
│    - Framerate (24, 30, 60, 120 fps)                            │
│    - Bitrate (average, peak)                                    │
│    - HDR presence (HDR10, Dolby Vision, HLG)                    │
│    - Duration (short clips vs full movies)                      │
│                                                                │
│ 5. User Experience Requirements                                 │
│    - Latency tolerance (live: <2s, VOD: flexible)               │
│    - Quality preference (speed vs quality)                      │
│    - Battery status (low battery → optimize)                   │
│    - Power mode (low power → reduce transcode)                 │
│                                                                │
│ 6. Performance History (if available)                          │
│    - Previous transcode performance                            │
│    - Device-specific optimizations                             │
│    - Network-specific optimizations                            │
└────────────────────────────────────────────────────────────────┘
```

**Implementation**:
```swift
struct TierDecisionEngine {
    func decideTier(
        codec: VideoCodec,
        audioCodec: AudioCodec,
        resolution: Resolution,
        capabilities: DeviceCapabilities,
        network: NetworkConditions,
        preferences: UserPreferences
    ) -> TransmuxTier {
        // Smart decision logic
    }
}

enum TransmuxTier: Int, Comparable {
    case passthrough = 0  // No transcoding
    case audioOnly = 1    // Audio transcode only
    case video = 2        // Video selective transcode
    case full = 3         // Full transcode

    var cpuImpact: Double { ... }
    var batteryImpact: Double { ... }
    var qualityImpact: Double { ... }
}
```

**Tasks**:
- [ ] Diseñar `TierDecisionEngine` con heurísticas
- [ ] Implementar `DeviceCapabilities` detector
- [ ] Implementar `NetworkConditions` monitor
- [ ] Crear scoring algorithm para tier selection
- [ ] Agregar adaptive bitrate calculator
- [ ] Implementar fallback logic
- [ ] Agregar telemetry para mejoras futuras
- [ ] Escribir tests exhaustivos de edge cases

**Deliverables**:
- `TierDecisionEngine.swift` completo
- Device capabilities detector
- Network conditions monitor
- Unit tests con coverage >90%

#### 3.2 Adaptive Bitrate & Quality
**Objetivos**:
- Calcular bitrate óptimo basado en resolución, network, device
- Implementar quality-preserving transcoding
- Balancear quality vs performance vs battery
- Soportar HDR metadata passthrough

**Implementation**:
```swift
struct AdaptiveBitrateCalculator {
    func calculateTargetBitrate(
        sourceResolution: Resolution,
        networkBandwidth: Double,
        device: DeviceCapabilities,
        tier: TransmuxTier,
        preferences: QualityPreference
    ) -> Bitrate {
        // Optimal bitrate calculation
    }

    func calculateEncoderProfile(
        resolution: Resolution,
        bitrate: Bitrate,
        device: DeviceCapabilities
    ) -> VideoEncoderProfile {
        // Optimal profile selection
    }
}

struct QualityPreference {
    var maximizeQuality: Bool
    var minimizeBattery: Bool
    var prioritizeSpeed: Bool
    var targetQuality: VideoQuality?
}
```

**Tasks**:
- [ ] Implementar `AdaptiveBitrateCalculator`
- [ ] Crear bitrate tables por resolución
- [ ] Implementar quality-preserving algorithms
- [ ] Agregar HDR metadata handling
- [ ] Implementar bitrate adaptation dinámica
- [ ] Crear quality presets para diferentes escenarios
- [ ] Tests de quality vs performance

**Deliverables**:
- `AdaptiveBitrateCalculator.swift`
- HDR metadata handling
- Quality presets
- Performance benchmarks

#### 3.3 Performance Optimization
**Objetivos**:
- Optimizar CPU usage con threading y QoS
- Minimize memory allocations y copies
- Implementar efficient buffer management
- Reducir latency para live streaming

**Optimizations**:
```swift
// QoS-aware threading
actor TransmuxExecutor {
    private let queue: DispatchQueue

    func execute<T>(_ task: () async throws -> T, qos: QualityOfService) async rethrows -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(qos: qos) {
                Task {
                    do {
                        let result = try await task()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// Zero-copy buffer management
struct VideoBuffer {
    let pixelBuffer: CVPixelBuffer
    private var retained = false

    func retain() -> VideoBuffer { ... }
    func release() { ... }
}

// Memory pool for reuse
class BufferPool<T> {
    private var pool: [T] = []
    private let lock = NSLock()

    func acquire() -> T { ... }
    func release(_ buffer: T) { ... }
}
```

**Tasks**:
- [ ] Implementar QoS-aware threading
- [ ] Crear buffer pool para reuse
- [ ] Optimizar memory allocations
- [ ] Implementar zero-copy paths donde sea posible
- [ ] Reducir latency en pipeline
- [ ] Agregar performance counters y profiling
- [ ] Profile y optimize hot paths
- [ ] Benchmarking comparativo vs KSPlayer

**Deliverables**:
- Optimized threading con QoS
- Buffer pool implementation
- Performance counters
- Benchmarking results

### Fase 4: Advanced Integrations (Weeks 7-8)

#### 4.1 Live Streaming Optimizations
**Objetivos**:
- Soportar ultra-low latency (<1s) para live TV
- Implementar adaptive bitrate para live streams
- Optimizar handling de HLS/DASH live manifests
- Manejar network issues robustamente

**Tasks**:
- [ ] Implementar low-latency mode
- [ ] Optimizar buffer management para live
- [ ] Agregar network resilience logic
- [ ] Implementar adaptive bitrate para live
- [ ] Optimizar HLS/DASH parsing
- [ ] Tests de live streaming scenarios

**Deliverables**:
- Low-latency pipeline
- Live streaming optimizations
- Live streaming tests

#### 4.2 Error Handling & Recovery
**Objetivos**:
- Manejar todos los error scenarios robustamente
- Implementar retry logic inteligente
- Propagar errores claros al usuario
- Recover gracefully de failures

**Implementation**:
```swift
struct TransmuxError: LocalizedError {
    enum Code {
        case codecNotSupported
        case deviceNotCapable
        case networkError
        case transcodingFailed
        case memoryError
        case invalidInput
        case timeout
        case unknown
    }

    let code: Code
    let message: String
    let underlying: Error?

    var errorDescription: String? { ... }
}

class RetryHandler {
    func attempt<T>(
        _ operation: @escaping () async throws -> T,
        maxRetries: Int = 3,
        backoff: BackoffStrategy = .exponential
    ) async throws -> T { ... }
}
```

**Tasks**:
- [ ] Definir todos los error codes
- [ ] Implementar retry logic con backoff
- [ ] Agregar error recovery strategies
- [ ] Crear user-friendly error messages
- [ ] Tests de error scenarios

**Deliverables**:
- Comprehensive error handling
- Retry logic
- Error recovery tests

#### 4.3 Telemetry & Analytics
**Objetivos**:
- Recolectar performance metrics
- Track codec usage por tier
- Monitorizar device capabilities
- Identificar optimization opportunities

**Metrics**:
```
Performance Metrics:
- Transcoding time (ms)
- CPU usage (%)
- Memory usage (MB)
- Battery impact (%)
- Latency (ms)

Usage Metrics:
- Codec distribution (by tier)
- Device distribution
- Network conditions distribution
- Error rates
- Fallback rates

Quality Metrics:
- Perceptual quality scores
- Bitrate efficiency
- Resolution distribution
- HDR passthrough rate
```

**Tasks**:
- [ ] Diseñar metrics schema
- [ ] Implementar metrics collection
- [ ] Crear analytics pipeline
- [ ] Implementar privacy-compliant tracking
- [ ] Dashboard para visualize metrics

**Deliverables**:
- Metrics collection system
- Analytics pipeline
- Telemetry dashboard (opcional)

---

## Fase 5: Testing & Validation (Weeks 9-10)

### 5.1 Comprehensive Test Suite
**Objetivos**:
- Crear tests exhaustivos para todos los módulos
- Alcanzar >90% code coverage
- Testear edge cases y error scenarios
- Validar performance expectations

**Test Categories**:

#### Unit Tests
```
C Layer:
- Core initialization and error handling
- FFmpeg wrapper functions
- VideoToolbox bridge
- Audio/video transcoding
- Format detection and parsing

Swift Layer:
- Swift-C bridge functionality
- Tier decision logic
- Adaptive bitrate calculation
- AVPlayer integration
- Error handling and retry logic
```

#### Integration Tests
```
End-to-End Pipeline:
- Tier 0: Passthrough flow
- Tier 1: Audio-only transcode
- Tier 2: Video selective transcode
- Tier 3: Full transcode

Edge Cases:
- Corrupted streams
- Unsupported codecs
- Network interruptions
- Device limitations
- Low battery scenarios
```

#### Performance Tests
```
Benchmarks:
- CPU usage vs KSPlayer
- Memory usage vs KSPlayer
- Battery impact vs KSPlayer
- Transcoding speed vs KSPlayer
- Latency vs KSPlayer

Quality Tests:
- PSNR comparisons
- SSIM comparisons
- Perceptual quality assessment
- HDR passthrough validation
```

**Tasks**:
- [ ] Escribir unit tests para C layer
- [ ] Escribir unit tests para Swift layer
- [ ] Crear integration tests
- [ ] Implementar performance benchmarks
- [ ] Crear quality assessment tests
- [ ] Automatizar test execution
- [ ] Integrar en CI/CD pipeline

**Deliverables**:
- >90% code coverage
- Performance benchmarks
- Quality validation results
- Automated test suite

### 5.2 Real-World Validation
**Objetivos**:
- Testear con contenido real de IPTV streams
- Validar performance en dispositivos reales
- Comparar con KSPlayer en scenarios reales
- Recopilar feedback de usuarios beta

**Test Scenarios**:
```
Content Types:
- Live TV channels (H.264/H.265)
- Movies (various codecs)
- Series episodes
- Sports broadcasts (high motion)
- 4K HDR content

Device Coverage:
- iPhone 15 Pro (A17 Pro)
- iPad Pro M4
- Mac M3 Pro/Max
- Apple TV 4K (M2)
- Older devices for fallback testing

Network Conditions:
- High-speed WiFi
- Cellular 5G
- Cellular LTE
- Low-bandwidth WiFi
```

**Tasks**:
- [ ] Crear test suite con streams reales
- [ ] Testear en múltiples dispositivos
- [ ] Comparar performance con KSPlayer
- [ ] Recopilar metrics reales
- [ ] Validar battery impact
- [ ] Solicitar feedback de usuarios beta
- [ ] Documentar findings

**Deliverables**:
- Real-world performance report
- KSPlayer comparison results
- User feedback summary
- Optimization recommendations

---

## Fase 6: Documentation & Handoff (Weeks 11-12)

### 6.1 Technical Documentation
**Objetivos**:
- Documentar toda la arquitectura
- Crear guías de uso y desarrollo
- Documentar APIs y abstractions
- Crear troubleshooting guides

**Documents**:
```
Architecture:
- Architecture Overview
- Component Diagrams
- Data Flow Diagrams
- API Reference

Developer Guides:
- Getting Started Guide
- Build and Setup Guide
- Contributing Guide
- Testing Guide

User Documentation:
- Configuration Options
- Troubleshooting Guide
- Performance Tuning Guide
- FAQ
```

**Tasks**:
- [ ] Escribir architecture overview
- [ ] Crear component diagrams
- [ ] Documentar todas las APIs
- [ ] Escribir developer guides
- [ ] Crear troubleshooting guides
- [ ] Documentar configuration options
- [ ] Crear FAQ

**Deliverables**:
- Complete technical documentation
- Developer guides
- User documentation

### 6.2 Final Optimization & Polish
**Objetivos**:
- Address issues encontradas en testing
- Optimizar basado en real-world feedback
- Polish code y remove technical debt
- Prepare para production deployment

**Tasks**:
- [ ] Fix bugs encontrados
- [ ] Optimize based on feedback
- [ ] Refactor code quality issues
- [ ] Remove dead code y comments
- [ ] Finalize documentation
- [ ] Prepare release notes

**Deliverables**:
- Production-ready code
- Release notes
- Final documentation

---

## Success Criteria

### Technical Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| **Codec Coverage** | 98%+ | Tested against 1000+ streams |
| **CPU Usage vs KSPlayer** | ≤60% | Benchmarking on same hardware |
| **Battery Impact vs KSPlayer** | ≤40% | Battery drain tests |
| **Binary Size** | ≤5MB | Compiled xcframework |
| **Latency (Live)** | <2s | End-to-end timing |
| **Code Coverage** | >90% | Unit test coverage |
| **Memory Usage** | ≤50MB of KSPlayer | Memory profiling |

### Quality Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| **PSNR vs Source** | >40dB (tier 2/3) | Quality assessment |
| **SSIM vs Source** | >0.95 (tier 2/3) | Quality assessment |
| **Perceptual Quality** | No visible degradation (tier 2/3) | Human evaluation |
| **Error Rate** | <1% | Production telemetry |
| **Fallback Rate** | <5% (to full transcode) | Telemetry |

### Experience Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| **User Satisfaction** | ≥4.5/5 | Beta feedback |
| **Crash Rate** | 0% | Crashlytics |
| **Startup Time** | <1s | Performance tests |
| **Seek Time** | <500ms | Performance tests |

---

## Risks & Mitigations

### Technical Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **VideoToolbox limitations** | High | Medium | Research exhaustive, fallback to software encoding |
| **Performance not meeting targets** | High | Low | Early benchmarks, iterative optimization |
| **FFmpeg compilation issues** | Medium | Medium | Thorough testing, fallback to stable version |
| **Memory leaks in C-Swift bridge** | Medium | Medium | Memory profiling, strict ownership rules |
| **Live streaming latency too high** | Medium | Low | Low-latency optimization, buffer tuning |

### Project Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **Timeline overruns** | Medium | Medium | Agile approach, phased delivery |
| **Research scope too large** | Low | Medium | Time-box research, focus on key areas |
| **KSPlayer improvements during development** | Low | Low | Monitor KSPlayer, adapt as needed |
| **Resource constraints** | Medium | Low | Prioritize critical features, defer nice-to-haves |

---

## Next Steps

### Immediate Actions (This Week)
1. [ ] **Setup Reference Repository**
   ```bash
   cd /Volumes/KODAK1TB/MKS-IPTV-App
   mkdir -p references
   cd references
   git clone https://github.com/kingslay/KSPlayer.git
   ```

2. [ ] **Add to .gitignore**
   ```
   # Reference repositories (read-only)
   /references/KSPlayer/
   ```

3. [ ] **Start Research Phase**
   - Begin FFmpeg 6→8 research (Changelog analysis)
   - Start VideoToolbox documentation review
   - Begin KSPlayer architecture analysis

4. [ ] **Create Documentation Directory**
   ```bash
   mkdir -p docs/transmuxcore-phase0
   ```

### Week 1-2: Research Phase Execution
- Execute research tasks documented in "Fase Preliminar"
- Create all research documents
- Synthesize findings into architecture recommendations

### Week 3+: Implementation Phase
- Begin Fase 1 implementation (Foundation)
- Follow phased approach outlined above
- Regular checkpoints y progress reviews

---

## Conclusion

Este plan establece una path clara para superar a KSPlayer en:

1. **Rendimiento**: 40-60% menos CPU, 60% menos battery impact
2. **Eficiencia**: Architecture más simple, 70-80% reduction en binary size
3. **Patrones de Código**: Modular, bien documentado, type-safe Swift-C bridge
4. **Codec Support**: 98%+ con tiers inteligentes de transcoding
5. **Experiencia de Usuario**: AVPlayer nativo (PiP, AirPlay, HDR, Spatial Audio)

**Key Differentiators vs KSPlayer**:
- Smart tier selection (passthrough 85% del tiempo)
- Adaptive bitrate y quality
- Research exhaustivo antes de implementar
- Modern Swift 6 concurrency patterns
- Well-documented, maintainable architecture
- Focus on efficiency vs feature bloat

**The "Crazy" Factor**: Sí, es una meta ambiciosa, pero con:
- Access a KSPlayer source como referencia
- FFmpeg 6→8 improvements
- VideoToolbox hardware acceleration
- Apple ecosystem advantages
- Tiempo, obsesión, y enfoque

Es **viable y ejecutable**. Procedemos.

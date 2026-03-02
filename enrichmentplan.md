# Enrichment Plan: Metadata, Caching, UI/UX y Liquid Glass

## Progreso Global

| Fase | Estado | Commit | Descripcion |
|------|--------|--------|-------------|
| **Fase 0** | ✅ COMPLETADA | `57f612c` | Quick fixes: cleanTitle en HeroBanner y HomeMediaCard |
| **Fase 1** | ✅ COMPLETADA | `5a652bb` | EnrichedMediaStore actor + prefetch en Home + tmdbIdInt |
| **Fase 2** | ✅ COMPLETADA | pendiente commit | Hero Banner enriquecido con metadata TMDB |
| **Fase 3** | 🔲 PENDIENTE | — | MediaDetailSheet (Apple TV+/Netflix style) |
| **Fase 4** | 🔲 PENDIENTE | — | SWR generico en CacheManager |
| **Fase 5** | 🔲 PENDIENTE | — | Liquid Glass UI enhancements |
| **Fase 6** | 🔲 PENDIENTE | — | Serie Detail con episodes tab |

---

## Estado Actual del Proyecto (verificado 2 Mar 2026)

```
mks-multiplatform-iptv/IPTVDownloader/
├── Core/
│   ├── Configuration/    IPTVProfile, IPTVProfilesManager
│   ├── Metadata/         TMDBMetadataProvider, TheTVDBMetadataProvider,
│   │                     ITunesSearchProvider, MetadataResolver,
│   │                     MetadataEnrichmentService, MetadataTypes,
│   │                     StringSimilarity, MetadataProvider (protocol)
│   ├── Networking/       CacheManager, VideoDownloader, ImageCache
│   └── Player/           TransmuxingService, HLSSegmenter
├── Features/
│   ├── Download/
│   │   ├── ViewModels/   MovieDetailViewModel, SerieDetailViewModel
│   │   └── Views/        AddDownloadView (macOS), AddDownloadMediaViewiOS,
│   │                     MetadataPickerView, DownloadViews
│   ├── Home/
│   │   ├── ViewModels/   HomeViewModel
│   │   └── Views/        HomeView, HeroBannerView, HomeMediaCard,
│   │                     HomeMediaCarousel
│   ├── Media/
│   │   ├── ViewModels/   MediaListViewModel, MediaDetailViewModel
│   │   └── Views/        MovieCardView, SerieCardView,
│   │                     MediaCardViewUtilities, MediaCardViewiOS,
│   │                     MediaListView
│   └── LiveChannelsList/ ...
├── Models/               Movie, Serie, MovieDetail, SerieDetail,
│                         LiveChannel, DownloadItem
├── Services/             MovieService (actor)
├── Utils/                TitleParser, TransmuxLog
└── App/                  AppDataLoader, ContentView, AppTheme,
                          NavigationDestination
```

---

## BUG CORREGIDO: Hero Banner mostraba `item.name` en vez de `item.cleanTitle`

> ✅ **RESUELTO en Fase 0** — Commit `57f612c`

### Cambios aplicados:
| Archivo | Linea | Antes | Despues | Estado |
|---------|-------|-------|---------|--------|
| `HeroBannerView.swift` | 72 | `item.name` | `item.cleanTitle` | ✅ Fix |
| `HomeMediaCard.swift` | 159 | `item.name` (placeholder) | `item.cleanTitle` | ✅ Fix |

### Usos que ya eran correctos:
| Archivo | Linea | Propiedad |
|---------|-------|-----------|
| `HomeMediaCard.swift` | 55 | `item.cleanTitle` |
| `MovieCardView.swift` | 141 | `movie.formattedTitle` (= `cleanTitle`) |
| `SerieCardView.swift` | 141 | `serie.formattedTitle` (= `cleanTitle`) |

---

## SECCION 1: Arquitectura de Datos Actual

### 1.1 Modelos de Datos

#### Movie.swift (verificado)
```swift
struct Movie: Identifiable, Codable, Equatable {
    let name: String              // Titulo crudo de la API IPTV
    let streamId: Int             // ID unico
    let tmdbId: String?           // TMDB ID (String o Int, decodificado flexible)
    let streamIcon: String?       // URL del poster
    let rating5Based: Double?     // Rating 0-5
    let added: String?            // Unix timestamp como String
    let categoryId: String
    let containerExtension: String?

    // Computed (NO cacheadas, se recalculan cada acceso):
    var parsedMetadata: TitleMetadata { TitleParser.parse(name) }
    var cleanTitle: String { parsedMetadata.cleanTitle }
    var quality: String? { parsedMetadata.quality }
    var codec: String? { parsedMetadata.codec }
    var year: String? { parsedMetadata.year }   // via extension en MediaCardViewUtilities
}
```

#### Serie.swift (verificado)
```swift
struct Serie: Identifiable, Codable, Equatable {
    let name: String
    let seriesId: Int
    let cover: String?            // URL del poster
    let plot: String
    let cast: String              // Comma-separated
    let director: String?
    let genre: String
    let releaseDate: String
    let rating5Based: Double      // NOT optional (a diferencia de Movie)
    let backdropPath: [String]
    let youtubeTrailer: String?
    let categoryId: String
    // ⚠️ NO tiene tmdbId (a diferencia de Movie)

    // Mismos computed que Movie
    var parsedMetadata: TitleMetadata { TitleParser.parse(name) }
    var cleanTitle: String { parsedMetadata.cleanTitle }
}
```

#### MovieDetail.swift (verificado)
```swift
struct MovieDetail: Identifiable, Codable {
    let movieData: Movie          // Nested Movie
    let tmdbId: Int               // ← Int directo (no String como en Movie)
    let movieImage: String        // Poster URL
    let backdrop: String?
    let youtubeTrailer: String?
    let genre: String
    let plot: String
    let cast: [String]            // Ya parseado como array
    let director: String
    let releaseDate: String
    let backdropPath: [String]?
    let durationSecs: Int
    let duration: String
    // Decodifica desde JSON: { "info": {...}, "movie_data": {...} }
}
```

#### SerieDetail.swift (verificado)
```swift
struct SerieDetail: Codable {
    let seasons: [Season]
    let info: SerieInfo           // Metadata general
    let episodes: [String: [Episode]]  // seasonNum -> [Episode]

    struct SerieInfo: Codable {
        let name, cover, genre, plot, cast, rating: String
        let rating5Based: Double
        let director: String?
        let backdropPath: [String]
        let youtubeTrailer: String?
    }
    struct Episode: Codable {
        let id: String
        let episodeNum: Int
        let title: String
        let containerExtension: String
        let info: EpisodeInfo     // Per-episode metadata
    }
}
```

### 1.2 Flujo de Datos Actual

```
┌──────────────────────────────────────────────────────────────────────┐
│                        IPTV SERVER (Xtream Codes API)               │
│  /player_api.php?action=get_vod_streams     → [Movie]              │
│  /player_api.php?action=get_series          → [Serie]              │
│  /player_api.php?action=get_vod_info&vod_id=X → MovieDetail       │
│  /player_api.php?action=get_series_info&series_id=X → SerieDetail  │
└──────────────────┬───────────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     MovieService (actor)                             │
│  fetchMovies() → [Movie]        fetchMovieDetails(vodId) → Detail  │
│  fetchSeries() → [Serie]        fetchSeriesDetails(seriesId) → Det │
│  fetchMovieCategories() → [MovieCategory]                          │
│  fetchSeriesCategories() → [SeriesCategory]                        │
└──────────────────┬───────────────────────────────────────────────────┘
                   │
          ┌────────┼────────┐
          ▼        ▼        ▼
   ┌─────────┐ ┌──────┐ ┌──────────────┐
   │ Cache   │ │ VM   │ │ HomeViewModel│
   │ Manager │ │ List │ │              │
   └────┬────┘ └──┬───┘ └──────┬───────┘
        │         │             │
        │    ┌────┴────┐   ┌───┴────────┐
        │    │MediaList│   │assembleSect│
        │    │ViewModel│   │ions()      │
        │    └────┬────┘   └───┬────────┘
        │         │            │
        ▼         ▼            ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          UI LAYER                                    │
│  HomeView → HeroBannerView (✅ usa item.cleanTitle — fixed F0)      │
│          → HomeMediaCarousel → HomeMediaCard (✅ usa item.cleanTitle)│
│  MediaListView → MovieCardView (✓ usa movie.formattedTitle)        │
│               → SerieCardView (✓ usa serie.formattedTitle)         │
│               → fullScreenCover → AddDownloadMediaViewiOS          │
│               → sheet (macOS) → AddDownloadView                    │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.3 Sistema de Caching Actual (CacheManager.swift - verificado)

```
┌──────────────────────────────────────────────────────────────────────┐
│                    CacheManager.shared (singleton)                   │
│                                                                      │
│  Almacenamiento: FileManager → Caches/IPTVCache/*.json              │
│  Thread safety: DispatchQueue concurrent (sync reads, barrier writes)│
│                                                                      │
│  ┌──────────────────────┬──────────┬────────────────────────────┐   │
│  │ Tipo                 │ TTL      │ Key Pattern                │   │
│  ├──────────────────────┼──────────┼────────────────────────────┤   │
│  │ Movie lists          │ 1 hora   │ media_list_movies_{catId}  │   │
│  │ Serie lists          │ 1 hora   │ media_list_series_{catId}  │   │
│  │ MovieDetail          │ 1 hora   │ movie_detail_{id}          │   │
│  │ SerieDetail          │ 1 hora   │ serie_detail_{id}          │   │
│  │ MetadataResult       │ 24 horas │ metadata_{title}_{year}    │   │
│  │ EPG data             │ 4 horas  │ epg_data.plist (binary)    │   │
│  │ EPG match table      │ 4 horas  │ epg_match_table.plist      │   │
│  └──────────────────────┴──────────┴────────────────────────────┘   │
│                                                                      │
│  PROBLEMAS (estado post Fase 1):                                    │
│  1. No hay SWR generico en CacheManager (solo en EnrichedMediaStore)│ → Fase 4
│  2. parsedMetadata se recalcula en CADA acceso (aceptable, ver 0.3) │ → Decision: mantener
│  3. ✅ Dedup de requests en vuelo → EnrichedMediaStore.inFlightReqs │ RESUELTO F1
│  4. ✅ Prefetch de metadata para items del Home → prefetchMetadata()│ RESUELTO F1
│  5. ✅ Persistencia de MetadataResult → EnrichedMediaStore 3-tier   │ RESUELTO F1
│  6. clearExpiredCache() usa cacheExpiration (1h) para TODO,         │ → Fase 4
│     deberia respetar TTLs individuales                              │
└──────────────────────────────────────────────────────────────────────┘
```

### 1.4 Sistema de Metadata Providers (verificado)

```
┌──────────────────────────────────────────────────────────────────────┐
│              MetadataEnrichmentService.shared (actor)                │
│                                                                      │
│  Providers:                                                         │
│  ┌─────────────────────┬───────────┬──────────────────────────────┐ │
│  │ TMDBMetadataProvider │ API v3   │ API key required             │ │
│  │                      │          │ Exact ID lookup → conf 1.0   │ │
│  │                      │          │ Title search → conf 0.5      │ │
│  │                      │          │ poster: w500, backdrop: w1280│ │
│  │                      │          │ Fetch credits + images       │ │
│  ├─────────────────────┼───────────┼──────────────────────────────┤ │
│  │ TheTVDBProvider     │ API v4   │ JWT auth (29-day TTL)         │ │
│  │                      │          │ Strong for TV series         │ │
│  │                      │          │ Base conf 0.4 for search     │ │
│  ├─────────────────────┼───────────┼──────────────────────────────┤ │
│  │ ITunesSearchProvider│ No key   │ High-quality artwork          │ │
│  │                      │          │ 600x600 and 1200x1200        │ │
│  │                      │          │ Content advisory ratings     │ │
│  └─────────────────────┴───────────┴──────────────────────────────┘ │
│                                                                      │
│  MetadataResolver (actor):                                          │
│  - Queries all providers in parallel (TaskGroup)                    │
│  - Scoring heuristico:                                              │
│    ┌──────────────────────────┬────────┐                            │
│    │ Factor                   │ Weight │                            │
│    ├──────────────────────────┼────────┤                            │
│    │ Exact TMDB ID match      │ 50     │                            │
│    │ Title similarity (Lev.)  │ 25     │                            │
│    │ Year match               │ 10     │                            │
│    │ Genre overlap            │ 8      │                            │
│    │ Runtime proximity        │ 7      │                            │
│    └──────────────────────────┴────────┘                            │
│                                                                      │
│  ✅ RESUELTO (Fase 1): EnrichedMediaStore ahora usa este servicio   │
│     proactivamente via HomeViewModel.prefetchMetadata() al cargar   │
│     el Home. Hero banner + primeros 10 items/carousel se prefetchean│
└──────────────────────────────────────────────────────────────────────┘
```

### 1.5 Flujo de Presentacion de Detalle (verificado)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    FLUJO ACTUAL DE DETALLE                           │
│                                                                     │
│  1. Usuario toca card en MediaListView                              │
│  2. showMovieDetail(for: movieId) se ejecuta:                       │
│     a. selectedMediaItemId = movieId                                │
│     b. initializeDetailViewModelsIfNeeded()                         │
│     c. isLoadingDetail = true                                       │
│     d. Task.sleep(400ms) ← delay artificial para animacion         │
│     e. movieDetailViewModel.fetchMovieDetails(for: movieId)         │
│     f. isLoadingDetail = false                                      │
│     g. showingFullScreenDetail = true                               │
│                                                                     │
│  3. Presentacion:                                                   │
│     iOS:   .fullScreenCover → AddDownloadMediaViewiOS               │
│     macOS: .sheet(minWidth:800, minHeight:600) → AddDownloadView    │
│                                                                     │
│  4. AddDownloadMediaViewiOS/AddDownloadView:                        │
│     - Collapsing header con backdrop                                │
│     - Pills: genre, rating, year, duration                          │
│     - Plot, cast, director                                          │
│     - Action buttons: Play, Download                                │
│                                                                     │
│  ⚠️ PROBLEMAS UX:                                                  │
│  1. "Download" → navega a Downloads tab → cierra el detalle         │
│  2. No hay transicion hero (matched geometry no conectado)          │
│  3. Sheet/fullScreenCover es tipo "dialogo basico"                  │
│  4. No hay trailer embebido ni preview del video                    │
│  5. No hay metadata enriquecida visible (poster TMDB, backdrop HD)  │
│  6. No hay tabs (Overview/Episodes/Similar/Trailers)                │
│  7. No se muestran los metadatos enriquecidos del provider          │
└─────────────────────────────────────────────────────────────────────┘
```

---

## SECCION 2: Plan de Implementacion

### FASE 0: Quick Fixes ✅ COMPLETADA

> **Commit**: `57f612c` — `fix(ui): use cleanTitle in hero banner and media card placeholder`

#### Tarea 0.1: Fix Hero Banner cleanTitle ✅
**Archivo**: `HeroBannerView.swift:72` — `item.name` → `item.cleanTitle`

#### Tarea 0.2: Fix HomeMediaCard placeholder ✅
**Archivo**: `HomeMediaCard.swift:159` — `item.name` → `item.cleanTitle`

#### Tarea 0.3: Cachear `parsedMetadata` en Movie y Serie — DECISION TOMADA
**Decision**: Mantener como computed property. Las regex de TitleParser son rapidas para un titulo individual. El costo real esta en listas de 10K+ items donde se llama N veces por item en cada render. Si se detecta un bottleneck futuro, se puede cachear con un diccionario en el ViewModel.

---

### FASE 1: Enriquecimiento Proactivo de Metadata ✅ COMPLETADA

> **Commit**: `5a652bb` — `feat(metadata): add proactive metadata enrichment with stale-while-revalidate`

#### Objetivo
Cuando el Home carga, los items del hero banner y los carousels ya deben tener metadata enriquecida (poster HD, backdrop, plot, etc.) sin que el usuario tenga que abrir el detalle.

#### Tarea 1.1: EnrichedMediaStore ✅ IMPLEMENTADO

**Archivo creado**: `Core/Metadata/EnrichedMediaStore.swift`

Implementacion real (verificada en codebase):
- Actor con `static let shared` singleton
- Three-tier lookup: Memory → Disk (CacheManager) → Network (MetadataEnrichmentService)
- SWR: entries stale after 1 hour, return immediately + revalidate in background
- Request dedup via `inFlightRequests: [String: Task<MetadataResult?, Never>]`
- `invalidate(for:)` method for cache busting
- `prefetch(items:maxConcurrency:)` batch method with TaskGroup (max 5 concurrent)
- Cache key format: `"enriched_{movie|serie}_{streamId}"`
- `buildQuery()` uses TitleParser to extract cleanTitle + year for search

**Diferencias vs plan original**:
- Se agrego `invalidate(for:)` (no estaba en el plan)
- Se agrego `prefetch(items:maxConcurrency:)` como metodo del store (en el plan, la concurrencia estaba en HomeViewModel)
- `revalidate()` ahora verifica `inFlightRequests[key] == nil` para evitar revalidacion duplicada
- `inFlightRequests` se limpia con `removeValue(forKey:)` en vez de asignar nil

#### Tarea 1.2: Prefetch en Home ✅ IMPLEMENTADO

**Archivo modificado**: `HomeViewModel.swift` — metodo `prefetchMetadata()`

Implementacion real (simplificada vs plan):
```swift
func prefetchMetadata() async {
    let store = EnrichedMediaStore.shared
    // Priority 1: Hero banner item
    for section in sections {
        if case .heroBanner(let item) = section.type {
            let tmdbId = (item as? Movie)?.tmdbId.flatMap { Int($0) }
            _ = await store.getEnrichedMetadata(for: item, tmdbId: tmdbId)
            break
        }
    }
    // Priority 2: First 10 items per carousel section
    for section in sections {
        if case .mediaCarousel(let items) = section.type {
            await store.prefetch(items: Array(items.prefix(10)))
        }
    }
}
```

**Diferencias vs plan original**:
- Signature simplificada: `prefetchMetadata()` sin parametros (usa `sections` directamente)
- Carousel prefetch delegado a `store.prefetch()` (el store maneja concurrencia internamente)
- No necesita recibir `movies`/`series` como parametros

**Archivo modificado**: `AppDataLoader.swift` — llamada no-bloqueante
```swift
// Despues del EPG background task:
Task.detached { [weak self] in
    await self?.homeViewModel?.prefetchMetadata()
}
```

**Diferencia vs plan**: No necesita pasar movies/series, mas limpio.

#### Tarea 1.3: tmdbIdInt en LibraryItem ✅ IMPLEMENTADO

**Archivo modificado**: `MediaListViewModel.swift`

```swift
protocol LibraryItem {
    // ... existing properties ...
    var tmdbIdInt: Int? { get }
}

extension Movie: LibraryItem {
    var tmdbIdInt: Int? { tmdbId.flatMap { Int($0) } }
}

extension Serie: LibraryItem {
    /// Serie model does not carry a TMDB ID from the Xtream Codes API.
    /// Enrichment falls back to title+year search in metadata providers.
    var tmdbIdInt: Int? { nil }
}
```

---

### FASE 2: Hero Banner Enriquecido ✅ COMPLETADA

#### Tarea 2.1: Refactorizar HeroBannerView con metadata enriquecida ✅ IMPLEMENTADO

**Archivo**: `HeroBannerView.swift`

```swift
struct HeroBannerView: View {
    let item: any LibraryItem
    @Binding var selectedView: String?
    @State private var enrichedMetadata: MetadataResult?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop: priorizar backdrop enriquecido HD
            backdropImage

            // Gradient overlay
            LinearGradient(...)

            // Content overlay
            VStack(alignment: .leading, spacing: 12) {
                // Type badge
                typeBadge

                // Title: SIEMPRE cleanTitle
                Text(item.cleanTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // Subtitle: year + genre + duration del metadata enriquecido
                if let meta = enrichedMetadata {
                    enrichedSubtitle(meta)
                }

                // Rating
                ratingBadge

                // Plot preview (si hay metadata)
                if let plot = enrichedMetadata?.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }

                // Action buttons
                actionButtons
            }
            .padding(24)
        }
        .frame(height: bannerHeight)
        .task {
            // Fetch enriched metadata en background
            enrichedMetadata = await EnrichedMediaStore.shared
                .getEnrichedMetadata(
                    for: item,
                    tmdbId: item.tmdbIdInt
                )
        }
    }

    @ViewBuilder
    private var backdropImage: some View {
        // Prioridad: 1) backdrop enriquecido, 2) coverImage original
        let backdropURL = enrichedMetadata?.backdropURL
                         ?? item.coverImage
        if let urlStr = backdropURL, let url = URL(string: urlStr) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                         .aspectRatio(contentMode: .fill)
                         .frame(height: bannerHeight)
                         .clipped()
                         .transition(.opacity.combined(with: .scale(scale: 1.02)))
                case .failure: fallbackBanner
                case .empty: SkeletonLoader().frame(height: bannerHeight)
                @unknown default: fallbackBanner
                }
            }
        } else {
            fallbackBanner
        }
    }

    @ViewBuilder
    private func enrichedSubtitle(_ meta: MetadataResult) -> some View {
        HStack(spacing: 8) {
            if let year = meta.year {
                Text(String(year))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !meta.genre.isEmpty {
                Text(meta.genre.prefix(2).joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let runtime = meta.runtimeMinutes, runtime > 0 {
                Text("\(runtime / 60)h \(runtime % 60)m")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .adaptiveGlass(in: Capsule())
    }
}
```

---

### FASE 3: Vista de Detalle Rediseñada (estilo Apple TV+/Netflix)

#### Objetivo
Reemplazar el fullScreenCover/sheet basico con una vista de detalle rica, nativa, con Liquid Glass.

#### Tarea 3.1: Crear `MediaDetailSheet` (nuevo componente)

**Concepto de diseño**:
```
┌──────────────────────────────────────────┐
│  ╔══════════════════════════════════════╗ │
│  ║         BACKDROP IMAGE (HD)         ║ │
│  ║    ┌──────────┐                     ║ │
│  ║    │  POSTER  │  Title              ║ │
│  ║    │  (TMDB)  │  2024 · Drama · 2h  ║ │
│  ║    │          │  ★ 8.5/10           ║ │
│  ║    └──────────┘                     ║ │
│  ║                                     ║ │
│  ║  [▶ Play]  [⬇ Download]  [+ List]  ║ │
│  ╚══════════════════════════════════════╝ │
│                                          │
│  ┌─ Overview ─┬─ Episodes ─┬─ Similar ─┐│
│  │            │            │           ││
│  │  Plot text with full description    ││
│  │                                     ││
│  │  Director: Christopher Nolan        ││
│  │  Cast: Leonardo DiCaprio, ...       ││
│  │                                     ││
│  │  ┌──────┐ ┌──────┐ ┌──────┐        ││
│  │  │ 4K   │ │ HDR  │ │ Atmos│        ││
│  │  └──────┘ └──────┘ └──────┘        ││
│  │                                     ││
│  │  Trailer: [YouTube embed/link]      ││
│  └─────────────────────────────────────┘│
└──────────────────────────────────────────┘
```

**Archivo nuevo**: `Features/Media/Views/MediaDetailSheet.swift`

```swift
struct MediaDetailSheet: View {
    let item: any LibraryItem
    let movieDetail: MovieDetail?
    let serieDetail: SerieDetail?
    let onDismiss: () -> Void

    @State private var enrichedMetadata: MetadataResult?
    @State private var selectedTab: DetailTab = .overview
    @State private var headerHeight: CGFloat = 400
    @State private var scrollOffset: CGFloat = 0

    @EnvironmentObject private var downloadManager: DownloadManager

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case episodes = "Episodes"  // Solo para series
        case similar = "Similar"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Background
                AppColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Collapsing header con backdrop + poster
                        headerView(geometry: geometry)

                        // Tab bar
                        tabBar

                        // Tab content
                        tabContent

                        Spacer(minLength: 40)
                    }
                }

                // Floating close button (glass)
                closeButton
            }
        }
        .task {
            await loadEnrichedMetadata()
        }
    }

    // Header con backdrop + poster + metadata basica
    @ViewBuilder
    private func headerView(geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            // Backdrop HD
            let backdropURL = enrichedMetadata?.backdropURL
                ?? movieDetail?.backdrop
                ?? serieDetail?.info.backdropPath.first
                ?? item.coverImage

            if let url = backdropURL.flatMap({ URL(string: $0) }) {
                CachedAsyncImage(url: url) { phase in
                    // ... image loading
                }
                .frame(width: geometry.size.width, height: 400)
            }

            // Gradient
            LinearGradient(
                colors: [.clear, AppColors.background.opacity(0.5),
                         AppColors.background],
                startPoint: .center,
                endPoint: .bottom
            )

            // Poster + Title + Metadata
            HStack(alignment: .bottom, spacing: 16) {
                // Poster (TMDB quality si disponible)
                let posterURL = enrichedMetadata?.posterURL
                    ?? movieDetail?.movieImage
                    ?? item.coverImage

                if let url = posterURL.flatMap({ URL(string: $0) }) {
                    CachedAsyncImage(url: url) { phase in
                        // ... poster image
                    }
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }

                // Title block
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.cleanTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    // Metadata pills
                    metadataPills

                    // Rating
                    ratingView

                    // Action buttons
                    actionButtons
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var metadataPills: some View {
        HStack(spacing: 6) {
            if let year = enrichedMetadata?.year ?? item.year.flatMap({ Int($0) }) {
                pillView(String(year))
            }
            if let genres = enrichedMetadata?.genre, !genres.isEmpty {
                pillView(genres.first ?? "")
            }
            if let runtime = enrichedMetadata?.runtimeMinutes
                ?? movieDetail?.durationSecs.map({ $0 / 60 }),
               runtime > 0 {
                pillView("\(runtime)min")
            }
            if let quality = item.quality {
                pillView(quality, color: qualityColor(for: quality))
            }
            if item.isHDR {
                pillView("HDR", color: .orange)
            }
        }
    }

    private func pillView(
        _ text: String,
        color: Color = .white.opacity(0.7)
    ) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .adaptiveGlass(in: Capsule())
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                // Play action
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.appGlassProminent)

            Button {
                // Download - NO navega, abre modal
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.appGlass)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewContent
        case .episodes:
            episodesContent
        case .similar:
            Text("Similar content coming soon")
                .foregroundStyle(AppColors.textTertiary)
                .padding()
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Plot
            if let plot = enrichedMetadata?.plot
                ?? movieDetail?.plot
                ?? serieDetail?.info.plot,
               !plot.isEmpty {
                Text(plot)
                    .font(.body)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Director
            if let director = enrichedMetadata?.director
                ?? movieDetail?.director
                ?? serieDetail?.info.director,
               !director.isEmpty {
                infoRow("Director", value: director)
            }

            // Cast
            if let cast = enrichedMetadata?.cast,
               !cast.isEmpty {
                infoRow("Cast", value: cast.prefix(5).joined(separator: ", "))
            } else if let cast = movieDetail?.cast {
                infoRow("Cast", value: cast.prefix(5).joined(separator: ", "))
            }

            // Technical badges
            technicalBadges

            // Trailer
            if let trailer = enrichedMetadata?.artworkURLs.first
                ?? movieDetail?.youtubeTrailer
                ?? serieDetail?.info.youtubeTrailer,
               !trailer.isEmpty {
                trailerButton(youtubeId: trailer)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func loadEnrichedMetadata() async {
        enrichedMetadata = await EnrichedMediaStore.shared
            .getEnrichedMetadata(for: item, tmdbId: item.tmdbIdInt)
    }
}
```

#### Tarea 3.2: Integrar en MediaListView

**Archivo**: `MediaListView.swift` — reemplazar fullScreenCover content

```swift
// ANTES:
.fullScreenCover(isPresented: $showingFullScreenDetail) {
    PlatformSpecificAddDownloadViewMovie(...)
}

// DESPUES:
.fullScreenCover(isPresented: $showingFullScreenDetail) {
    if let movieDetailVM = movieDetailViewModel,
       let detail = movieDetailVM.movieDetail {
        MediaDetailSheet(
            item: detail.movieData,
            movieDetail: detail,
            serieDetail: nil,
            onDismiss: dismissMediaDetail
        )
        .environmentObject(downloadManager)
    } else if let serieDetailVM = serieDetailViewModel,
              let detail = serieDetailVM.serieDetail {
        MediaDetailSheet(
            item: ..., // need to pass Serie
            movieDetail: nil,
            serieDetail: detail,
            onDismiss: dismissMediaDetail
        )
        .environmentObject(downloadManager)
    }
}
```

#### Tarea 3.3: Download sin perder detalle

**Cambio clave**: El boton "Download" no debe navegar a la tab Downloads ni cerrar el detalle. Debe:
1. Mostrar un sheet modal de opciones de descarga (ya existe `DownloadOptionsModal`)
2. Iniciar la descarga en background
3. Mostrar un toast/banner de confirmacion
4. El detalle permanece abierto

```swift
// En MediaDetailSheet:
@State private var showDownloadOptions = false
@State private var downloadStarted = false

Button {
    showDownloadOptions = true
} label: {
    Label("Download", systemImage: "arrow.down.circle")
}
.sheet(isPresented: $showDownloadOptions) {
    DownloadOptionsModal(
        // ... opciones
        onStartDownload: {
            downloadManager.startDownload(...)
            showDownloadOptions = false
            downloadStarted = true
            // NO llamar onDismiss()
            // NO navegar a Downloads
        }
    )
}
.overlay(alignment: .top) {
    if downloadStarted {
        downloadConfirmationBanner
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { downloadStarted = false }
                }
            }
    }
}
```

---

### FASE 4: Stale-While-Revalidate en CacheManager

#### Tarea 4.1: Refactorizar CacheManager con SWR

**Archivo**: `CacheManager.swift` — agregar metodo generico SWR

```swift
/// Resultado de cache con informacion de staleness
struct CacheResult<T> {
    let value: T
    let age: TimeInterval
    let isStale: Bool
}

extension CacheManager {
    /// Stale-while-revalidate: devuelve dato cacheado aunque este
    /// expirado, pero indica si es stale para trigger background refresh.
    func getCacheWithStaleness<T: Decodable>(
        key: String,
        type: T.Type,
        freshTTL: TimeInterval,    // Dentro de este TTL → fresh
        staleTTL: TimeInterval     // Dentro de este TTL → stale pero usable
    ) -> CacheResult<T>? {
        return queue.sync {
            let fileURL = cacheDirectory
                .appendingPathComponent("\(key).json")

            guard FileManager.default.fileExists(atPath: fileURL.path)
            else { return nil }

            do {
                let attrs = try FileManager.default
                    .attributesOfItem(atPath: fileURL.path)
                let modDate = attrs[.modificationDate] as? Date ?? Date()
                let age = Date().timeIntervalSince(modDate)

                // Beyond stale TTL → truly expired, return nil
                if age > staleTTL { return nil }

                let data = try Data(contentsOf: fileURL)
                let value = try JSONDecoder().decode(type, from: data)

                return CacheResult(
                    value: value,
                    age: age,
                    isStale: age > freshTTL
                )
            } catch {
                return nil
            }
        }
    }
}
```

#### Tarea 4.2: Usar SWR en MediaListViewModel

```swift
func loadMedia(...) async {
    // ...
    if !forceRefresh {
        let result = cacheManager.getCacheWithStaleness(
            key: mediaListKey(type: "movies", categoryId: categoryId),
            type: [Movie].self,
            freshTTL: 1800,     // 30 min fresh
            staleTTL: 86400     // 24h stale pero usable
        )
        if let result {
            movies = orderByAddedDesc(result.value)
            didLoadMovies = true
            loadedFromCache = true

            if result.isStale {
                Task { await refreshMoviesInBackground(categoryId: categoryId) }
            }
            return  // No esperar al refresh
        }
    }
    // ... fetch from network
}
```

---

### FASE 5: Mejoras de UI con Liquid Glass

#### Tarea 5.1: Enhanced Hero Banner con Liquid Glass

```swift
// En HeroBannerView: reemplazar gradient overlay con glass effect
VStack(alignment: .leading, spacing: 12) {
    // ... content
}
.padding(24)
.background {
    if #available(iOS 26, macOS 26, *) {
        GlassEffectContainer(
            in: UnevenRoundedRectangle(
                topLeadingRadius: 0,
                topTrailingRadius: 0,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20
            )
        )
        .glassEffectTint(AppColors.glassTint)
    } else {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.95)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

#### Tarea 5.2: Tab bar con Glass Segmented Control en MediaDetailSheet

```swift
// Reutilizar GlassSegmentedControl existente
GlassSegmentedControl(
    options: visibleTabs.map(\.rawValue),
    selectedOption: Binding(
        get: { selectedTab.rawValue },
        set: { selectedTab = DetailTab(rawValue: $0) ?? .overview }
    )
)
.padding(.horizontal, 20)
```

---

### FASE 6: Serie Detail con episodios

#### Tarea 6.1: Tab "Episodes" en MediaDetailSheet

```swift
@ViewBuilder
private var episodesContent: some View {
    if let serieDetail {
        VStack(alignment: .leading, spacing: 16) {
            // Season picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(serieDetail.seasons, id: \.id) { season in
                        Button(season.name) {
                            selectedSeason = season.seasonNumber
                        }
                        .buttonStyle(
                            selectedSeason == season.seasonNumber
                            ? .appGlassProminent : .appGlass
                        )
                    }
                }
                .padding(.horizontal, 20)
            }

            // Episode list
            let episodes = serieDetail.episodes[
                String(selectedSeason)
            ] ?? []
            ForEach(episodes, id: \.id) { episode in
                EpisodeRow(
                    episode: episode,
                    serieDetail: serieDetail,
                    onPlay: { /* play episode */ },
                    onDownload: { /* download episode */ }
                )
            }
        }
    }
}
```

---

## SECCION 3: Diagrama de Arquitectura (actual post Fase 1 + objetivo)

```
┌──────────────────────────────────────────────────────────────────────┐
│                        IPTV SERVER                                   │
└──────────────────┬───────────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                     MovieService (actor)                             │
└──────────────────┬───────────────────────────────────────────────────┘
                   │
          ┌────────┴───────────────────────────┐
          ▼                                    ▼
┌──────────────────────┐        ┌──────────────────────────────────┐
│   CacheManager       │        │  MediaListViewModel              │
│   (SWR enabled)      │◄──────►│  - loadMedia() con SWR           │
│                      │        │  - prefetch logic                 │
│   freshTTL: 30min    │        └──────────────┬───────────────────┘
│   staleTTL: 24h      │                       │
└──────────┬───────────┘               ┌───────┴───────┐
           │                           ▼               ▼
           │                    ┌────────────┐  ┌────────────────┐
           │                    │HomeViewModel│  │MediaDetailView │
           │                    │assembleSect │  │Model           │
           │                    │+ prefetch   │  │+ enrichMetadata│
           │                    └──────┬─────┘  └───────┬────────┘
           │                           │                │
           ▼                           ▼                ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    EnrichedMediaStore (actor)                        │
│                                                                      │
│  ┌─────────────────┐    ┌───────────────┐    ┌──────────────────┐  │
│  │ Memory Cache    │    │ Disk Cache    │    │ In-Flight Dedup  │  │
│  │ [String:Entry]  │    │ (CacheManager)│    │ [String:Task]    │  │
│  └────────┬────────┘    └───────┬───────┘    └────────┬─────────┘  │
│           │                     │                     │            │
│           └─────────┬───────────┴─────────────────────┘            │
│                     ▼                                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │         MetadataEnrichmentService.shared (actor)             │  │
│  │                                                              │  │
│  │  ┌──────────────┐  ┌───────────────┐  ┌────────────────┐   │  │
│  │  │ TMDB Provider│  │ TheTVDB Prov. │  │ iTunes Prov.   │   │  │
│  │  │ (ID→1.0)     │  │ (search→0.4) │  │ (artwork)      │   │  │
│  │  └──────────────┘  └───────────────┘  └────────────────┘   │  │
│  │                                                              │  │
│  │  MetadataResolver (scoring heuristico)                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                          UI LAYER                                    │
│                                                                      │
│  HomeView                                                           │
│  ├── HeroBannerView (✅ cleanTitle, 🔲 enriched backdrop/plot F2)   │
│  ├── HomeMediaCarousel → HomeMediaCard (✅ cleanTitle)              │
│  ├── EPG sections                                                   │
│  └── ✅ prefetchMetadata() runs after assembleSections (F1)         │
│                                                                      │
│  MediaListView                                                      │
│  ├── MovieCardView / SerieCardView (✅ formattedTitle = cleanTitle) │
│  └── .fullScreenCover → 🔲 MediaDetailSheet (F3, actualmente usa   │
│      │                    AddDownloadMediaViewiOS / AddDownloadView) │
│      ├── 🔲 Collapsing header (backdrop HD + poster TMDB)          │
│      ├── 🔲 GlassSegmentedControl tabs                             │
│      ├── 🔲 Overview (plot, cast, director, technical badges)      │
│      ├── 🔲 Episodes (para series, con season picker)              │
│      ├── 🔲 Action buttons (play, download SIN navegar)            │
│      └── 🔲 Download modal (in-place, no pierde el detalle)        │
└──────────────────────────────────────────────────────────────────────┘
```

---

## SECCION 4: Orden de Ejecucion y Dependencias

```
Fase 0: Quick Fixes ✅ COMPLETADA (57f612c)
  ├── 0.1 Fix HeroBannerView cleanTitle      ✅
  ├── 0.2 Fix HomeMediaCard placeholder       ✅
  └── 0.3 parsedMetadata cache → Decision: mantener computed

Fase 1: Enriquecimiento Proactivo ✅ COMPLETADA (5a652bb)
  ├── 1.1 EnrichedMediaStore (nuevo)          ✅ Core/Metadata/EnrichedMediaStore.swift
  ├── 1.2 Prefetch en HomeViewModel           ✅ prefetchMetadata() + AppDataLoader
  └── 1.3 tmdbIdInt en LibraryItem            ✅ Movie + Serie conformances

Fase 2: Hero Banner Enriquecido ✅ COMPLETADA
  └── 2.1 HeroBannerView con metadata enriquecida   ✅ backdrop HD, subtitle, plot, rating

Fase 3: Vista de Detalle               ← Requiere Fase 1 ✅
  ├── 3.1 MediaDetailSheet (nuevo)
  ├── 3.2 Integrar en MediaListView    ← Requiere 3.1
  └── 3.3 Download sin perder detalle  ← Requiere 3.1

Fase 4: SWR en CacheManager            ← Independiente (puede ir en paralelo con Fase 2/3)
  ├── 4.1 getCacheWithStaleness generico
  └── 4.2 Usar en MediaListViewModel

Fase 5: Liquid Glass UI                ← Requiere Fase 2 y 3
  ├── 5.1 Glass en Hero Banner
  └── 5.2 Glass tabs en detail

Fase 6: Serie Detail con episodios     ← Requiere Fase 3
  └── 6.1 Tab Episodes con season picker
```

---

## SECCION 5: Archivos a Crear/Modificar

### Archivos NUEVOS:
| Archivo | Fase | Estado | Descripcion |
|---------|------|--------|-------------|
| `Core/Metadata/EnrichedMediaStore.swift` | 1.1 | ✅ CREADO | Actor para metadata enriquecida con SWR y dedup |
| `Features/Media/Views/MediaDetailSheet.swift` | 3.1 | 🔲 PENDIENTE | Vista de detalle rediseñada |
| `Features/Media/Views/EpisodeRow.swift` | 6.1 | 🔲 PENDIENTE | Fila de episodio para series |

### Archivos MODIFICADOS:
| Archivo | Fase | Estado | Cambio |
|---------|------|--------|--------|
| `HeroBannerView.swift` | 0.1 | ✅ HECHO | `item.name` → `item.cleanTitle` |
| `HeroBannerView.swift` | 2.1 | ✅ HECHO | Enriched backdrop, subtitle (year/genre/runtime), plot, TMDB rating |
| `HomeMediaCard.swift` | 0.2 | ✅ HECHO | `item.name` → `item.cleanTitle` en placeholder |
| `HomeViewModel.swift` | 1.2 | ✅ HECHO | `prefetchMetadata()` method added |
| `AppDataLoader.swift` | 1.2 | ✅ HECHO | Non-blocking `Task.detached` prefetch call |
| `MediaListViewModel.swift` | 1.3 | ✅ HECHO | `tmdbIdInt` en LibraryItem protocol + conformances |
| `MediaListViewModel.swift` | 4.2 | 🔲 PENDIENTE | SWR generico en loadMedia() |
| `MediaListView.swift` | 3.2 | 🔲 PENDIENTE | Reemplazar fullScreenCover → MediaDetailSheet |
| `CacheManager.swift` | 4.1 | 🔲 PENDIENTE | `getCacheWithStaleness()` generico |

---

## SECCION 6: Datos Disponibles por Fuente

### Datos de la API IPTV (Xtream Codes):
```
Movie:    name, streamId, tmdbId, streamIcon, rating, added, categoryId
Serie:    name, seriesId, cover, plot, cast, director, genre, releaseDate,
          backdropPath[], youtubeTrailer, rating
MovieDet: + movieImage, backdrop, plot, cast[], director, genre, duration
SerieDet: + seasons[], episodes{}, episodeInfo (per-episode metadata)
```

### Datos de TMDB (via TMDBMetadataProvider):
```
title, originalTitle, year, releaseDate, genre[], plot, director,
cast[] (top 10), rating (voteAverage), runtimeMinutes,
posterURL (w500), backdropURL (w1280), artworkURLs (original),
tmdbId, imdbId, confidence
```

### Datos de TheTVDB (via TheTVDBMetadataProvider):
```
title, year, genre[], plot, cast[], rating, artworkURLs,
imdbId, confidence (0.4 base)
```

### Datos de iTunes (via ITunesSearchProvider):
```
title, artworkURLs (600x600, 1200x1200),
contentAdvisoryRating, itunesTrackId, confidence
```

### Prioridad de datos (merge strategy):
```
1. IPTV API (siempre base, mas confidence para identidad)
2. TMDB (si tmdbId disponible → confidence 1.0, complementa todo)
3. TheTVDB (fuerte para series, complementa si TMDB no tiene datos)
4. iTunes (solo para artwork alta calidad y advisory rating)
```

---

## SECCION 7: Resumen de Problemas y Soluciones

| # | Problema | Solucion | Fase | Estado |
|---|----------|----------|------|--------|
| 1 | Hero banner muestra titulo crudo | `item.name` → `item.cleanTitle` | 0.1 | ✅ |
| 2 | Placeholder muestra titulo crudo | `item.name` → `item.cleanTitle` | 0.2 | ✅ |
| 3 | parsedMetadata no cacheado | Decision: mantener computed (regex rapido) | 0.3 | ✅ |
| 4 | No hay prefetch de metadata | EnrichedMediaStore + prefetchMetadata() | 1.x | ✅ |
| 5 | Hero banner sin backdrop HD | Usar metadata enriquecida en HeroBanner | 2.1 | ✅ |
| 6 | Detalle tipo dialogo basico | MediaDetailSheet con tabs y glass | 3.1 | 🔲 |
| 7 | Download cierra el detalle | Modal in-place sin navegacion | 3.3 | 🔲 |
| 8 | No hay SWR real en cache | getCacheWithStaleness() generico | 4.x | 🔲 |
| 9 | No hay glass en detalle | Liquid Glass tabs y background | 5.x | 🔲 |
| 10 | No hay tab Episodes en series | EpisodeRow + season picker | 6.1 | 🔲 |
| 11 | Requests duplicados | Dedup via inFlightRequests en Store | 1.1 | ✅ |
| 12 | Serie no tiene tmdbId | Buscar por cleanTitle + year en TMDB | 1.1 | ✅ |

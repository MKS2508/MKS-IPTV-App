# Enrichment Plan: Metadata, Caching, UI/UX y Liquid Glass

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

## BUG CONFIRMADO: Hero Banner muestra `item.name` en vez de `item.cleanTitle`

### Archivo: `HeroBannerView.swift:72`
```swift
// ACTUAL (BUG):
Text(item.name)         // "Movie.Title.2021.1080p.WEB-DL.x264"

// CORRECTO:
Text(item.cleanTitle)   // "Movie Title"
```

### Otros usos inconsistentes de `item.name`:
| Archivo | Linea | Propiedad | Deberia ser |
|---------|-------|-----------|-------------|
| `HeroBannerView.swift` | 72 | `item.name` | `item.cleanTitle` |
| `HomeMediaCard.swift` | 159 | `item.name` (placeholder) | `item.cleanTitle` |

### Usos correctos (ya funcionan):
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
│  HomeView → HeroBannerView (⚠️ usa item.name)                      │
│          → HomeMediaCarousel → HomeMediaCard (✓ usa item.cleanTitle)│
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
│  ⚠️ PROBLEMAS:                                                      │
│  1. No hay stale-while-revalidate real (solo background refresh     │
│     manual en cada ViewModel)                                       │
│  2. parsedMetadata se recalcula en CADA acceso (no cacheado)        │
│  3. No hay dedup de requests en vuelo                               │
│  4. No hay prefetch de metadata para items del Home                 │
│  5. No hay persistencia de MetadataResult enriquecidos              │
│     asociados a Movie/Serie                                         │
│  6. clearExpiredCache() usa cacheExpiration (1h) para TODO,         │
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
│  ⚠️ PROBLEMA: Solo se usa en MovieDetailViewModel.enrichMetadata()  │
│     cuando se abre un detalle. NO se usa proactivamente al cargar   │
│     el Home ni las listas.                                          │
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

### FASE 0: Quick Fixes (sin refactorizacion)

#### Tarea 0.1: Fix Hero Banner cleanTitle
**Archivo**: `HeroBannerView.swift:72`
```swift
// ANTES:
Text(item.name)

// DESPUES:
Text(item.cleanTitle)
```

#### Tarea 0.2: Fix HomeMediaCard placeholder
**Archivo**: `HomeMediaCard.swift:159`
```swift
// ANTES:
Text(item.name)

// DESPUES:
Text(item.cleanTitle)
```

#### Tarea 0.3: Cachear `parsedMetadata` en Movie y Serie
**Problema**: `TitleParser.parse(name)` se ejecuta con regex en CADA acceso a `cleanTitle`, `quality`, etc. Es un computed property sin cache.

**Archivo**: `Movie.swift`
```swift
// ANTES:
var parsedMetadata: TitleMetadata {
    TitleParser.parse(name)
}

// DESPUES:
private var _parsedMetadata: TitleMetadata?

var parsedMetadata: TitleMetadata {
    // No se puede mutar en struct, asi que usamos lazy pattern via wrapper
    // o simplemente aceptamos el costo (regex es rapido para un solo titulo)
    TitleParser.parse(name)
}
```

**Decision**: Mantener como computed. Las regex son rapidas para un titulo individual. El costo real esta en listas de 10K+ items donde se llama N veces por item en cada render. Si se detecta un bottleneck, se puede cachear con un wrapper `@LazyParsed` o un diccionario en el ViewModel.

---

### FASE 1: Enriquecimiento Proactivo de Metadata

#### Objetivo
Cuando el Home carga, los items del hero banner y los carousels ya deben tener metadata enriquecida (poster HD, backdrop, plot, etc.) sin que el usuario tenga que abrir el detalle.

#### Tarea 1.1: Crear `EnrichedMediaStore` (nuevo actor)

**Archivo nuevo**: `Core/Metadata/EnrichedMediaStore.swift`

```swift
/// Actor que almacena y gestiona metadata enriquecida para Movie/Serie.
/// Implementa stale-while-revalidate: devuelve datos cacheados inmediatamente
/// y refresca en background si estan expirados.
actor EnrichedMediaStore {
    static let shared = EnrichedMediaStore()

    /// In-memory cache de MetadataResult por media ID
    /// Key: "movie_{streamId}" o "serie_{seriesId}"
    private var memoryCache: [String: EnrichedEntry] = [:]

    /// Requests en vuelo para dedup
    private var inFlightRequests: [String: Task<MetadataResult?, Never>] = [:]

    struct EnrichedEntry {
        let result: MetadataResult
        let fetchedAt: Date
        var isStale: Bool {
            Date().timeIntervalSince(fetchedAt) > 3600 // 1 hora
        }
    }

    /// Obtiene metadata enriquecida. Stale-while-revalidate:
    /// 1. Si hay cache valido → devuelve inmediato
    /// 2. Si hay cache stale → devuelve inmediato + revalida en background
    /// 3. Si no hay cache → fetch y devuelve
    func getEnrichedMetadata(
        for item: any LibraryItem,
        tmdbId: Int? = nil
    ) async -> MetadataResult? {
        let key = cacheKey(for: item)

        // 1. Check memory cache
        if let entry = memoryCache[key] {
            if !entry.isStale {
                return entry.result
            }
            // Stale: return immediately but trigger background refresh
            Task { await revalidate(key: key, item: item, tmdbId: tmdbId) }
            return entry.result
        }

        // 2. Check disk cache (CacheManager)
        if let diskCached = CacheManager.shared.getCachedMetadata(key: key) {
            memoryCache[key] = EnrichedEntry(result: diskCached, fetchedAt: Date())
            return diskCached
        }

        // 3. Fetch from providers (with dedup)
        return await fetchWithDedup(key: key, item: item, tmdbId: tmdbId)
    }

    private func fetchWithDedup(
        key: String,
        item: any LibraryItem,
        tmdbId: Int?
    ) async -> MetadataResult? {
        // Dedup: if already in-flight, await existing task
        if let existing = inFlightRequests[key] {
            return await existing.value
        }

        let task = Task<MetadataResult?, Never> {
            let query = buildQuery(for: item, tmdbId: tmdbId)
            let result = await MetadataEnrichmentService.shared
                                    .fetchMetadata(query: query)
            if let result {
                memoryCache[key] = EnrichedEntry(
                    result: result, fetchedAt: Date()
                )
                CacheManager.shared.cacheMetadata(result, key: key)
            }
            return result
        }
        inFlightRequests[key] = task
        let result = await task.value
        inFlightRequests[key] = nil
        return result
    }

    private func revalidate(
        key: String,
        item: any LibraryItem,
        tmdbId: Int?
    ) async {
        let query = buildQuery(for: item, tmdbId: tmdbId)
        if let result = await MetadataEnrichmentService.shared
                                .fetchMetadata(query: query) {
            memoryCache[key] = EnrichedEntry(
                result: result, fetchedAt: Date()
            )
            CacheManager.shared.cacheMetadata(result, key: key)
        }
    }

    private func cacheKey(for item: any LibraryItem) -> String {
        let type = item.libraryType == .movie ? "movie" : "serie"
        return "enriched_\(type)_\(item.streamId)"
    }

    private func buildQuery(
        for item: any LibraryItem,
        tmdbId: Int?
    ) -> MetadataSearchQuery {
        let parsed = TitleParser.parse(item.name)
        let yearInt = parsed.year.flatMap { Int($0) }
        return MetadataSearchQuery(
            title: parsed.cleanTitle,
            year: yearInt,
            tmdbId: tmdbId,
            genre: nil,
            runtimeMinutes: nil,
            mediaType: item.libraryType == .movie ? .movie : .series
        )
    }
}
```

#### Tarea 1.2: Prefetch de metadata en Home

**Archivo**: `HomeViewModel.swift` — agregar metodo `prefetchMetadata`

```swift
/// Prefetch metadata para los items visibles en Home.
/// Se ejecuta despues de assembleSections() en background.
func prefetchMetadata(movies: [Movie], series: [Serie]) async {
    let store = EnrichedMediaStore.shared

    // Prioridad 1: Hero banner
    if let heroSection = sections.first(where: {
        if case .heroBanner = $0.type { return true }; return false
    }), case .heroBanner(let item) = heroSection.type {
        let tmdbId = (item as? Movie)?.tmdbId.flatMap { Int($0) }
        _ = await store.getEnrichedMetadata(for: item, tmdbId: tmdbId)
    }

    // Prioridad 2: Items de carousels (primeros 10 de cada seccion)
    for section in sections {
        if case .mediaCarousel(let items) = section.type {
            await withTaskGroup(of: Void.self) { group in
                for item in items.prefix(10) {
                    group.addTask {
                        let tmdbId = (item as? Movie)?.tmdbId
                                        .flatMap { Int($0) }
                        _ = await store.getEnrichedMetadata(
                            for: item, tmdbId: tmdbId
                        )
                    }
                }
            }
        }
    }
}
```

**Archivo**: `AppDataLoader.swift` — llamar prefetch despues de assembleHomeSections

```swift
// En loadAllData(), despues de assembleHomeSections():
Task.detached { [weak self] in
    guard let self, let hvm = self.homeViewModel,
          let mvm = self.mediaViewModel else { return }
    await hvm.prefetchMetadata(
        movies: await mvm.movies,
        series: await mvm.series
    )
}
```

#### Tarea 1.3: Exponer metadata enriquecida en LibraryItem

**Archivo**: `MediaListViewModel.swift` — agregar al protocolo LibraryItem

```swift
protocol LibraryItem {
    // ... existing properties ...

    // Metadata enriquecida (puede ser nil si aun no se ha fetcheado)
    var tmdbIdInt: Int? { get }
}

extension Movie: LibraryItem {
    var tmdbIdInt: Int? { tmdbId.flatMap { Int($0) } }
}

extension Serie: LibraryItem {
    var tmdbIdInt: Int? { nil }  // Serie no tiene tmdbId en el modelo base
}
```

---

### FASE 2: Hero Banner Enriquecido

#### Tarea 2.1: Refactorizar HeroBannerView con metadata enriquecida

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

## SECCION 3: Diagrama de Arquitectura Objetivo

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
│  ├── HeroBannerView (enriched: backdrop HD, plot, genre, runtime)   │
│  ├── HomeMediaCarousel → HomeMediaCard (cleanTitle, enriched poster)│
│  └── EPG sections                                                   │
│                                                                      │
│  MediaListView                                                      │
│  ├── MovieCardView / SerieCardView (formattedTitle = cleanTitle)    │
│  └── .fullScreenCover → MediaDetailSheet (NEW)                      │
│      ├── Collapsing header (backdrop HD + poster TMDB)              │
│      ├── GlassSegmentedControl tabs                                 │
│      ├── Overview (plot, cast, director, technical badges)          │
│      ├── Episodes (para series, con season picker)                  │
│      ├── Action buttons (play, download SIN navegar)                │
│      └── Download modal (in-place, no pierde el detalle)            │
└──────────────────────────────────────────────────────────────────────┘
```

---

## SECCION 4: Orden de Ejecucion y Dependencias

```
Fase 0: Quick Fixes                    ← SIN dependencias, hacer PRIMERO
  ├── 0.1 Fix HeroBannerView cleanTitle
  ├── 0.2 Fix HomeMediaCard placeholder
  └── 0.3 (Evaluar) parsedMetadata cache

Fase 1: Enriquecimiento Proactivo      ← Requiere Fase 0
  ├── 1.1 EnrichedMediaStore (nuevo)
  ├── 1.2 Prefetch en HomeViewModel    ← Requiere 1.1
  └── 1.3 tmdbIdInt en LibraryItem     ← Requiere 1.1

Fase 2: Hero Banner Enriquecido        ← Requiere Fase 1
  └── 2.1 HeroBannerView con metadata

Fase 3: Vista de Detalle               ← Requiere Fase 1
  ├── 3.1 MediaDetailSheet (nuevo)
  ├── 3.2 Integrar en MediaListView    ← Requiere 3.1
  └── 3.3 Download sin perder detalle  ← Requiere 3.1

Fase 4: SWR en CacheManager            ← Independiente (puede ir en paralelo)
  ├── 4.1 getCacheWithStaleness
  └── 4.2 Usar en MediaListViewModel

Fase 5: Liquid Glass UI                ← Requiere Fase 2 y 3
  ├── 5.1 Glass en Hero Banner
  └── 5.2 Glass tabs en detail

Fase 6: Serie Detail con episodios     ← Requiere Fase 3
  └── 6.1 Tab Episodes
```

---

## SECCION 5: Archivos a Crear/Modificar

### Archivos NUEVOS:
| Archivo | Fase | Descripcion |
|---------|------|-------------|
| `Core/Metadata/EnrichedMediaStore.swift` | 1.1 | Actor para metadata enriquecida con SWR |
| `Features/Media/Views/MediaDetailSheet.swift` | 3.1 | Vista de detalle rediseñada |
| `Features/Media/Views/EpisodeRow.swift` | 6.1 | Fila de episodio para series |

### Archivos a MODIFICAR:
| Archivo | Fase | Cambio |
|---------|------|--------|
| `HeroBannerView.swift` | 0.1, 2.1 | `item.name` → `item.cleanTitle` + metadata enriquecida |
| `HomeMediaCard.swift` | 0.2 | `item.name` → `item.cleanTitle` en placeholder |
| `HomeViewModel.swift` | 1.2 | Agregar `prefetchMetadata()` |
| `AppDataLoader.swift` | 1.2 | Llamar prefetch despues de assembleHomeSections |
| `MediaListViewModel.swift` | 1.3, 4.2 | `tmdbIdInt` en LibraryItem + SWR |
| `MediaListView.swift` | 3.2 | Reemplazar fullScreenCover content |
| `CacheManager.swift` | 4.1 | Agregar `getCacheWithStaleness()` |

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

| # | Problema | Solucion | Fase |
|---|----------|----------|------|
| 1 | Hero banner muestra titulo crudo | `item.name` → `item.cleanTitle` | 0.1 |
| 2 | Placeholder muestra titulo crudo | `item.name` → `item.cleanTitle` | 0.2 |
| 3 | parsedMetadata no cacheado | Evaluar: mantener computed (regex rapido) | 0.3 |
| 4 | No hay prefetch de metadata | EnrichedMediaStore + prefetch en Home | 1.x |
| 5 | Hero banner sin backdrop HD | Usar metadata enriquecida en HeroBanner | 2.1 |
| 6 | Detalle tipo dialogo basico | MediaDetailSheet con tabs y glass | 3.1 |
| 7 | Download cierra el detalle | Modal in-place sin navegacion | 3.3 |
| 8 | No hay SWR real en cache | getCacheWithStaleness() | 4.x |
| 9 | No hay glass en detalle | Liquid Glass tabs y background | 5.x |
| 10 | No hay tab Episodes en series | EpisodeRow + season picker | 6.1 |
| 11 | Requests duplicados | Dedup via inFlightRequests en Store | 1.1 |
| 12 | Serie no tiene tmdbId | Buscar por cleanTitle + year en TMDB | 1.1 |

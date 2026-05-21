# mksiptv-server#4 — Series Endpoints

## Summary

Exponer series y episodios via REST API. Endpoints para listar, buscar, obtener detalles con episodios, y saison info.

## Context

- `IPTVService` actor ya tiene: `fetchSeries()`, `fetchSerieDetails(seriesId:)`
- `Serie` model: `seriesId`, `name`, `cover`, `plot`, `genre`, `cast`, `rating`
- `SerieDetail`: incluye `seasons: [Season]`, `episodes: [String: [Episode]]`

## Scope

### Must Have
- [ ] `GET /series` → lista series (paginación, filtro por categoría)
- [ ] `GET /series/:id` → detalle con episodios
- [ ] `GET /series/:id/seasons/:season` → episodios de una saison
- [ ] `GET /series/:id/stream-url?episode=1&season=1` → URL streaming episodio

### Should Have
- [ ] `GET /series/categories` → categorías
- [ ] Filtro por año, rating

### Won't Have
- Playback (eso es cosa del cliente)
- TMDB enrichment

## Data Model

```swift
struct SerieResponse: Codable {
    let id: Int           // seriesId
    let name: String
    let cover: String?
    let plot: String?
    let genre: String?
    let rating: String?
    let categoryId: String?
    let episodeCount: Int?
}

struct SerieDetailResponse: Codable {
    let id: Int
    let name: String
    let cover: String?
    let plot: String
    let genre: String
    let cast: [String]
    let director: String
    let rating: String?
    let releaseDate: String
    let backdropPaths: [String]?
    let youtubeTrailer: String?
    let seasons: [SeasonResponse]
    let episodeCount: Int
}

struct SeasonResponse: Codable {
    let seasonNumber: Int
    let cover: String?
    let episodeCount: Int
}

struct EpisodeResponse: Codable {
    let episodeNum: Int
    let title: String
    let plot: String?
    let duration: String?
    let cover: String?
    let added: String
    let streamId: Int
}

struct EpisodeStreamURLResponse: Codable {
    let seriesId: Int
    let season: Int
    let episode: Int
    let episodeStreamId: Int
    let url: String
    let extension: String
}
```

## API Design

```
GET /series                              → [SerieResponse]
GET /series?category=14&limit=20         → [SerieResponse]
GET /series/:id                          → SerieDetailResponse
GET /series/:id/seasons/:season          → [EpisodeResponse]
GET /series/:id/stream-url?season=1&episode=3 → EpisodeStreamURLResponse
GET /series/categories                   → [CategoryResponse]
```

## Stream URL Episode Mapping

Xtream Codes episode URLs usan el `streamId` del episodio (no el de la serie):
```
{baseURL}/series/{username}/{password}/{episodeStreamId}.{extension}
```

## Error Responses

```json
// 404 Not Found
{"error": "SERIE_NOT_FOUND", "message": "Serie with id 123 not found"}
{"error": "EPISODE_NOT_FOUND", "message": "Episode S01E05 not found"}

// 400 Bad Request
{"error": "INVALID_SEASON", "message": "Season 99 does not exist for this series"}
```

## Technical Notes

- SerieDetail tiene episodes en formato `episodes[seasonNumber] = [Episode]`
- El episode streamId está en `Episode.id`
- `containerExtension` del episodio para construir URL

## Verification

```bash
# List series
curl http://localhost:4848/series?limit=5

# Get detail with seasons
curl http://localhost:4848/series/12345

# Get stream URL for specific episode
curl "http://localhost:4848/series/12345/stream-url?season=1&episode=3"
```

## File Ownership

- `Sources/mksiptv-server/Models/SerieModels.swift` — crear
- `Sources/mksiptv-server/Routes/SerieRoutes.swift` — crear
- `Sources/mksiptv-server/Services/SeriesService+API.swift` — crear

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [2] |
| estimate | 1h |
| phase | 4 |
| priority | medium |
| status | pending |
| tags | [series, api, iptv] |

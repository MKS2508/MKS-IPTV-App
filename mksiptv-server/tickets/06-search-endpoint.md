# mksiptv-server#6 — Unified Search Endpoint

## Summary

Endpoint único que busca en movies, series y live channels simultáneamente. Devuelve resultados agregados con tipo y metadata básica.

## Context

- Los 3 tipos (movie, series, live channels) tienen search implícito via IPTVService
- La búsqueda en Xtream Codes es server-side (param `search`)

## Scope

### Must Have
- [ ] `GET /search?q=` → búsqueda en todos los tipos
- [ ] Filtro por tipo: `?q=avatar&type=movie`
- [ ] Paginación global (no por tipo)

### Should Have
- [ ] Highlight del término buscado en resultados
- [ ] Búsqueda fuzzy (Levenshtein) como fallback si Xtream no devuelve resultados

### Won't Have
- Búsqueda en EPG
- Indexación local (Elasticsearch, etc.)

## Data Model

```swift
enum MediaType: String, Codable {
    case movie
    case series
    case liveChannel = "live_channel"
}

struct SearchResult: Codable {
    let id: Int
    let name: String
    let type: MediaType
    let icon: String?
    let categoryId: String?
    let categoryName: String?
    let rating: String?
    // Para movies/series
    let streamId: Int?
    // Para live channels
    let channelNumber: Int?
}

struct SearchResponse: Codable {
    let query: String
    let total: Int
    let results: [SearchResult]
    // Breakdown por tipo
    let counts: [MediaType: Int]
}
```

## API Design

```
GET /search?q=avatar                    → SearchResponse
GET /search?q=la%20liga&type=series     → SearchResponse (solo series)
GET /search?q=bbc&type=live_channel     → SearchResponse (solo canales)
GET /search?q=avatar&limit=20&offset=0  → SearchResponse
```

### Query Parameters

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `q` | String | **required** | Término de búsqueda |
| `type` | MediaType | all | Filtrar por tipo |
| `limit` | Int | 50 | Max resultados totales |
| `offset` | Int | 0 |Offset global |

## Response Example

```json
{
  "query": "avatar",
  "total": 5,
  "results": [
    {
      "id": 1,
      "name": "Avatar",
      "type": "movie",
      "icon": "http://xtream.example.com/cover.jpg",
      "categoryId": "18",
      "categoryName": "Movies",
      "rating": "8.5",
      "streamId": 1
    },
    {
      "id": 2,
      "name": "Avatar: The Last Airbender",
      "type": "series",
      "icon": "http://xtream.example.com/cover.jpg",
      "categoryId": "14",
      "categoryName": "Series",
      "rating": "9.3",
      "streamId": 2
    }
  ],
  "counts": {
    "movie": 1,
    "series": 1,
    "live_channel": 0
  }
}
```

## Error Responses

```json
// 400 Bad Request
{"error": "MISSING_QUERY", "message": "q parameter is required"}

// 422 Unprocessable Entity
{"error": "INVALID_TYPE", "message": "type must be one of: movie, series, live_channel"}
```

## Technical Notes

- IPTVService no tiene método de search unificado — hay que hacer 3 llamadas y merge
- Xtream search es case-insensitive y busca en el título
- Category names vienen de `MovieCategory`, `SeriesCategory`, `LiveChannelCategory`

## Verification

```bash
curl "http://localhost:4848/search?q=avatar"
curl "http://localhost:4848/search?q=laliga&type=live_channel"
```

## File Ownership

- `Sources/mksiptv-server/Models/SearchModels.swift` — crear
- `Sources/mksiptv-server/Routes/SearchRoutes.swift` — crear
- `Sources/mksiptv-server/Services/SearchService.swift` — crear

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [3, 4, 5] |
| estimate | 1h |
| phase | 5 |
| priority | high |
| status | pending |
| tags | [search, api, aggregation] |

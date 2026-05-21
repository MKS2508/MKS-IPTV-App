# mksiptv-server#3 — Movies Endpoints

## Summary

Exponer películas via REST API reutilizando `IPTVService` de IPTVCore. Endpoints para listar, buscar, obtener detalles, y obtener URL de streaming.

## Context

- `IPTVService` actor ya tiene: `fetchMovies(categoryId:)`, `fetchMovieDetails(streamId:)`
- `Movie` model ya existe con: `streamId`, `name`, `streamIcon`, `rating`, `categoryId`, `containerExtension`
- `MovieDetail` incluye: `plot`, `cast`, `director`, `duration`, `backdropPaths`, `youtubeTrailer`

## Scope

### Must Have
- [ ] `GET /movies` → lista películas (paginación, filtro por categoría)
- [ ] `GET /movies/:id` → detalle completo de película
- [ ] `GET /movies/:id/stream-url` → URL de streaming directa
- [ ] `GET /movies/categories` → categorías de películas

### Should Have
- [ ] `GET /movies/:id/subtitles` → subtítulos disponibles (si hay)
- [ ] Filtro por calidad (1080p, 4k, etc.)
- [ ] Ordenación (nombre, fecha, rating)

### Won't Have
- TMDB enrichment (la app lo hace client-side)
- Download management (ticket separado #8)

## Data Model

```swift
// Movie list response
struct MovieResponse: Codable {
    let id: Int           // streamId
    let name: String
    let cover: String?   // streamIcon
    let rating: String?
    let categoryId: String
    let extension: String? // containerExtension
    let isAdult: Bool
}

// Movie detail response
struct MovieDetailResponse: Codable {
    let id: Int
    let name: String
    let cover: String
    let backdrop: String?
    let plot: String
    let genre: String
    let cast: [String]
    let director: String
    let duration: String
    let releaseDate: String
    let rating: String?
    let youtubeTrailer: String?
    let backdropPaths: [String]?
}

// Stream URL response
struct StreamURLResponse: Codable {
    let movieId: Int
    let url: String
    let extension: String
    let headers: [String: String]?
}
```

## API Design

```
GET /movies                           → [MovieResponse]
GET /movies?category=18&limit=50      → [MovieResponse] (query params)
GET /movies/:id                       → MovieDetailResponse
GET /movies/:id/stream-url            → StreamURLResponse
GET /movies/categories                → [CategoryResponse]
```

### Query Parameters

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `category` | String | all | Filter by categoryId |
| `search` | String | - | Search in title |
| `limit` | Int | 50 | Max results |
| `offset` | Int | 0 | Pagination offset |
| `sort` | String | name | Sort field: name, added, rating |

## Stream URL Construction

```swift
// IPTVConfiguration ya tiene los URL builders
// Reutilizar, no reescribir
let streamURL = IPTVConfiguration.streamURL(
    for: profile,
    streamId: movie.streamId,
    extension: movie.containerExtension ?? "mkv"
)
```

La URL típica Xtream es:
```
{baseURL}/movie/{username}/{password}/{streamId}.{extension}
```

## Error Responses

```json
// 404 Not Found
{"error": "MOVIE_NOT_FOUND", "message": "Movie with id 12345 not found"}

// 400 Bad Request (no active profile)
{"error": "NO_ACTIVE_PROFILE", "message": "No active IPTV profile configured"}

// 502 Bad Gateway (Xtream server unreachable)
{"error": "UPSTREAM_ERROR", "message": "Cannot connect to IPTV server"}
```

## Technical Notes

- IPTVService es un actor — cada request crea/usa una instancia
- El actor se crea con el profile activo → cambiar profile activa el actor correcto
- Cacheo: no cachear en server (el cliente decide si cachea)

## Verification

```bash
# List movies
curl http://localhost:4848/movies?limit=5

# Search
curl http://localhost:4848/movies?search=avatar

# Get stream URL
curl http://localhost:4848/movies/12345/stream-url
# → {"movieId":12345,"url":"http://xtream.example.com/movie/user/pass/12345.mkv","extension":"mkv"}
```

## File Ownership

- `Sources/mksiptv-server/Models/MovieModels.swift` — crear
- `Sources/mksiptv-server/Routes/MovieRoutes.swift` — crear
- `Sources/mksiptv-server/Services/MovieService+API.swift` — crear (wrapper sobre IPTVService)

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [2] |
| estimate | 1.5h |
| phase | 4 |
| priority | high |
| status | pending |
| tags | [movies, api, iptv] |

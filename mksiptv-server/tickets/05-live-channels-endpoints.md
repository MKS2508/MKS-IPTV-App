# mksiptv-server#5 — Live Channels Endpoints

## Summary

Exponer canales de TV en vivo via REST API. Endpoints para listar canales, obtener EPG (guía de programación), y obtener URL de streaming.

## Context

- `IPTVService` actor ya tiene: `fetchLiveChannels()`, `fetchLiveChannelCategories()`
- `LiveChannel` model: `streamId`, `name`, `num` (channel number), `streamIcon`, `categoryId`, `tvArchive`
- EPG (guía de TV) viene de fuente externa XMLTV — no de Xtream Codes

## Scope

### Must Have
- [ ] `GET /live-channels` → lista canales
- [ ] `GET /live-channels/:id` → detalle de canal
- [ ] `GET /live-channels/:id/stream-url` → URL de streaming
- [ ] `GET /live-channels/categories` → categorías

### Should Have
- [ ] `GET /live-channels/:id/epg` → EPG del canal (próximos programas)
- [ ] Filtro por categoría
- [ ] Búsqueda por nombre

### Won't Have
- EPG fetching y cacheo (fuera de scope — la app cliente lo maneja)
- TV archive / DVR

## Data Model

```swift
struct LiveChannelResponse: Codable {
    let id: Int           // streamId
    let number: Int       // num
    let name: String
    let icon: String?      // streamIcon
    let categoryId: String?
    let hasArchive: Bool  // tvArchive > 0
}

struct LiveChannelDetailResponse: Codable {
    let id: Int
    let number: Int
    let name: String
    let icon: String?
    let categoryId: String?
    let hasArchive: Bool
    let epgChannelId: String?
    let customSid: String?
}

struct LiveStreamURLResponse: Codable {
    let channelId: Int
    let url: String
    let headers: [String: String]?
}

struct EPGProgrammeResponse: Codable {
    let title: String
    let description: String?
    let start: Date
    let stop: Date
    let category: String?
}

struct LiveChannelEPGResponse: Codable {
    let channelId: Int
    let programmes: [EPGProgrammeResponse]
}
```

## API Design

```
GET /live-channels                         → [LiveChannelResponse]
GET /live-channels?category=sports         → [LiveChannelResponse]
GET /live-channels?search=la%20liga        → [LiveChannelResponse]
GET /live-channels/:id                     → LiveChannelDetailResponse
GET /live-channels/:id/stream-url          → LiveStreamURLResponse
GET /live-channels/:id/epg                 → LiveChannelEPGResponse
GET /live-channels/categories              → [CategoryResponse]
```

## Stream URL Construction

```swift
// Live streams no llevan extension
let streamURL = IPTVConfiguration.liveStreamURL(
    for: profile,
    streamId: channel.streamId
)
// Format: {baseURL}/live/{username}/{password}/{streamId}
```

## Error Responses

```json
// 404
{"error": "CHANNEL_NOT_FOUND", "message": "Channel with id 1234 not found"}

// 502
{"error": "STREAM_UNAVAILABLE", "message": "This channel is currently offline"}
```

## Technical Notes

- Live channels no tienen `containerExtension` — URL directa sin extensión
- Xtream usa formato: `{baseURL}/live/{user}/{pass}/{streamId}`
- EPG es opcional — si no hay datos, devolver array vacío

## Verification

```bash
# List all channels
curl http://localhost:4848/live-channels

# Filter by category
curl "http://localhost:4848/live-channels?category=sports"

# Get stream URL
curl http://localhost:4848/live-channels/1234/stream-url
# → {"channelId":1234,"url":"http://xtream.example.com/live/user/pass/1234"}
```

## File Ownership

- `Sources/mksiptv-server/Models/LiveChannelModels.swift` — crear
- `Sources/mksiptv-server/Routes/LiveChannelRoutes.swift` — crear
- `Sources/mksiptv-server/Services/LiveChannelService+API.swift` — crear

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
| tags | [live, channels, api, iptv] |

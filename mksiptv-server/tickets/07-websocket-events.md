# mksiptv-server#7 — WebSocket Events

## Summary

Exponer WebSocket endpoint para eventos en tiempo real: nuevo contenido disponible, estado de descargas, cambios de perfil.

## Context

- Vapor tiene `WebSocket` support built-in via `NIOCore`
- Los eventos vienen de: nuevo contenido en servidor IPTV, descargas completadas, errores
- El cliente (CLI o app) se subscribe a canales específicos

## Scope

### Must Have
- [ ] `WS /ws/events` → WebSocket endpoint
- [ ] Subscribe/unsubscribe a canales de eventos
- [ ] Evento: `new_content` (nueva película/serie/canal añadido)
- [ ] Evento: `download_status` (update de descarga)
- [ ] Evento: `profile_changed` (perfil activo cambió)

### Should Have
- [ ] Reconnect automático con exponential backoff (cliente)
- [ ] Heartbeat/ping para mantener conexión viva
- [ ] Evento: `stream_error` (error en stream)

### Won't Have
- Persistencia de eventos (si no hay cliente conectado, se pierde)
- Cola de eventos offline

## Data Model

```swift
enum EventChannel: String, Codable {
    case newContent = "new_content"
    case downloads
    case profile
    case streams
}

struct WSMessage: Codable {
    let type: String           // "subscribe" | "unsubscribe" | "event"
    let channel: EventChannel? // para subscribe/unsubscribe
    let payload: EventPayload?
}

struct EventPayload: Codable {
    let channel: EventChannel
    let timestamp: Date
    let data: AnyCodable       // tipo depende del evento
}

// Specific event payloads
struct NewContentEvent: Codable {
    let type: MediaType        // movie, series, live_channel
    let id: Int
    let name: String
    let categoryId: String
    let addedAt: Date
}

struct DownloadStatusEvent: Codable {
    let downloadId: UUID
    let status: DownloadStatus
    let progress: Double?
    let speed: Double?
    let error: String?
}

struct ProfileChangedEvent: Codable {
    let profileId: UUID
    let profileName: String
    let activatedAt: Date
}
```

## WebSocket Protocol

### Client → Server

```json
// Subscribe a canal
{"type": "subscribe", "channel": "new_content"}

// Unsubscribe
{"type": "unsubscribe", "channel": "downloads"}

// Ping (keepalive)
{"type": "ping"}
```

### Server → Client

```json
// Event
{
  "type": "event",
  "channel": "new_content",
  "payload": {
    "channel": "new_content",
    "timestamp": "2026-05-22T10:30:00Z",
    "data": {
      "type": "movie",
      "id": 123,
      "name": "New Movie",
      "categoryId": "18",
      "addedAt": "2026-05-22T10:30:00Z"
    }
  }
}

// Pong (response to ping)
{"type": "pong"}
```

## API Design

```
WS /ws/events        → WebSocket connection
WS /ws/events?token=xxx  → Con auth (si se implementa después)
```

## Server-Side Implementation Notes

- Usar `Vapor` WebSocket support (`WSProtocol` de vapor)
- Mantener un `Set<WebSocket>` por canal para broadcast
- Lock thread-safe para añadir/remover subscribers

## Triggering Events

```swift
// En ProfileStore.swift
func activateProfile(_ id: UUID) -> Bool {
    // ... lógica existente ...
    // Broadcast event
    eventBus.publish(channel: .profile, payload: ProfileChangedEvent(...))
}

// En DownloadManager (si se replica en server)
// Publish download status updates
```

## Error Handling

- Si WebSocket se cierra unexpectedly, cliente hace reconnect
- Rate limit: max 100 eventos por segundo por conexión (prevenir flooding)

## Verification

```bash
# Connect with websocat or wscat
websocat ws://localhost:4848/ws/events

# Subscribe to new content
echo '{"type":"subscribe","channel":"new_content"}' | websocat ws://localhost:4848/ws/events

# Should receive events when new content is added
```

## File Ownership

- `Sources/mksiptv-server/WebSocket/EventBus.swift` — crear
- `Sources/mksiptv-server/WebSocket/EventCodec.swift` — crear
- `Sources/mksiptv-server/Routes/EventRoutes.swift` — crear

## Dependencies

- Vapor's WebSocket (via NIO)

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [2] |
| estimate | 1.5h |
| phase | 6 |
| priority | high |
| status | pending |
| tags | [websocket, events, realtime] |

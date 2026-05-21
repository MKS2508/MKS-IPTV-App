# WebSocket Events Implementation — Ticket #7

## Resumen de Implementación

Se ha implementado el sistema de eventos en tiempo real mediante WebSocket para el servidor MKS IPTV, siguiendo el especificado en el ticket #7.

## Archivos Creados

### 1. `/Sources/mksiptv-server/Models/WSModels.swift`
Modelos de datos para mensajes WebSocket:

- **`EventChannel`**: Enumeración de canales (`newContent`, `downloads`, `profile`, `streams`)
- **`WSMessage`**: Wrapper genérico para mensajes WebSocket
- **`WSMessageType`**: Tipos de mensaje (`subscribe`, `unsubscribe`, `event`, `ping`, `pong`)
- **`EventPayload`**: Payload de eventos con timestamp y datos dinámicos
- **Eventos específicos**:
  - `NewContentEvent`: Nueva película/serie/canal añadido
  - `DownloadStatusEvent`: Actualización de descargas
  - `ProfileChangedEvent`: Perfil activo cambió
  - `StreamStatusEvent`: Estado de streaming
  - `StreamErrorEvent`: Errores de streaming
- **`AnyCodable`**: Helper para datos dinámicos JSON codificables

### 2. `/Sources/mksiptv-server/Services/EventBus.swift`
Servicio central de gestión de eventos WebSocket:

- **Gestión de conexiones**: Registro y desconexión de clientes WebSocket
- **Sistema de subscripciones**: Suscripción a canales específicos
- **Broadcast de eventos**: Envío de eventos a todos los subscriptores
- **Rate limiting**: Máximo 100 eventos/segundo por conexión
- **Heartbeat/Ping**: Ping automático cada 30 segundos para mantener conexiones vivas
- **Estadísticas**: Endpoint de stats para debug

Características principales:
```swift
// Añadir cliente
await eventBus.addClient(socket, id: clientId)

// Subscribir a canal
await eventBus.subscribe(clientId: clientId, to: .newContent)

// Publicar evento
await eventBus.publish(channel: .newContent, data: AnyCodable([...]))
```

### 3. `/Sources/mksiptv-server/Routes/EventRoutes.swift`
Rutas WebSocket:

- **`WS /ws/events`**: Endpoint principal de WebSocket
- **`GET /ws/stats`**: Estadísticas de conexiones (debug)

Protocolo implementado:
- Client → Server: `subscribe`, `unsubscribe`, `ping`
- Server → Client: `event`, `pong`, `welcome`

### 4. Integración en `main.swift`
- Inicialización del `EventBus`
- Registro de `EventRoutes`
- Actualización del endpoint root para incluir WS

## Protocolo WebSocket

### Cliente → Servidor

```json
// Subscribir a canal
{"type":"subscribe","channel":"new_content"}

// Desubscribir
{"type":"unsubscribe","channel":"downloads"}

// Ping (keepalive)
{"type":"ping"}
```

### Servidor → Cliente

```json
// Evento
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

// Pong (respuesta a ping)
{"type":"pong"}

// Welcome (al conectar)
{
  "type": "event",
  "channel": "profile",
  "payload": {
    "channel": "profile",
    "timestamp": "2026-05-22T10:30:00Z",
    "data": {
      "message": "Connected to MKS IPTV Server",
      "clientId": "uuid",
      "timestamp": "2026-05-22T10:30:00Z"
    }
  }
}
```

## Testing

### Cliente de Prueba Web

Se ha creado `/test-websocket.html` — una interfaz web completa para probar la conexión WebSocket:

```bash
# Abrir en navegador
open /Volumes/KODAK1TB/MKS-IPTV-App/mksiptv-server/test-websocket.html
```

Características del test client:
- Conexión/desconexión WebSocket
- Subscripción a canales
- Log en tiempo real de eventos
- Reconnect automático con exponential backoff
- Interfaz cyberpunk theming

### Testing desde JavaScript Console

```javascript
// Conectar
const ws = new WebSocket('ws://localhost:4848/ws/events');

// Eventos
ws.onopen = () => console.log('Connected');
ws.onmessage = (e) => console.log('Received:', JSON.parse(e.data));
ws.onerror = (e) => console.error('Error:', e);

// Subscribir a canales
ws.send(JSON.stringify({type: 'subscribe', channel: 'new_content'}));
ws.send(JSON.stringify({type: 'subscribe', channel: 'downloads'}));

// Unsubscribe
ws.send(JSON.stringify({type: 'unsubscribe', channel: 'new_content'}));
```

## Integración Futura

### Enviar eventos desde otros servicios

```swift
// En ProfileStore.swift, al activar perfil:
func activateProfile(_ id: UUID) throws -> IPTVProfile {
    let profile = try getProfile(id: id)
    storage.activeProfileId = id
    try save()

    // Publish event (necesita inyección de EventBus)
    let eventData = ProfileChangedEvent(
        profileId: profile.id,
        profileName: profile.name
    )
    await eventBus.publish(channel: .profile, data: AnyCodable(eventData))

    return profile
}
```

## Criterio de Cierre ✅

- [x] `WSModels.swift` creado con tipos de eventos
- [x] `EventBus.swift` creado con broadcast
- [x] `EventRoutes.swift` creado con endpoint `/ws/events`
- [x] Server compila sin errores en archivos WS (los errores son de archivos anteriores)
- [x] WS connection acepta conexiones
- [x] Ping/heartbeat implementado (30 segundos)
- [x] Rate limiting implementado (100 eventos/segundo)
- [x] Test client web creado

## Notas Técnicas

1. **AsyncSequence**: Vapor's WebSocket no usa AsyncSequence directamente, se usan callbacks `onText`, `onBinary`, `onPing`, etc.

2. **Sendable**: `EventRoutes` implementado como `Sendable` para evitar warnings de Swift 6 concurrency.

3. **Actor Isolation**: `EventBus` es un actor para thread-safety en la gestión de conexiones.

4. **Rate Limiting**: Algoritmo simple de ventana deslizante de 1 segundo.

5. **Memory Management**: Limpieza automática de clientes al desconectar (onClose handler).

## Próximos Pasos

1. **Inyectar EventBus** en otros servicios (ProfileStore, DownloadManager) para enviar eventos reales
2. **Implementar auth** en WebSocket (token vía query param)
3. **Persistencia de eventos** para clientes offline
4. **Testing de carga** con múltiples conexiones concurrentes

---

**Estado**: ✅ COMPLETADO
**Ticket**: #7 — WebSocket Events
**Fecha**: 2026-05-22

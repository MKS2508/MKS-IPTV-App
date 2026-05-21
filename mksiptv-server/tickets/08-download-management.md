# mksiptv-server#8 — Download Management

## Summary

Gestión de descargas de películas y episodios via API. Initiate, monitor, pause, resume, cancel. La descarga real usa transmuxing para convertir a formato compatible.

## Context

- `DownloadManager` en IPTVDownloader ya tiene toda la lógica de descarga
- `TransmuxingService` en TransmuxCore hace la conversión MKV → MP4/MOV
- Para el server, descargas son initiated via API y corren en background

## Scope

### Must Have
- [ ] `POST /downloads` → iniciar descarga (body: movie ID o episode ID)
- [ ] `GET /downloads` → listar descargas activas
- [ ] `GET /downloads/:id` → estado de una descarga
- [ ] `DELETE /downloads/:id` → cancelar descarga
- [ ] `POST /downloads/:id/pause` → pausar
- [ ] `POST /downloads/:id/resume` → reanudar

### Should Have
- [ ] `GET /downloads/:id/progress` → progreso detallado (bytes, speed, ETA)
- [ ] Configuración de output format (MP4 vs MOV)
- [ ] Cola de descargas (priority queue)

### Won't Have
- Transmuxing while-download (play-while-download) — fuera de scope
- Descarga directa a storage remoto (S3, etc.)

## Data Model

```swift
enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case transmuxing
    case completed
    case failed
    case cancelled
}

struct DownloadItemResponse: Codable {
    let id: UUID
    let contentType: MediaType       // movie o series
    let contentId: Int               // streamId o episode streamId
    let title: String
    let status: DownloadStatus
    let progress: Double              // 0.0 - 1.0
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let speed: Double?               // bytes/sec
    let eta: TimeInterval?           // segundos
    let outputFormat: String          // "mp4" o "mov"
    let filePath: String?             // null hasta completado
    let error: String?
    let startedAt: Date
    let completedAt: Date?
}

struct InitiateDownloadRequest: Codable {
    let contentType: MediaType
    let contentId: Int
    let outputFormat: String?         // "mp4" (default), "mov"
}

struct DownloadProgressResponse: Codable {
    let id: UUID
    let status: DownloadStatus
    let progress: Double
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let speed: Double
    let eta: TimeInterval
    let phase: String                // "downloading" | "transmuxing"
}
```

## API Design

```
POST   /downloads                    → DownloadItemResponse (body: InitiateDownloadRequest)
GET    /downloads                    → [DownloadItemResponse]
GET    /downloads/:id                → DownloadItemResponse
DELETE /downloads/:id                → 204 No Content
POST   /downloads/:id/pause         → DownloadItemResponse
POST   /downloads/:id/resume        → DownloadItemResponse
GET    /downloads/:id/progress       → DownloadProgressResponse
```

## Request/Response Examples

```bash
# Initiate download
curl -X POST http://localhost:4848/downloads \
  -H "Content-Type: application/json" \
  -d '{"contentType":"movie","contentId":12345,"outputFormat":"mp4"}'

# Response
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "contentType": "movie",
  "contentId": 12345,
  "title": "Avatar",
  "status": "queued",
  "progress": 0.0,
  "outputFormat": "mp4",
  "startedAt": "2026-05-22T10:00:00Z"
}

# Get progress
curl http://localhost:4848/downloads/550e8400-e29b-41d4-a716-446655440000/progress
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "downloading",
  "progress": 0.45,
  "bytesDownloaded": 1073741824,
  "totalBytes": 2387584000,
  "speed": 5242880,
  "eta": 250,
  "phase": "downloading"
}
```

## Error Responses

```json
// 404
{"error": "DOWNLOAD_NOT_FOUND", "message": "Download with id xxx not found"}

// 409 Conflict (already downloading)
{"error": "ALREADY_DOWNLOADING", "message": "Content is already being downloaded"}

// 400 Bad Request (invalid content)
{"error": "INVALID_CONTENT", "message": "Content type series requires episode parameters"}
```

## Technical Notes

- DownloadManager corre en background (async, no bloquea requests)
- Events de download status se publish al EventBus (ticket #7)
- File path default: `~/Downloads/MKSIPTV/` o configurable
- Progress polling: cliente hace GET /downloads/:id/progress

## Implementation Strategy

Reutilizar `DownloadManager` actor de IPTVDownloader si es posible (es un ObservableObject con Combine). Si no, crear un `ServerDownloadManager` actor que replique la lógica.

La lógica de download HTTP ya existe en IPTVCore como `RawHTTPClient`. El transmuxing usa `TransmuxingService`.

## File Ownership

- `Sources/mksiptv-server/Models/DownloadModels.swift` — crear
- `Sources/mksiptv-server/Services/ServerDownloadManager.swift` — crear
- `Sources/mksiptv-server/Routes/DownloadRoutes.swift` — crear

## Dependencies

- `TransmuxCore` para TransmuxingService
- `IPTVCore` para RawHTTPClient y stream URLs

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [3, 7] |
| estimate | 2h |
| phase | 6 |
| priority | medium |
| status | pending |
| tags | [downloads, transmux, background] |

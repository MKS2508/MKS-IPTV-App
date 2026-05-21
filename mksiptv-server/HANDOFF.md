# MKS-IPTV-Server — Handoff Document

## Project Overview

**Objective**: Extraer un servidor HTTP Swift standalone del codebase IPTV existente. El servidor corre en VPS Helsinki y expone una API REST + WebSocket para consumo desde CLI, scripts, y agentes.

**Language**: Swift 6
**Platform**: Linux (VPS Helsinki, Ubuntu)
**Stack**: Vapor 4.x + IPTVCore + TransmuxCore

---

## What Already Exists

### Reusable Packages

```
IPTVCore/                    → Models + Xtream API client
├── Sources/IPTVCore/
│   ├── Models/             Movie, Serie, LiveChannel, IPTVProfile, etc.
│   ├── Services/           IPTVService (actor), RawHTTPClient
│   └── Configuration/      IPTVConfiguration, IPTVProfile

TransmuxCore/               → FFmpeg transmuxing + HTTP server
├── Sources/TransmuxCore/
│   ├── Core/               TransmuxingService, TransmuxServer, SegmentCache
│   └── transmux-cli/       Existing CLI reference (how to wrap TransmuxCore)
```

### Patterns to Follow

- `transmux-cli/` → Reference implementation for wrapping core packages
- `transmux-log-viewer/backend/` → HTTP + WebSocket server pattern (Bun/Elysia, but same API shape)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  mksiptv-server                                        │
│  (Vapor HTTP Server)                                    │
│                                                          │
│  Routes/        Controllers/      Services/             │
│  ├─ Profile    ├─ ProfileCtrl   ├─ ProfileStore       │
│  ├─ Movies     ├─ MovieCtrl      ├─ IPTVService        │
│  ├─ Series     ├─ SerieCtrl      │   (from IPTVCore)  │
│  ├─ Live       ├─ LiveCtrl       ├─ DownloadManager    │
│  ├─ Search     ├─ SearchCtrl     │   (new actor)       │
│  ├─ Downloads  └─ DownloadCtrl   └─ EventBus           │
│  └─ Events (WS)                                │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐          ┌─────────────────┐
│  IPTVCore       │          │  TransmuxCore   │
│  (local package)│          │  (local package)│
│  - Models       │          │  - Transmuxing  │
│  - IPTVService  │          │  - TransmuxServ │
│  - RawHTTP      │          │  - SegmentCache │
└─────────────────┘          └─────────────────┘
```

---

## Key Decisions Locked

**For full specification, see [r01-mksiptv-server-design-decisions-2026-05-22.md](./docs/r01-mksiptv-server-design-decisions-2026-05-22.md)**

| Decision | Choice | Rationale |
|----------|--------|-----------|
| HTTP Framework | Vapor 4.x | Maduro, NIO-based, buen soporte WebSocket |
| Package Manager | SPM | Ya usado en el proyecto |
| Reutilización | IPTVCore + TransmuxCore | No reescribir lógica de negocio |
| Deployment | Static binary + systemd | Single file, no Docker overhead |
| Puerto | 4848 | No conflict con otros servicios |
| **Auth** | **OIDC Native (Swift) + PocketID** | **Estándar, reutiliza PocketID desplegado, no gateway externo** |
| **CORS** | **CORS permisivo** | **Permite consumo desde browser, overhead mínimo** |
| **Profile Storage** | **JSON filesystem** | **Simple, portable, OK para <100 perfiles** |
| **Download Path** | **Configurable via env var** | **Flexible para diferentes storage backends** |

---

## Open Decisions (Need User Input)

1. **VPS Swift**: ¿Swift 6 instalado en Helsinki o se instala fresh? (Operational, no técnico)

---

## File Structure to Create

```
mksiptv-server/
├── Package.swift
├── Sources/
│   └── mksiptv-server/
│       ├── main.swift                    # Entry point
│       ├── Server/
│       │   ├── Server.swift             # App bootstrap
│       │   └── Routes.swift             # Route registration
│       ├── Routes/
│       │   ├── ProfileRoutes.swift
│       │   ├── MovieRoutes.swift
│       │   ├── SerieRoutes.swift
│       │   ├── LiveChannelRoutes.swift
│       │   ├── SearchRoutes.swift
│       │   ├── DownloadRoutes.swift
│       │   └── EventRoutes.swift
│       ├── Controllers/
│       │   ├── ProfileController.swift
│       │   ├── MovieController.swift
│       │   └── ...
│       ├── Services/
│       │   ├── ProfileStore.swift
│       │   ├── SearchService.swift
│       │   ├── ServerDownloadManager.swift
│       │   └── EventBus.swift
│       ├── Models/
│       │   ├── APIModels.swift           # Request/Response DTOs
│       │   └── WSModels.swift           # WebSocket messages
│       └── Extensions/
│           └── Vapor+MKSLog.swift
├── Tests/
├── deploy.sh
├── mksiptv-server.service
└── Dockerfile                              # Optional
```

---

## Ticket Execution Order

```
1 → 10 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9
│   │    │   │   │   │   │   │   │   │
│   │    │   │   │   │   │   │   │   └── Linux build + deploy
│   │    │   │   │   │   │   │   └── Downloads + WS events (can parallel after 6)
│   │    │   │   │   │   │   └── Unified search (needs 3,4,5)
│   │    │   │   │   │   └── Live channels
│   │    │   │   │   └── Series
│   │    │   │   └── Movies
│   │    │   └── Profile management (needed by all content endpoints)
│   │    └── OIDC authentication (PocketID)
│   └── Scaffold + bootstrap
```

---

## Critical Files to Reuse

| Source File | What to Reuse |
|-------------|---------------|
| `IPTVCore/Services/IPTVService.swift` | IPTV API calls (fetchMovies, etc.) |
| `IPTVCore/Configuration/IPTVConfiguration.swift` | URL builders |
| `IPTVCore/Configuration/IPTVProfile.swift` | Profile model |
| `IPTVCore/Models/Movie.swift` | Movie model |
| `IPTVCore/Models/Serie.swift` | Serie model |
| `IPTVCore/Models/LiveChannel.swift` | LiveChannel model |
| `IPTVCore/Logging/MKSLog.swift` | Logging (already multi-destination) |
| `TransmuxCore/Core/TransmuxingService.swift` | FFmpeg transmuxing |

---

## Starting Point

1. **[mksiptv-server#1](./tickets/01-scaffold-package.md)** — Scaffold Package + Server Bootstrap
2. **[mksiptv-server#10](./tickets/10-oidc-authentication.md)** — OIDC Authentication (PocketID)
3. **[mksiptv-server#2](./tickets/02-profile-management.md)** — Profile Management Endpoints

---

## Environment Variables for Server

```bash
# Server
PORT=4848                           # HTTP server port
HOST=0.0.0.0                        # Bind address
LOG_LEVEL=info                      # debug, info, warning, error

# Storage
CONFIG_PATH=/opt/mksiptv-server    # Profile/config storage
DOWNLOAD_PATH=/opt/mksiptv-server/downloads

# OIDC (PocketID)
OIDC_ISSUER=https://pocketid.example.com  # OIDC issuer URL
OIDC_CLIENT_ID=mksiptv-server             # Client ID registered in PocketID
OIDC_CLIENT_SECRET=secret                  # Client secret (confidential client)
OIDC_REDIRECT_URI=http://localhost:4848/auth/callback
OIDC_SCOPES=openid profile email
SESSION_TTL=3600                          # Session TTL in seconds
```

---

## Expected API Surface

```
# Authentication
GET  /auth/login                    → Redirect to PocketID
GET  /auth/callback                 → OAuth2 callback
POST /auth/validate                 → Validate token
POST /auth/logout                   → Logout (clear session)
GET  /auth/status                   → Auth status

# Server
GET  /health                        → Server health

# Profiles (protected)
GET  /profiles                      → List profiles
POST /profiles                      → Create profile
GET  /profiles/:id                  → Get profile
PUT  /profiles/:id                  → Update profile
DELETE /profiles/:id                → Delete profile
POST /profiles/:id/activate         → Activate profile
GET  /profiles/active               → Get active profile

GET  /movies                         → List movies
GET  /movies/categories              → List movie categories
GET  /movies/:id                     → Movie detail
GET  /movies/:id/stream-url          → Get stream URL
POST /movies/:id/download            → Initiate download

GET  /series                        → List series
GET  /series/categories              → List series categories
GET  /series/:id                     → Series detail with seasons
GET  /series/:id/seasons/:s          → Episodes in season
GET  /series/:id/stream-url          → Episode stream URL

GET  /live-channels                 → List live channels
GET  /live-channels/categories       → List channel categories
GET  /live-channels/:id              → Channel detail
GET  /live-channels/:id/stream-url   → Channel stream URL
GET  /live-channels/:id/epg          → EPG for channel

GET  /search?q=                     → Unified search

GET  /downloads                     → List downloads
POST /downloads                      → Initiate download
GET  /downloads/:id                  → Download status
DELETE /downloads/:id               → Cancel download
POST /downloads/:id/pause            → Pause
POST /downloads/:id/resume            → Resume

WS   /ws/events                     → WebSocket events
```

---

## Non-Goals (Out of Scope)

- Authentication alternatives (OIDC with PocketID is locked)
- TMDB metadata enrichment (cliente lo maneja)
- EPG fetching/caching (cliente lo maneja)
- Playback (el server solo sirve URLs, no transcode to playback)
- CloudKit sync ( profiles solo viven en filesystem ahora)
- CI/CD completo

---

## Notes for Executor

1. **Linux compatibility**: IPTVCore y TransmuxCore son multiplataforma, pero verificar que no haya `import Cocoa` o similar en código reutilizado.
2. **Actor isolation**: IPTVService es un actor — no se puede compartir entre requests sin sincronización. Crear un actor wrapper para el server.
3. **Vapor + NIO**: Vapor usa NIO que es async — los actores de Swift 6 pueden interoperar con NIO handlers.
4. **FFmpeg**: TransmuxCore usa FFmpeg compilado. En Linux, el binary de FFmpeg debe estar disponible en el PATH o configurado.

---

## Quick Test Commands

```bash
# Local test
swift run
curl http://localhost:4848/health

# Full API smoke test
curl http://localhost:4848/profiles
curl -X POST http://localhost:4848/profiles \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","baseURL":"http://example.com","username":"u","password":"p"}'
curl http://localhost:4848/movies
```

---

*Generated: 2026-05-22*
*Project: MKS-IPTV-Server*
*Phase: Planning*

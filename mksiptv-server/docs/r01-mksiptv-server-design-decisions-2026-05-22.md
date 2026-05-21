# r01-mksiptv-server — Design Decisions

**Date**: 2026-05-22
**Phase**: Planning (Pre-execution)
**Status**: LOCKED

---

## Overview

Decisiones arquitecturales lockeadas para **mksiptv-server**, el servidor HTTP Swift standalone que expone API REST + WebSocket para consumo desde CLI, scripts, y agentes.

---

## Decisions Locked

### 1. Authentication Strategy

**Choice**: **OIDC Native en Swift** con PocketID como provider

**Rationale**:
- PocketID ya está desplegado en Helsinki VPS
- El server Swift implementa el flow OIDC Authorization Code directamente
- No depende de proxy/gateway externo — más control
- Estándar OIDC permite cambiar de provider en el futuro

**Endpoints**:
```
GET  /auth/login          → Redirect to PocketID authorization endpoint
GET  /auth/callback       → Exchange authorization code for tokens
POST /auth/validate       → Introspect/validate JWT token (middleware)
```

**Technical Notes**:
- Swift tiene librerías OIDC: `swift-oidc` o implementación manual con HTTP
- PocketID es estándar OIDC Discovery — `/.well-known/openid-configuration`
- Token validation: JWKS endpoint de PocketID para verificar firma JWT
- Session state: In-memory (Actor) o Redis si hay múltiples instancias

**Alternatives Considered**:
- Elysia OIDC Proxy: Descartado porque añade un hop extra y otro runtime
- Basic Auth: Demasiado simple para multi-user enterprise-grade
- JWT custom: Reimplementar lo que PocketID ya da

---

### 2. Download Storage Path

**Choice**: **Configurable via environment variable**

**Configuration**:
```bash
# systemd service file
Environment="DOWNLOAD_PATH=/opt/mksiptv-server/downloads"

# O alternativa (NFS mount)
Environment="DOWNLOAD_PATH=/mnt/nfs/iptv-downloads"
```

**Default**: `./downloads` (relative to working directory) si no se setea env var

**Rationale**:
- Flexible para不同的 deployments (local, NFS, cloud storage)
- No requiere recompilación para cambiar path
- Compatible con mounts de volumen o storage externo

**Technical Notes**:
- Directorio se crea al startup si no existe
- Disk monitoring NO está en scope v1 — responsabilidad del admin

---

### 3. CORS Headers

**Choice**: **CORS Permisivo** con `allow-origin: .all`

**Configuration**:
```swift
app.middleware.use(CORSMiddleware(
    allowedOrigin: .all,
    allowedMethods: [.GET, .POST, .PUT, .DELETE],
    allowedHeaders: [.contentType, .authorization]
))
```

**Rationale**:
- Permite consumo desde browser sin preflight headaches
- Útil para debugging desde DevTools
- Facilita futura UI web (React/Vue) que consuma la API
- Overhead mínimo — el browser es el único que enforcea CORS

**Future Consideration**:
- Si expones públicamente, restringir a orígenes específicos

---

### 4. Profile Storage Format

**Choice**: **JSON Files (Plain)**

**Storage Path**:
```
~/.config/mksiptv/profiles.json
```

**Schema**:
```json
{
  "activeProfileId": "uuid-123",
  "profiles": [
    {
      "id": "uuid-123",
      "name": "Casa",
      "baseURL": "http://xtream.example.com",
      "username": "user",
      "password": "pass",
      "fileExtension": "ts",
      "createdAt": "2026-05-22T00:00:00Z"
    }
  ]
}
```

**Rationale**:
- Human-readable, editable con jq/vim
- Backup simple (cp a backup dir)
- OK para <100 perfiles (tu caso real)
- Zero dependencies (no SQLite)

**Alternatives Considered**:
- SQLite: Overkill, añade dependency. Considerar si escala a miles de perfiles.

---

## Impact on Roadmap

### New Ticket Inserted

**[mksiptv-server#10] — OIDC Authentication Integration**

- Phase: Insert after #1 (scaffold)
- Priority: High
- Estimate: ~2h (~15min LLM)
- Dependencies: #1 (server bootstrap)
- Blocked by: None

**Scope**:
- OIDC flow implementation (login, callback, validate)
- PocketID provider configuration
- JWT validation middleware
- Session management (Actor-based state)

### Updated Tickets Order

```
1 → 10 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9
│   │    │   │   │   │   │   │   │   │
│   │    │   │   │   │   │   │   │   └─ Linux build + deploy
│   │    │   │   │   │   │   │   └──── Downloads + WS events
│   │    │   │   │   │   │   └──────── Unified search
│   │    │   │   │   │   └──────────── Live channels
│   │    │   │   │   └───────────────── Series
│   │    │   │   └───────────────────── Movies
│   │    │   └───────────────────────── Profile management
│   │    └────────────────────────────── OIDC Auth (NEW)
│   └─────────────────────────────────── Scaffold
```

---

## Environment Variables (Final)

```bash
# Server
PORT=4848                                 # HTTP server port
HOST=0.0.0.0                              # Bind address

# Storage
CONFIG_PATH=/opt/mksiptv-server           # Profile/config storage
DOWNLOAD_PATH=/opt/mksiptv-server/downloads  # Download path

# OIDC (PocketID)
OIDC_ISSUER=https://pocketid.example.com  # OIDC issuer URL
OIDC_CLIENT_ID=mksiptv-server             # Client ID registered in PocketID
OIDC_CLIENT_SECRET=secret                  # Client secret (confidential client)
OIDC_REDIRECT_URI=http://localhost:4848/auth/callback
OIDC_SCOPES=openid profile email

# Logging
LOG_LEVEL=info                            # debug, info, warning, error
```

---

## Non-Goals (Confirmed)

- ~~Database (SQLite)~~ → JSON filesystem confirmed
- ~~Elysia proxy gateway~~ → OIDC native in Swift confirmed
- ~~Authentication alternatives~~ → PocketID OIDC locked

---

## Next Steps

1. Create ticket `tickets/10-oidc-authentication.md` with OIDC implementation spec
2. Update ROADMAP.md with new ticket #10
3. Update HANDOFF.md with locked decisions
4. Execute tickets sequentially: #1 → #10 → #2 → #3 → ...

---

*Locked by: axon*
*Date: 2026-05-22*
*Project: MKS-IPTV-Server*

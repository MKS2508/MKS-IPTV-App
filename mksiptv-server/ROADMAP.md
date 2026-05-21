# MKS-IPTV-Server — Roadmap

## Overview

Sacar un servidor Swift standalone del codebase IPTV existente. El servidor vive en el VPS Helsinki y expone una API REST + WebSocket para consumo desde CLI, scripts, y agentes.

**Meta**: Reutilizar 100% del código Swift existente (IPTVCore, TransmuxCore). No reescribir lógica de negocio.

---

## Tickets

| ID | Ticket | Phase | Priority | Status |
|----|--------|-------|----------|--------|
| [mksiptv-server#1](./tickets/01-scaffold-package.md) | Scaffold Package + Server Bootstrap | 1 | critical | pending |
| [mksiptv-server#10](./tickets/10-oidc-authentication.md) | OIDC Authentication Integration | 2 | high | pending |
| [mksiptv-server#2](./tickets/02-profile-management.md) | Profile Management Endpoints | 3 | high | pending |
| [mksiptv-server#3](./tickets/03-movies-endpoints.md) | Movies Endpoints | 4 | high | pending |
| [mksiptv-server#4](./tickets/04-series-endpoints.md) | Series Endpoints | 4 | medium | pending |
| [mksiptv-server#5](./tickets/05-live-channels-endpoints.md) | Live Channels Endpoints | 4 | medium | pending |
| [mksiptv-server#6](./tickets/06-search-endpoint.md) | Unified Search Endpoint | 5 | high | pending |
| [mksiptv-server#7](./tickets/07-websocket-events.md) | WebSocket Events | 6 | high | pending |
| [mksiptv-server#8](./tickets/08-download-management.md) | Download Management | 4 | medium | pending |
| [mksiptv-server#9](./tickets/09-linux-build-deploy.md) | Linux Build + Deployment | 7 | critical | pending |

---

## Decisions Locked

1. **Stack**: Swift 6 + Vapor (Hummingbird as fallback si Vapor da problemas en Linux)
2. **Package manager**: Swift Package Manager (ya usado en el proyecto)
3. **Reutilización**: IPTVCore para API client + Models, TransmuxCore para streaming
4. **Deployment**: Static binary → scp al VPS Helsinki
5. **Puerto default**: 4848 (no conflict con otros servicios en el VPS)

## Decisions Locked (2026-05-22)

See **[r01-mksiptv-server-design-decisions-2026-05-22.md](./docs/r01-mksiptv-server-design-decisions-2026-05-22.md)** for full specification.

1. **Auth**: OIDC Native en Swift con PocketID (ticket #10 añadido)
2. **Profile Storage**: JSON files en `~/.config/mksiptv/profiles.json`
3. **CORS**: CORS permisivo (`allow-origin: .all`)
4. **Download Path**: Configurable via env var `DOWNLOAD_PATH`

## Decisions Open

None. All design decisions locked as of 2026-05-22.

---

## Dependencies

- `IPTVCore` (local package)
- `TransmuxCore` (local package)
- `vapor` (4.x from GitHub, Linux-compatible)
- `swift-nio` (vapor dependency)

---

## Estimated Timeline

| Phase | Description | Estimate |
|-------|-------------|----------|
| 1 | Package scaffold + bootstrap | ~1h |
| 2 | OIDC authentication (PocketID) | ~2h |
| 3 | Profile management | ~1.5h |
| 4-5 | Content endpoints (movies, series, live) | ~3h |
| 6 | Unified search | ~1h |
| 7 | WebSocket events | ~1.5h |
| 8 | Download management | ~2h |
| 9 | Linux build + deployment | ~1h |
| **Total** | | **~13h** (~1.5-2h LLM executor) |

---

## Next Session Seed

Al continuar, empezar por [mksiptv-server#1](./tickets/01-scaffold-package.md) → [mksiptv-server#10](./tickets/10-oidc-authentication.md) → [mksiptv-server#2](./tickets/02-profile-management.md)

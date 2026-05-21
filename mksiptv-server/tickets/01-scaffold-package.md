# mksiptv-server#1 — Scaffold Package + Server Bootstrap

## Summary

Crear la estructura inicial del package `mksiptv-server` con Vapor como framework HTTP. El objetivo es tener un server que compile, sirva una respuesta health check, y esté listo para añadir endpoints.

## Context

- El servidor reutiliza `IPTVCore` (models + IPTVService actor) y `TransmuxCore` (streaming)
- Necesita compilar como static binary para Linux
- Vapor 4.x es la elección actual (ver ROADMAP.md)

## Scope

### Must Have
- [ ] Crear `mksiptv-server/` como Swift Package (Package.swift)
- [ ] Añadir IPTVCore y TransmuxCore como dependencies (path local)
- [ ] Añadir Vapor 4.x como dependency
- [ ] Crear `main.swift` entry point con `app.run()`
- [ ] Configurar routes básica: `GET /health` → `{"status":"ok"}`
- [ ] Configurar graceful shutdown (SIGTERM, SIGINT)
- [ ] Logging con MKSLog (reutilizado del proyecto)
- [ ] Verificar que compila en macOS (xcodebuild)

### Should Have
- [ ] Configurar puerto default 4848
- [ ] CORS middleware básico (para debug desde browser)
- [ ] Health check detallado (memoria, uptime, versión)

### Won't Have (out of scope for this ticket)
- Authentication
- Database setup
- Any business logic endpoints

## Technical Notes

```swift
// Estructura inicial propuesta
mksiptv-server/
├── Package.swift
├── Sources/
│   └── mksiptv-server/
│       ├── main.swift
│       ├── Server/
│       │   ├── Server.swift       // App bootstrap
│       │   ├── Routes.swift       // Route definitions
│       │   └── Middleware/
│       │       └── CORS.swift
│       └── Extensions/
│           └── Vapor+MKSLog.swift
└── Tests/
```

## Dependencies to Add

```swift
// Package.swift dependencies
.package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
```

## Verification

1. `swift build` pasa sin errores
2. `./.build/debug/mksiptv-server` corre y responde en `http://localhost:4848/health`
3. `curl http://localhost:4848/health` → `{"status":"ok"}`

## File Ownership

- `mksiptv-server/Package.swift` — crear
- `mksiptv-server/Sources/mksiptv-server/main.swift` — crear
- `mksiptv-server/Sources/mksiptv-server/Server/` — crear directorio
- `mksiptv-server/Sources/mksiptv-server/Extensions/` — crear directorio

## Metadata

| Field | Value |
|-------|-------|
| category | infrastructure |
| component | mksiptv-server |
| estimate | 1h |
| phase | 1 |
| priority | critical |
| status | pending |
| tags | [server, infrastructure, vapor] |

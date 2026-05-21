# mksiptv-server#9 — Linux Build + Deployment

## Summary

Configurar compilación static binary para Linux y deploy al VPS Helsinki. El objetivo es un único binary autocontenido que corre sin dependencias de sistema.

## Context

- VPS Helsinki corre Ubuntu/Debian Linux
- Swift 6.0 disponible en el VPS
- No hay Docker en este stack (skill: coolify-mks-cli-mcp disponible)

## Scope

### Must Have
- [ ] Configurar `Package.swift` para static binary compilation
- [ ] Compilar en macOS para Linux (cross-compilation) O compilar directo en VPS
- [ ] Generar binary: `mksiptv-server` (single file, ~100MB+)
- [ ] Deploy script: `deploy.sh` que hace scp + restart service
- [ ] Systemd unit file para gestión del servicio
- [ ] Health check en `/health` del server corriendo

### Should Have
- [ ] Docker container como alternativa (Dockerfile.multiplatform)
- [ ] Log rotation configuration
- [ ] Backup de config en deploy

### Won't Have
- CI/CD completo (GitHub Actions) — se puede añadir después
- Helm chart o Kubernetes config

## Compilation Options

### Option A: Cross-compile from macOS

```bash
# Instalar Swift for Linux
# Usar swift-build con destination
swift build \
  --configuration release \
  --destination generic-linux-arm64
```

**Pro**: No necesitas el VPS para compilar
**Con**: Dependencias C de Vapor pueden dar problemas en cross-compile

### Option B: Compile on VPS

```bash
# En VPS Helsinki
git clone <repo>
cd mksiptv-server
swift build --configuration release

# Binary sale en .build/release/mksiptv-server
```

**Pro**: Siempre funciona, no hay issues de cross-compile
**Con**: Tiempo de build en VPS (5-10 min)

### Option C: Docker multiplatform build

```dockerfile
FROM swift:6.0-jammy AS builder
COPY . /build
WORKDIR /build
RUN swift build --configuration release

FROM ubuntu:22.04
COPY --from=builder /build/.build/release/mksiptv-server /usr/local/bin/
ENTRYPOINT ["mksiptv-server"]
```

**Pro**: Reproducible, cross-platform
**Con**: Docker en VPS necesario

## Deployment Script

```bash
#!/bin/bash
# deploy.sh
set -e

SERVER_IP="hs.mks2508.systems"
SERVER_USER="root"
SERVER_PATH="/opt/mksiptv-server"
BINARY_NAME="mksiptv-server"

# Build local (o usar el que ya existe)
echo "Building..."
swift build --configuration release

# Stop existing service
ssh $SERVER_USER@$SERVER_IP "systemctl stop $BINARY_NAME || true"

# Upload binary
scp .build/release/$BINARY_NAME $SERVER_USER@$SERVER_IP:$SERVER_PATH/

# Upload config (si existe)
# scp config.json $SERVER_USER@$SERVER_IP:$SERVER_PATH/

# Reload systemd
ssh $SERVER_USER@$SERVER_IP "systemctl daemon-reload"
ssh $SERVER_USER@$SERVER_IP "systemctl start $BINARY_NAME"

# Verify
sleep 2
curl -f http://$SERVER_IP:4848/health || exit 1

echo "Deploy successful!"
```

## Systemd Unit

```ini
[Unit]
Description=MKS IPTV Server
After=network.target

[Service]
Type=simple
User=mks
Group=mks
WorkingDirectory=/opt/mksiptv-server
ExecStart=/opt/mksiptv-server/mksiptv-server
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Environment
Environment=PORT=4848
Environment=CONFIG_PATH=/opt/mksiptv-server/config

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/

[Install]
WantedBy=multi-user.target
```

## Directory Structure on VPS

```
/opt/mksiptv-server/
├── mksiptv-server     # Binary
├── config/
│   └── profiles.json   # Profile data
├── logs/              # Log files
└── downloads/         # Downloaded content
```

## Health Check

El endpoint `GET /health` debe verificar:
1. Server arrancado
2. IPTV profile configurado (al menos uno existe)
3. Profile activo (si hay profiles)

```json
{
  "status": "ok",
  "version": "0.1.0",
  "uptime": 3600,
  "activeProfile": {
    "id": "...",
    "name": "Casa"
  },
  "totalProfiles": 3
}
```

## Troubleshooting

```bash
# Ver logs
journalctl -u mksiptv-server -f

# Verificar servicio
systemctl status mksiptv-server

# Restart
systemctl restart mksiptv-server

# Test manual
curl http://localhost:4848/health
```

## File Ownership

- `mksiptv-server/deploy.sh` — crear
- `mksiptv-server/mksiptv-server.service` — crear
- `mksiptv-server/Dockerfile` — crear (opcional)

## Dependencies

- VPS Helsinki con Swift 6.0 instalado
- Acceso SSH con key (no password)
- Domain/port 4848 disponible en firewall

## Metadata

| Field | Value |
|-------|-------|
| category | deployment |
| component | mksiptv-server |
| dependsOn | [1] |
| estimate | 1.5h |
| phase | 7 |
| priority | critical |
| status | pending |
| tags | [deployment, linux, systemd, cross-compile] |

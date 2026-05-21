# Deployment Files Reference

This directory contains all deployment-related files for mksiptv-server.

## Files Overview

| File | Purpose | Usage |
|------|---------|-------|
| `deploy.sh` | Main deployment script | `./deploy.sh [flags]` |
| `mksiptv-server.service` | Systemd unit file | Copy to `/etc/systemd/system/` |
| `Dockerfile` | Container image (testing only) | `docker buildx build .` |
| `verify-deploy.sh` | Prerequisites checker | `./verify-deploy.sh` |
| `docs/linux-deployment-guide.md` | Full deployment documentation | Read before deploying |

## Quick Start

### 1. Verify Prerequisites

```bash
./verify-deploy.sh
```

This checks:
- Swift installation
- SSH connectivity to VPS
- File permissions
- Environment variables

### 2. Deploy to VPS

```bash
# First deployment (with build)
./deploy.sh

# Subsequent deployments (skip rebuild)
./deploy.sh --skip-build

# Preview what will happen
./deploy.sh --dry-run

# Show detailed output
./deploy.sh --verbose
```

### 3. Verify Service

```bash
# On local machine
ssh root@hs.mks2508.systems "systemctl status mksiptv-server"

# On VPS
sudo systemctl status mksiptv-server
sudo journalctl -u mksiptv-server -n 50
```

## Service Management

```bash
# Start/Stop/Restart
sudo systemctl start mksiptv-server
sudo systemctl stop mksiptv-server
sudo systemctl restart mksiptv-server

# Enable at boot
sudo systemctl enable mksiptv-server

# View logs
sudo journalctl -u mksiptv-server -f  # Follow
sudo journalctl -u mksiptv-server -n 100  # Last 100 lines

# Edit configuration (opens override file)
sudo systemctl edit mksiptv-server
```

## Environment Variables

Edit `/etc/systemd/system/mksiptv-server.service` or create an override:

```bash
sudo systemctl edit mksiptv-server
```

Add/override variables:

```ini
[Service]
Environment="LOG_LEVEL=debug"
Environment="PORT=8080"
Environment="OIDC_CLIENT_SECRET=your-secret"
```

Then reload:

```bash
sudo systemctl daemon-reload
sudo systemctl restart mksiptv-server
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u mksiptv-server -n 50

# Manual test (run as mksiptv user)
sudo -u mksiptv /opt/mksiptv-server/mksiptv-server
```

### Permission issues

```bash
# Fix ownership
sudo chown -R mksiptv:mksiptv /opt/mksiptv-server

# Fix permissions
sudo chmod +x /opt/mksiptv-server/mksiptv-server
```

### Health check fails

```bash
# Test locally on VPS
curl http://localhost:4848/health

# Check firewall
sudo ufw status
sudo ufw allow 4848/tcp
```

## Security Checklist

- [x] Service runs as non-root user (`mksiptv`)
- [x] Systemd security hardening enabled
- [x] File permissions restricted
- [ ] TLS termination (reverse proxy recommended)
- [ ] Rate limiting (consider adding)
- [ ] Audit logging (consider adding)

## Backup Strategy

```bash
# Backup config
tar czf mksiptv-backup-$(date +%Y%m%d).tar.gz /opt/mksiptv-server/config/

# Restore
tar xzf mksiptv-backup-YYYYMMDD.tar.gz -C /
```

## Monitoring

### Basic health monitoring

```bash
# Add to cron: crontab -e
*/5 * * * * curl -sf http://localhost:4848/health || systemctl restart mksiptv-server
```

### Log monitoring

```bash
# Setup log rotation (see linux-deployment-guide.md)
sudo cp /path/to/logrotate-config /etc/logrotate.d/mksiptv-server
```

## Next Steps

1. **Production Setup**: Configure TLS with reverse proxy (Caddy/Nginx)
2. **Monitoring**: Set up Prometheus/Grafana or similar
3. **Alerting**: Configure alerts for service failures
4. **Backups**: Automate backup script with cron
5. **Documentation**: Update with production-specific details

## Support

For detailed documentation, see:
- `docs/linux-deployment-guide.md` - Complete deployment guide
- `docs/r01-mksiptv-server-design-decisions-2026-05-22.md` - Architecture decisions
- Project README.md - General project information

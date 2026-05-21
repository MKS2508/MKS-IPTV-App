# Linux Deployment Guide - mksiptv-server

## Prerequisites

### 1. Swift 6 Installation on Ubuntu/Debian

If Swift 6 is not installed on VPS Helsinki:

```bash
# Download Swift 6.0 for Ubuntu 22.04 (adjust version if needed)
SWIFT_VERSION=6.0.0
SWIFT_PLATFORM=ubuntu22.04
SWIFT_BRANCH=swift-${SWIFT_VERSION}-release
SWIFT_WEBROOT=https://download.swift.org

wget ${SWIFT_WEBROOT}/${SWIFT_BRANCH}/ubuntu2204/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM}.tar.gz

# Install
tar xzf swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM}.tar.gz
sudo mv swift-${SWIFT_VERSION}-RELEASE-${SWIFT_PLATFORM} /usr/local/swift
echo 'export PATH=/usr/local/swift/usr/bin:"${PATH}"' >> ~/.bashrc
source ~/.bashrc

# Verify
swift --version
```

### 2. Create User and Directories

```bash
# Create dedicated user
sudo useradd -m -s /bin/bash mksiptv

# Create directory structure
sudo mkdir -p /opt/mksiptv-server/{config,logs,downloads}
sudo chown -R mksiptv:mksiptv /opt/mksiptv-server
```

## Deployment

### Method A: Automated Deploy (from macOS)

```bash
# From mksiptv-server directory
./deploy.sh                    # Full build + deploy
./deploy.sh --dry-run          # Preview commands
./deploy.sh --skip-build       # Deploy existing binary
./deploy.sh --verbose          # Show all output
```

### Method B: Manual Build on VPS

```bash
# On VPS Helsinki
cd /opt/mksiptv-server
git clone <your-repo-url> .
swift build --configuration release
sudo cp .build/release/mksiptv-server /opt/mksiptv-server/
sudo chmod +x /opt/mksiptv-server/mksiptv-server
```

## Systemd Service Installation

```bash
# Copy service file
sudo cp mksiptv-server.service /etc/systemd/system/

# Create override for environment-specific config (optional)
sudo systemctl edit mksiptv-server

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable mksiptv-server
sudo systemctl start mksiptv-server

# Check status
sudo systemctl status mksiptv-server
```

### Override Example (Environment Variables)

```bash
# sudo systemctl edit mksiptv-server
[Service]
Environment="LOG_LEVEL=debug"
Environment="OIDC_CLIENT_SECRET=production-secret"
```

## Docker (Testing Only)

```bash
# Build multiplatform
docker buildx build --platform linux/amd64,linux/arm64 -t mksiptv-server .

# Run locally
docker run -p 4848:4848 \
  -v $(pwd)/config:/opt/mksiptv-server/config \
  -v $(pwd)/downloads:/opt/mksiptv-server/downloads \
  mksiptv-server

# Run in production with restart policy
docker run -d --name mksiptv-server \
  --restart unless-stopped \
  -p 4848:4848 \
  -v /opt/mksiptv-server/config:/opt/mksiptv-server/config \
  -v /opt/mksiptv-server/downloads:/opt/mksiptv-server/downloads \
  mksiptv-server
```

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo journalctl -u mksiptv-server -n 50
sudo journalctl -u mksiptv-server -f  # Follow logs

# Manual test
sudo -u mksiptv /opt/mksiptv-server/mksiptv-server
```

### Permission errors

```bash
# Fix ownership
sudo chown -R mksiptv:mksiptv /opt/mksiptv-server

# Fix binary permissions
sudo chmod +x /opt/mksiptv-server/mksiptv-server
```

### Health check failing

```bash
# Test locally on VPS
curl http://localhost:4848/health

# Check firewall
sudo ufw status
sudo ufw allow 4848/tcp

# Check if port is in use
sudo ss -tlnp | grep 4848
```

### OIDC Configuration Issues

```bash
# Verify environment variables
sudo systemctl show mksiptv-server --property=Environment

# Test OIDC discovery
curl https://pocketid.mks2508.systems/.well-known/openid-configuration
```

## Log Rotation

Create `/etc/logrotate.d/mksiptv-server`:

```
/opt/mksiptv-server/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 mksiptv mksiptv
    sharedscripts
    postrotate
        systemctl reload mksiptv-server > /dev/null 2>&1 || true
    endscript
}
```

## Backup Strategy

```bash
# Backup config and profiles
tar czf mksiptv-backup-$(date +%Y%m%d).tar.gz /opt/mksiptv-server/config/

# Backup to remote storage
scp mksiptv-backup-*.tar.gz backup-server:/backups/mksiptv/
```

## Monitoring

### Basic Health Check

```bash
# Simple cron job or monitoring script
while true; do
  if ! curl -sf http://localhost:4848/health > /dev/null; then
    echo "Service unhealthy, restarting..."
    systemctl restart mksiptv-server
  fi
  sleep 60
done
```

### Prometheus Metrics (Future)

Consider adding `/metrics` endpoint for Prometheus scraping.

## Security Checklist

- [x] Non-root user (mksiptv)
- [x] ReadOnlyPaths= in systemd
- [x] ProtectSystem=strict
- [x] NoNewPrivileges=true
- [x] Firewall rules (ufw allow 4848)
- [ ] TLS termination (consider reverse proxy with Caddy/Nginx)
- [ ] Rate limiting (consider adding Vapor middleware)
- [ ] Audit logging (consider adding audit trail for actions)

## Performance Tuning

### Increase file descriptor limits

```bash
# In mksiptv-server.service
LimitNOFILE=65536
```

### Adjust Swift runtime

```bash
# Environment variables
Environment="SWIFT_RUNTIME_SCHEDULER=threads"
Environment="SWIFT_CONCURRENCY_COOPERATIVE_POOL_OVERCOMMIT=1"
```

## Next Steps

1. Test deployment on staging environment
2. Set up monitoring/alerting
3. Configure TLS with reverse proxy
4. Set up automated backups
5. Document disaster recovery procedure

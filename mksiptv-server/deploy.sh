#!/bin/bash
# deploy.sh - Deploy mksiptv-server to VPS Helsinki
#
# Usage:
#   ./deploy.sh [--dry-run] [--skip-build] [--verbose]
#
# Flags:
#   --dry-run       Show commands without executing
#   --skip-build    Use existing binary without rebuilding
#   --verbose       Show all commands output

set -e

# Config
SERVER_IP="hs.mks2508.systems"
SERVER_USER="root"
SERVER_PATH="/opt/mksiptv-server"
BINARY_NAME="mksiptv-server"
LOCAL_BINARY=".build/release/${BINARY_NAME}"

# Flags
DRY_RUN=false
SKIP_BUILD=false
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--dry-run] [--skip-build] [--verbose]"
      exit 1
      ;;
  esac
done

# Helper functions
run_cmd() {
  local cmd="$1"
  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] $cmd"
  else
    if [ "$VERBOSE" = true ]; then
      echo "[EXEC] $cmd"
      eval "$cmd"
    else
      eval "$cmd" > /dev/null 2>&1
    fi
  fi
}

echo "🚀 Deploying mksiptv-server to ${SERVER_IP}..."

# Step 1: Build
if [ "$SKIP_BUILD" = false ]; then
  echo "📦 Building release binary..."
  if [ "$DRY_RUN" = false ]; then
    swift build --configuration release
  fi

  if [ ! -f "$LOCAL_BINARY" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY RUN] Would verify binary at $LOCAL_BINARY"
    else
      echo "❌ Build failed: binary not found at $LOCAL_BINARY"
      exit 1
    fi
  else
    echo "✅ Build complete: $LOCAL_BINARY"
  fi
else
  echo "⏭️  Skipping build (using existing binary)"
fi

# Step 2: Stop service
echo "🛑 Stopping service on remote..."
run_cmd "ssh ${SERVER_USER}@${SERVER_IP} \"systemctl stop ${BINARY_NAME} || true\""

# Step 3: Upload binary
echo "📤 Uploading binary..."
run_cmd "scp ${LOCAL_BINARY} ${SERVER_USER}@${SERVER_IP}:${SERVER_PATH}/"

# Step 4: Set permissions
echo "🔒 Setting permissions..."
run_cmd "ssh ${SERVER_USER}@${SERVER_IP} \"chmod +x ${SERVER_PATH}/${BINARY_NAME}\""

# Step 5: Create directories
echo "📁 Creating directories..."
run_cmd "ssh ${SERVER_USER}@${SERVER_IP} \"mkdir -p ${SERVER_PATH}/{config,logs,downloads}\""

# Step 6: Reload systemd
echo "🔄 Reloading systemd..."
run_cmd "ssh ${SERVER_USER}@${SERVER_IP} \"systemctl daemon-reload\""

# Step 7: Start service
echo "▶️  Starting service..."
run_cmd "ssh ${SERVER_USER}@${SERVER_IP} \"systemctl start ${BINARY_NAME}\""

# Step 8: Health check
echo "🏥 Health check..."
sleep 2
if [ "$DRY_RUN" = false ]; then
  if curl -sf "http://${SERVER_IP}:4848/health" > /dev/null; then
    echo "✅ Deploy successful! Service is healthy."
    echo "📊 Status: ssh ${SERVER_USER}@${SERVER_IP} \"systemctl status ${BINARY_NAME}\""
    echo "📋 Logs: ssh ${SERVER_USER}@${SERVER_IP} \"journalctl -u ${BINARY_NAME} -n 50\""
  else
    echo "❌ Health check failed! Service may not be running correctly."
    echo "📋 Check logs: ssh ${SERVER_USER}@${SERVER_IP} \"journalctl -u ${BINARY_NAME} -n 50\""
    exit 1
  fi
else
  echo "[DRY RUN] Would run health check at: http://${SERVER_IP}:4848/health"
fi

echo "🎉 Deploy complete!"

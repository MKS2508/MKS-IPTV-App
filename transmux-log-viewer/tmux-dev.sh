#!/bin/bash

# tmux-dev.sh - Idempotent development environment manager
# Creates/attaches to tmux session with split panes for Transmux Log Viewer

set -euo pipefail

# Configuration
SESSION_NAME="transmux-dev"
LOG_FILE="/tmp/mks-iptv-transmux.log"
TRANSMUX_DIR="/Users/mks/Documents/MKS-IPTV-App/TransmuxCore"
LOGVIEWER_DIR="/Users/mks/Documents/MKS-IPTV-App/transmux-log-viewer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[tmux-dev]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[tmux-dev]${NC} $1"
}

error() {
    echo -e "${RED}[tmux-dev]${NC} $1"
}

# Kill existing session if clean flag is set
if [[ "${1:-}" == "--clean" ]]; then
    log "Cleaning existing session..."
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    pkill -f "bun run dev" 2>/dev/null || true
    pkill -f "vite" 2>/dev/null || true
    exit 0
fi

# Check if session exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    log "Session '$SESSION_NAME' already exists"
    
    # Check if already attached
    if [[ -n "${TMUX:-}" ]] && [[ "$TMUX" == *"tmux"* ]] && [[ "$TMUX" == *"$SESSION_NAME"* ]]; then
        warn "Already attached to session '$SESSION_NAME'"
        exit 0
    fi
    
    log "Attaching to existing session..."
    exec tmux attach -t "$SESSION_NAME"
    exit 0
fi

# Create new session
log "Creating new tmux session '$SESSION_NAME'..."

# Create session with first window (CLI/Commands)
tmux new-session -d -s "$SESSION_NAME" -c "$TRANSMUX_DIR" -n "CLI"

# Split windows and create panes
# Window 1: CLI/Commands (split: top = commands, bottom = file system)
tmux split-window -v -c "$TRANSMUX_DIR"
tmux send-keys -t "$SESSION_NAME:0.0" "clear && echo '=== TransmuxCore CLI Commands ==='" Enter
tmux send-keys -t "$SESSION_NAME:0.1" "clear && echo '=== File System ===' && ls -la" Enter

# Window 2: Development (split: top-left = backend, top-right = frontend, bottom = log tail)
tmux new-window -c "$LOGVIEWER_DIR" -n "Dev"
tmux split-window -h -c "$LOGVIEWER_DIR"  # Right pane for frontend
tmux split-window -v -c "$LOGVIEWER_DIR"  # Split right pane vertically
tmux select-pane -t "$SESSION_NAME:1.0"  # Focus on backend pane
tmux split-window -v -c "$TRANSMUX_DIR"  # Split left pane vertically (bottom for log tail)

# Pane layout for Dev window:
# ┌─────────────┬─────────────┐
# │   Backend   │  Frontend   │
# ├─────────────┼─────────────┤
# │  Log Tail   │             │
# └─────────────┴─────────────┘

# Setup each pane
# Backend (top-left)
tmux send-keys -t "$SESSION_NAME:1.0" "clear && echo '=== Backend (Port 3000) ===' && bun run dev:backend" Enter

# Frontend (top-right)
tmux send-keys -t "$SESSION_NAME:1.1" "clear && echo '=== Frontend (Port 5173) ===' && bun run dev:frontend" Enter

# Log Tail (bottom-left)
tmux send-keys -t "$SESSION_NAME:1.2" "clear && echo '=== Log Tail: $LOG_FILE ===' && sleep 2 && tail -f $LOG_FILE" Enter

# Window 3: Test Tools
tmux new-window -c "$LOGVIEWER_DIR" -n "Test"
tmux send-keys -t "$SESSION_NAME:2" "clear && echo '=== Test Tools ==='
echo 'Available commands:'
echo '  curl http://localhost:3000/health'
echo '  curl http://localhost:3000/logs/history'
echo '  curl http://localhost:3000/logs/stream'
echo '  curl -X POST http://localhost:3000/logs/clear'
echo ''
echo 'Test files:'
echo '  ls /Volumes/KODAK1TB/*.mkv'
" Enter

# Focus on backend pane initially
tmux select-window -t "$SESSION_NAME:1"
tmux select-pane -t "$SESSION_NAME:1.0"

# Create log file if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

# Wait a moment for services to start
log "Waiting for services to start..."
sleep 3

# Check if services are up
log "Checking services..."
if curl -s http://localhost:3000/health >/dev/null 2>&1; then
    log "✓ Backend is running on port 3000"
else
    warn "✗ Backend not responding on port 3000"
fi

if curl -s http://localhost:5173 >/dev/null 2>&1; then
    log "✓ Frontend is running on port 5173"
else
    warn "✗ Frontend not responding on port 5173"
fi

# Session info
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Transmux Log Viewer Development Environment               ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║ Session: $SESSION_NAME"
echo "║ Layout:"
echo "║   Window 1: CLI Commands (split)"
echo "║   Window 2: Dev Environment (4-way split)"
echo "║     ├─ Backend     (port 3000)"
echo "║     ├─ Frontend    (port 5173)"
echo "║     └─ Log Tail"
echo "║   Window 3: Test Tools"
echo "║"
echo "║ Commands:"
echo "║   tmux attach -t $SESSION_NAME     - Attach to session"
echo "║   ./tmux-dev.sh --clean           - Kill session and clean"
echo "║   Ctrl+b d                       - Detach from session"
echo "║"
echo "║ URLs:"
echo "║   Frontend: http://localhost:5173"
echo "║   Backend:  http://localhost:3000"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Attach to session
exec tmux attach -t "$SESSION_NAME"
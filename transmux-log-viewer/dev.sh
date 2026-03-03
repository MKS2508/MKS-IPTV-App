#!/bin/bash

# dev.sh - Entorno de desarrollo idempotente
# Crea sesión tmux con 4 paneles split si servicios no están corriendo
# Si sesión o servicios ya existen, muestra error y guía al usuario

set -euo pipefail

# Configuration
SESSION_NAME="transmux-dev"
LOG_FILE="/tmp/mks-iptv-transmux.log"
TRANSMUX_DIR="/Users/mks/Documents/MKS-IPTV-App/TransmuxCore"
TRANSMUX_CLI="$TRANSMUX_DIR/.build/arm64-apple-macosx/debug/transmux-cli"
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

# Check if services are already running
check_services() {
    local backend_running frontend_running session_exists
    
    # Check backend
    if curl -s --max-time 1 "http://localhost:3000" >/dev/null 2>&1; then
        backend_running=1
    else
        backend_running=0
    fi
    
    # Check frontend
    if curl -s --max-time 1 "http://localhost:5173" >/dev/null 2>&1; then
        frontend_running=1
    else
        frontend_running=0
    fi
    
    # Check tmux session
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        session_exists=1
    else
        session_exists=0
    fi
    
    echo "$backend_running:$frontend_running:$session_exists"
}

# Create log file if doesn't exist
setup_log_file() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# Check TransmuxCore CLI availability
check_cli() {
    if [[ ! -f "$TRANSMUX_CLI" ]]; then
        warn "TransmuxCore CLI not found at: $TRANSMUX_CLI"
        warn "Build it with: cd $TRANSMUX_DIR && swift build --product transmux-cli"
        return 1
    fi
    return 0
}

# Create full development session
create_full_dev_session() {
    log "Creating development session..."
    
    # Create session
    tmux new-session -d -s "$SESSION_NAME" -c "$LOGVIEWER_DIR"
    
    # Create 4-pane layout (2x2 grid)
    # First split: horizontal (top/bottom)
    tmux split-window -v
    # Split top pane vertically (backend | frontend)
    tmux select-pane -t 0
    tmux split-window -h
    # Split bottom pane vertically (log | cli)
    tmux select-pane -t 2
    tmux split-window -h
    
    # Setup pane 0: Backend (top-left)
    tmux send-keys -t "$SESSION_NAME:0.0" "clear && echo '=== Backend (Port 3000) ==='" Enter
    tmux send-keys -t "$SESSION_NAME:0.0" "bun run dev:backend" Enter
    
    # Setup pane 1: Frontend (top-right)
    tmux send-keys -t "$SESSION_NAME:0.1" "clear && echo '=== Frontend (Port 5173) ==='" Enter
    tmux send-keys -t "$SESSION_NAME:0.1" "bun run dev:frontend" Enter
    
    # Setup pane 2: Log Tail (bottom-left)
    tmux send-keys -t "$SESSION_NAME:0.2" "clear && echo '=== Log Tail: $LOG_FILE ==='" Enter
    tmux send-keys -t "$SESSION_NAME:0.2" "sleep 2 && tail -f $LOG_FILE" Enter
    
    # Setup pane 3: CLI Transmux (bottom-right)
    tmux send-keys -t "$SESSION_NAME:0.3" "clear && echo '=== TransmuxCore CLI ==='" Enter
    tmux send-keys -t "$SESSION_NAME:0.3" "cd $TRANSMUX_DIR" Enter
    tmux send-keys -t "$SESSION_NAME:0.3" "ls -la" Enter
    
    # Focus on backend pane initially
    tmux select-pane -t "$SESSION_NAME:0.0"
}

# Main function
main() {
    local service_check
    service_check=$(check_services)
    
    IFS=':' read -r backend_running frontend_running session_exists <<< "$service_check"
    
    # Case 3: Session already exists
    if [[ $session_exists -eq 1 ]]; then
        error "ERROR: Sesión '$SESSION_NAME' ya existe"
        echo ""
        echo "Para unirse a la sesión existente:"
        echo "  tmux attach -t $SESSION_NAME"
        echo ""
        echo "Para terminar la sesión:"
        echo "  tmux kill-session -t $SESSION_NAME"
        echo ""
        echo "Para limpiar todo:"
        echo "  bun run tmux:clean"
        exit 1
    fi
    
    # Case A or B: Services already running
    if [[ $backend_running -eq 1 || $frontend_running -eq 1 ]]; then
        error "ERROR: Servicios ya corriendo"
        echo ""
        if [[ $backend_running -eq 1 ]]; then
            warn "  - Backend detectado en puerto 3000"
        fi
        if [[ $frontend_running -eq 1 ]]; then
            warn "  - Frontend detectado en puerto 5173"
        fi
        echo ""
        echo "Detén los servicios primero:"
        if [[ $backend_running -eq 1 ]]; then
            echo "  pkill -f 'bun run dev:backend'"
        fi
        if [[ $frontend_running -eq 1 ]]; then
            echo "  pkill -f 'bun run dev:frontend'"
        fi
        echo "  o usa: bun run tmux:clean"
        exit 1
    fi
    
    # Normal case: Create full development session
    setup_log_file
    
    if ! check_cli; then
        error "No se puede continuar sin el TransmuxCore CLI"
        exit 1
    fi
    
    create_full_dev_session
    
    # Wait a moment for services to start
    log "Esperando a que los servicios inicien..."
    sleep 3
    
    # Check services status
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                     TRANSMUX LOG VIEWER DEV                     ║"
    echo "╠═════════════════════════════════════════════════════════════════╣"
    echo "║ Sesión: $SESSION_NAME"
    echo "║ Layout: 4 paneles (2x2)"
    echo "║   ┌─────────────────┬─────────────────┐"
    echo "║   │    Backend    │   Frontend     │"
    echo "║   │   (port 3000) │  (port 5173) │"
    echo "║   ├─────────────────┼─────────────────┤"
    echo "║   │   Log Tail    │   CLI Transmux  │"
    echo "║   │               │                │"
    echo "║   └─────────────────┴─────────────────┘"
    echo "║"
    echo "║ URLs:"
    echo "║   Frontend: http://localhost:5173"
    echo "║   Backend:  http://localhost:3000"
    echo "║"
    echo "║ Comandos útiles:"
    echo "║   tmux attach -t $SESSION_NAME     - Unirse a sesión"
    echo "║   Ctrl+b d                       - Detach de sesión"
    echo "║   bun run tmux:clean             - Limpiar todo"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Attach to session
    exec tmux attach -t "$SESSION_NAME"
}

# Check for clean flag
if [[ "${1:-}" == "--clean" ]]; then
    log "Limpiando entorno..."
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    pkill -f "bun run dev" 2>/dev/null || true
    pkill -f "vite" 2>/dev/null || true
    exit 0
fi

main "$@"
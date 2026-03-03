#!/bin/bash

# dev.sh — Transmux Log Viewer development environment
#
# Creates an idempotent tmux session with titled panes, cyberpunk-themed borders,
# portless support, and agent-friendly subcommands.
#
# Usage:
#   ./dev.sh                     Start dev session (direct ports)
#   ./dev.sh --portless          Start with portless proxy (.localhost URLs)
#   ./dev.sh --clean             Kill session and processes
#   ./dev.sh restart backend     Restart backend pane
#   ./dev.sh restart frontend    Restart frontend pane
#   ./dev.sh restart all         Restart both
#   ./dev.sh stop                Send Ctrl+C to all panes
#   ./dev.sh status              Health checks + pane statuses
#   ./dev.sh output <pane>       Capture output from named pane (backend|frontend|log|cli)
#   ./dev.sh log [N]             Tail N lines from log pane (default 50)

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────
SESSION_NAME="transmux-dev"
LOG_FILE="/tmp/mks-iptv-transmux.log"
TRANSMUX_DIR="/Users/mks/Documents/MKS-IPTV-App/TransmuxCore"
TRANSMUX_CLI="$TRANSMUX_DIR/.build/arm64-apple-macosx/debug/transmux-cli"
LOGVIEWER_DIR="/Users/mks/Documents/MKS-IPTV-App/transmux-log-viewer"

# Portless names
PL_BACKEND_NAME="api.transmux"
PL_FRONTEND_NAME="transmux"

# Pane indices
PANE_BACKEND=0
PANE_FRONTEND=1
PANE_LOG=2
PANE_CLI=3

# Mode flag (set by --portless)
USE_PORTLESS=0

# Cyberpunk theme colors (tmux)
C_BLUE="#7aa2f7"
C_MUTED="#565f89"

# Terminal output colors
RED='\033[38;2;247;118;142m'
GREEN='\033[38;2;158;206;106m'
BLUE='\033[38;2;122;162;247m'
PURPLE='\033[38;2;187;154;247m'
YELLOW='\033[38;2;224;175;104m'
MUTED='\033[38;2;86;95;137m'
FG='\033[38;2;192;202;245m'
NC='\033[0m'
BOLD='\033[1m'

# ──────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────
log()   { echo -e "${GREEN}[transmux]${NC} $1"; }
warn()  { echo -e "${YELLOW}[transmux]${NC} $1"; }
error() { echo -e "${RED}[transmux]${NC} $1"; }
info()  { echo -e "${BLUE}[transmux]${NC} $1"; }

pane_target() {
  echo "$SESSION_NAME:0.$1"
}

resolve_pane() {
  case "${1:-}" in
    backend)  echo $PANE_BACKEND ;;
    frontend) echo $PANE_FRONTEND ;;
    log)      echo $PANE_LOG ;;
    cli)      echo $PANE_CLI ;;
    *)        echo "" ;;
  esac
}

session_exists() {
  tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────────────
# Portless helpers
# ──────────────────────────────────────────────────────────────────────
portless_available() {
  command -v portless &>/dev/null
}

portless_proxy_running() {
  portless_available && portless list &>/dev/null
}

ensure_portless_proxy() {
  if ! portless_available; then
    error "portless not found. Install globally: bun install -g portless"
    exit 1
  fi

  if ! portless_proxy_running; then
    log "Starting portless proxy on port 80 (requires sudo)..."
    sudo portless proxy start -p 80 2>&1
  fi
}

# Build the command for each pane based on mode
backend_cmd() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    echo "portless $PL_BACKEND_NAME bun run --filter @transmux-viewer/backend dev"
  else
    echo "bun run dev:backend"
  fi
}

frontend_cmd() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    echo "VITE_API_URL=http://$PL_BACKEND_NAME.localhost portless $PL_FRONTEND_NAME bun run --filter mks-iptv-client dev"
  else
    echo "bun run dev:frontend"
  fi
}

# ──────────────────────────────────────────────────────────────────────
# URL resolution
# ──────────────────────────────────────────────────────────────────────
get_urls() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    FRONTEND_URL="http://$PL_FRONTEND_NAME.localhost"
    BACKEND_URL="http://$PL_BACKEND_NAME.localhost"
    URL_MODE="portless"
  else
    FRONTEND_URL="http://localhost:5173"
    BACKEND_URL="http://localhost:3000"
    URL_MODE="direct"
  fi
}

# ──────────────────────────────────────────────────────────────────────
# Service checks
# ──────────────────────────────────────────────────────────────────────
check_backend() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    curl -sf --max-time 2 "http://$PL_BACKEND_NAME.localhost/health" &>/dev/null && echo "1" || echo "0"
  else
    curl -sf --max-time 2 "http://localhost:3000/health" &>/dev/null && echo "1" || echo "0"
  fi
}

check_frontend() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    curl -sf --max-time 2 "http://$PL_FRONTEND_NAME.localhost" &>/dev/null && echo "1" || echo "0"
  else
    curl -sf --max-time 2 "http://localhost:5173" &>/dev/null && echo "1" || echo "0"
  fi
}

check_cli() {
  if [[ -f "$TRANSMUX_CLI" ]]; then
    echo "1"
  else
    warn "TransmuxCore CLI not found: $TRANSMUX_CLI"
    warn "Build: cd $TRANSMUX_DIR && swift build --product transmux-cli"
    echo "0"
  fi
}

# ──────────────────────────────────────────────────────────────────────
# Banner
# ──────────────────────────────────────────────────────────────────────
print_banner() {
  get_urls

  echo ""
  echo -e "${PURPLE}${BOLD}"
  echo '  ╔════════════════════════════════════════════════════════════╗'
  echo '  ║          ▀█▀ █▀█ ▄▀█ █▄░█ █▀ █▀▄▀█ █░█ ▀▄▀             ║'
  echo '  ║          ░█░ █▀▄ █▀█ █░▀█ ▄█ █░▀░█ █▄█ █░█             ║'
  echo '  ║                   LOG VIEWER DEV                         ║'
  echo '  ╚════════════════════════════════════════════════════════════╝'
  echo -e "${NC}"
  echo -e "  ${MUTED}Session:${NC}  ${FG}$SESSION_NAME${NC}"
  echo -e "  ${MUTED}Mode:${NC}     ${FG}$URL_MODE${NC}"
  echo ""
  echo -e "  ${MUTED}┌───────────────────┬───────────────────┐${NC}"
  echo -e "  ${MUTED}│${NC} ${BLUE}Backend${NC}           ${MUTED}│${NC} ${GREEN}Frontend${NC}          ${MUTED}│${NC}"
  echo -e "  ${MUTED}├───────────────────┼───────────────────┤${NC}"
  echo -e "  ${MUTED}│${NC} ${YELLOW}Log Tail${NC}          ${MUTED}│${NC} ${PURPLE}CLI / Tests${NC}        ${MUTED}│${NC}"
  echo -e "  ${MUTED}└───────────────────┴───────────────────┘${NC}"
  echo ""
  echo -e "  ${MUTED}URLs:${NC}"
  echo -e "    ${FG}Frontend:${NC}  $FRONTEND_URL"
  echo -e "    ${FG}Backend:${NC}   $BACKEND_URL"
  echo ""
  echo -e "  ${MUTED}Subcommands:${NC}"
  echo -e "    ${FG}./dev.sh restart backend|frontend|all${NC}"
  echo -e "    ${FG}./dev.sh stop | status | output <pane> | log [N]${NC}"
  echo ""
}

# ──────────────────────────────────────────────────────────────────────
# Pane styling
# ──────────────────────────────────────────────────────────────────────
style_panes() {
  # Enable mouse support (click to focus pane, scroll, resize)
  tmux set-option -t "$SESSION_NAME" mouse on 2>/dev/null || true

  # Enable pane border status on top
  tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-border-format \
    " #{?pane_active,#[fg=$C_BLUE#,bold],#[fg=$C_MUTED]} #{pane_title} #[default]" 2>/dev/null || true

  # Border colors
  tmux set-option -t "$SESSION_NAME" pane-border-style "fg=$C_MUTED" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-active-border-style "fg=$C_BLUE" 2>/dev/null || true

  # Title each pane
  tmux select-pane -t "$(pane_target $PANE_BACKEND)"  -T "Backend"  2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_FRONTEND)" -T "Frontend" 2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_LOG)"      -T "Log Tail" 2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_CLI)"      -T "CLI"      2>/dev/null || true
}

# ──────────────────────────────────────────────────────────────────────
# Session creation
# ──────────────────────────────────────────────────────────────────────
create_session() {
  # Ensure log file exists
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  # Ensure portless proxy if in portless mode
  if [[ "$USE_PORTLESS" == "1" ]]; then
    ensure_portless_proxy
  fi

  log "Creating development session..."

  # Create session with 2x2 grid
  tmux new-session -d -s "$SESSION_NAME" -c "$LOGVIEWER_DIR"

  # Split into 4 panes (2x2)
  tmux split-window -v -t "$SESSION_NAME"
  tmux select-pane -t "$(pane_target 0)"
  tmux split-window -h -t "$SESSION_NAME"
  tmux select-pane -t "$(pane_target 2)"
  tmux split-window -h -t "$SESSION_NAME"

  # Style panes
  style_panes

  # Pane 0: Backend
  tmux send-keys -t "$(pane_target $PANE_BACKEND)" \
    "clear && $(backend_cmd)" Enter

  # Pane 1: Frontend
  tmux send-keys -t "$(pane_target $PANE_FRONTEND)" \
    "clear && $(frontend_cmd)" Enter

  # Pane 2: Log Tail
  tmux send-keys -t "$(pane_target $PANE_LOG)" \
    "clear && tail -f $LOG_FILE" Enter

  # Pane 3: CLI
  tmux send-keys -t "$(pane_target $PANE_CLI)" \
    "clear && cd $TRANSMUX_DIR && echo 'TransmuxCore CLI ready'" Enter

  # Focus backend pane
  tmux select-pane -t "$(pane_target $PANE_BACKEND)"

  print_banner

  # Attach
  exec tmux attach -t "$SESSION_NAME"
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: restart
# ──────────────────────────────────────────────────────────────────────
cmd_restart() {
  local target="${1:-all}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found. Run ./dev.sh first."
    exit 1
  fi

  # Detect if current session uses portless (check if portless routes exist)
  if portless_available && portless list 2>/dev/null | grep -q "$PL_BACKEND_NAME"; then
    USE_PORTLESS=1
  fi

  case "$target" in
    backend)
      log "Restarting backend..."
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" \
        "$(backend_cmd)" Enter
      log "Backend restarted"
      ;;
    frontend)
      log "Restarting frontend..."
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" \
        "$(frontend_cmd)" Enter
      log "Frontend restarted"
      ;;
    all)
      log "Restarting all services..."
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" \
        "$(backend_cmd)" Enter
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" \
        "$(frontend_cmd)" Enter
      log "All services restarted"
      ;;
    *)
      error "Unknown target: $target (use backend|frontend|all)"
      exit 1
      ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: stop
# ──────────────────────────────────────────────────────────────────────
cmd_stop() {
  if ! session_exists; then
    error "Session '$SESSION_NAME' not found."
    exit 1
  fi

  log "Stopping all panes..."
  for pane in $PANE_BACKEND $PANE_FRONTEND $PANE_LOG $PANE_CLI; do
    tmux send-keys -t "$(pane_target $pane)" C-c 2>/dev/null || true
  done
  log "All panes stopped"
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: status
# ──────────────────────────────────────────────────────────────────────
cmd_status() {
  # Auto-detect portless mode
  if portless_available && portless list 2>/dev/null | grep -q "$PL_BACKEND_NAME"; then
    USE_PORTLESS=1
  fi

  get_urls

  echo ""
  echo -e "${PURPLE}${BOLD}  TRANSMUX DEV STATUS${NC}"
  echo -e "  ${MUTED}────────────────────────────────────${NC}"

  # Session
  if session_exists; then
    echo -e "  ${GREEN}●${NC} tmux session: ${FG}$SESSION_NAME${NC}"
  else
    echo -e "  ${RED}●${NC} tmux session: ${MUTED}not running${NC}"
  fi

  # Backend health
  local be_status
  be_status=$(check_backend)
  if [[ "$be_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} Backend:      ${FG}healthy${NC}"
  else
    echo -e "  ${RED}●${NC} Backend:      ${MUTED}unreachable${NC}"
  fi

  # Frontend
  local fe_status
  fe_status=$(check_frontend)
  if [[ "$fe_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} Frontend:     ${FG}running${NC}"
  else
    echo -e "  ${RED}●${NC} Frontend:     ${MUTED}unreachable${NC}"
  fi

  # CLI
  local cli_status
  cli_status=$(check_cli 2>/dev/null)
  if [[ "$cli_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} CLI:          ${FG}available${NC}"
  else
    echo -e "  ${YELLOW}●${NC} CLI:          ${MUTED}not built${NC}"
  fi

  # Portless proxy
  if portless_available; then
    if portless_proxy_running; then
      echo -e "  ${GREEN}●${NC} Portless:     ${FG}proxy running${NC}"
    else
      echo -e "  ${MUTED}●${NC} Portless:     ${MUTED}proxy stopped${NC}"
    fi
  fi

  # Mode & URLs
  echo -e "  ${MUTED}─${NC}"
  echo -e "  ${MUTED}Mode:${NC}         ${FG}$URL_MODE${NC}"
  echo -e "  ${MUTED}Frontend:${NC}     ${FG}$FRONTEND_URL${NC}"
  echo -e "  ${MUTED}Backend:${NC}      ${FG}$BACKEND_URL${NC}"

  # Portless routes
  if [[ "$USE_PORTLESS" == "1" ]]; then
    echo -e "  ${MUTED}─${NC}"
    echo -e "  ${MUTED}Portless routes:${NC}"
    portless list 2>/dev/null | while IFS= read -r line; do
      echo -e "    ${FG}$line${NC}"
    done
  fi

  # Log file
  if [[ -f "$LOG_FILE" ]]; then
    local lines
    lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
    echo -e "  ${MUTED}Log file:${NC}     ${FG}$LOG_FILE${NC} (${lines} lines)"
  fi

  echo ""
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: output
# ──────────────────────────────────────────────────────────────────────
cmd_output() {
  local pane_name="${1:-backend}"
  local lines="${2:-50}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found."
    exit 1
  fi

  local pane_idx
  pane_idx=$(resolve_pane "$pane_name")

  if [[ -z "$pane_idx" ]]; then
    error "Unknown pane: $pane_name (use backend|frontend|log|cli)"
    exit 1
  fi

  tmux capture-pane -t "$(pane_target "$pane_idx")" -p | tail -"$lines"
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: log
# ──────────────────────────────────────────────────────────────────────
cmd_log() {
  local lines="${1:-50}"

  if ! session_exists; then
    tail -"$lines" "$LOG_FILE" 2>/dev/null || echo "Log file not found: $LOG_FILE"
    return
  fi

  tmux capture-pane -t "$(pane_target $PANE_LOG)" -p | tail -"$lines"
}

# ──────────────────────────────────────────────────────────────────────
# Subcommand: clean
# ──────────────────────────────────────────────────────────────────────
cmd_clean() {
  log "Cleaning environment..."
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  pkill -f "bun run dev" 2>/dev/null || true
  pkill -f "vite" 2>/dev/null || true
  portless proxy stop 2>/dev/null || true
  log "Clean complete"
}

# ──────────────────────────────────────────────────────────────────────
# Main entry
# ──────────────────────────────────────────────────────────────────────
main() {
  if session_exists; then
    error "Session '$SESSION_NAME' already exists"
    echo ""
    echo -e "  ${FG}Attach:${NC}   tmux attach -t $SESSION_NAME"
    echo -e "  ${FG}Kill:${NC}     tmux kill-session -t $SESSION_NAME"
    echo -e "  ${FG}Clean:${NC}    ./dev.sh --clean"
    echo -e "  ${FG}Status:${NC}   ./dev.sh status"
    echo ""
    exit 1
  fi

  # Check CLI availability (warn but don't block)
  check_cli >/dev/null 2>&1

  create_session
}

# ──────────────────────────────────────────────────────────────────────
# CLI router
# ──────────────────────────────────────────────────────────────────────

# Extract --portless flag from any position
for arg in "$@"; do
  if [[ "$arg" == "--portless" ]]; then
    USE_PORTLESS=1
  fi
done

# Route first non-flag argument
CMD="${1:-}"
[[ "$CMD" == "--portless" ]] && CMD="${2:-}"

case "$CMD" in
  --clean)
    cmd_clean
    ;;
  restart)
    # Shift past 'restart' (and --portless if present)
    shift
    [[ "${1:-}" == "--portless" ]] && shift
    cmd_restart "${1:-all}"
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  output)
    shift
    [[ "${1:-}" == "--portless" ]] && shift
    cmd_output "${1:-backend}" "${2:-50}"
    ;;
  log)
    shift
    [[ "${1:-}" == "--portless" ]] && shift
    cmd_log "${1:-50}"
    ;;
  "")
    main
    ;;
  *)
    error "Unknown command: $CMD"
    echo ""
    echo "Usage:"
    echo "  ./dev.sh [--portless]           Start dev session"
    echo "  ./dev.sh --clean                Kill session + processes + proxy"
    echo "  ./dev.sh restart <target>       Restart backend|frontend|all"
    echo "  ./dev.sh stop                   Stop all panes"
    echo "  ./dev.sh status                 Health checks"
    echo "  ./dev.sh output <pane> [N]      Capture pane output"
    echo "  ./dev.sh log [N]                Tail log pane"
    echo ""
    exit 1
    ;;
esac

#!/bin/bash

# dev.sh — Transmux Log Viewer development environment
#
# Creates an idempotent tmux session with titled panes, cyberpunk-themed status bar,
# portless support, and agent-friendly subcommands.
#
# Configuration: .tmuxdev.env (copy from .tmuxdev.env.example)
#
# Usage:
#   ./dev.sh                     Start dev session (portless on port 80)
#   ./dev.sh clean               Kill session and processes
#   ./dev.sh restart api|web|all Restart services
#   ./dev.sh stop                Send Ctrl+C to all panes
#   ./dev.sh status              Health checks + pane statuses
#   ./dev.sh output <pane> [N]   Capture output (api|web|logs|shell or 0|1|2|3)
#
# Panes:
#   0:api     - Elysia Backend
#   1:web     - Vite Frontend
#   2:logs    - tail -f log file
#   3:shell   - CLI + testing
#
# Exit: Ctrl+b Q (popup confirmation)

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Configuration Loading
# ═══════════════════════════════════════════════════════════════════════════

# Get script directory (project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$SCRIPT_DIR}"

# Load environment file
ENV_FILE="$PROJECT_ROOT/.tmuxdev.env"
if [[ -f "$ENV_FILE" ]]; then
  # Source the env file (handles comments and exports)
  set -a
  source "$ENV_FILE"
  set +a
fi

# ═══════════════════════════════════════════════════════════════════════════
# Defaults (if not set in .env)
# ═══════════════════════════════════════════════════════════════════════════

# Session
SESSION_NAME="${TMUX_SESSION_NAME:-transmux-dev}"

# Paths
LOG_FILE="${LOG_FILE:-/tmp/mks-iptv-transmux.log}"
TRANSMUX_DIR="${TRANSMUX_DIR:-$PROJECT_ROOT/../TransmuxCore}"
TRANSMUX_CLI="${TRANSMUX_CLI:-$TRANSMUX_DIR/.build/arm64-apple-macosx/debug/transmux-cli}"
PRIMARY_TEST_FILE="${PRIMARY_TEST_FILE:-}"

# Portless
USE_PORTLESS="${USE_PORTLESS:-1}"
PORTLESS_PORT="${PORTLESS_PORT:-80}"
PL_BACKEND_NAME="${PL_BACKEND_NAME:-transmux-api}"
PL_FRONTEND_NAME="${PL_FRONTEND_NAME:-transmux-app}"

# Direct ports
BACKEND_PORT="${BACKEND_PORT:-3000}"
FRONTEND_PORT="${FRONTEND_PORT:-5173}"

# Pane indices
PANE_BACKEND="${PANE_BACKEND:-0}"
PANE_FRONTEND="${PANE_FRONTEND:-1}"
PANE_LOG="${PANE_LOG:-2}"
PANE_CLI="${PANE_CLI:-3}"

# Theme colors
C_BLUE="${TMUX_COLOR_BLUE:-#7aa2f7}"
C_MUTED="${TMUX_COLOR_MUTED:-#565f89}"

# Package filters
BACKEND_PACKAGE="${BACKEND_PACKAGE:-@transmux-viewer/backend}"
FRONTEND_PACKAGE="${FRONTEND_PACKAGE:-mks-iptv-client}"

# ═══════════════════════════════════════════════════════════════════════════
# Terminal Colors
# ═══════════════════════════════════════════════════════════════════════════

RED='\033[38;2;247;118;142m'
GREEN='\033[38;2;158;206;106m'
BLUE='\033[38;2;122;162;247m'
PURPLE='\033[38;2;187;154;247m'
YELLOW='\033[38;2;224;175;104m'
MUTED='\033[38;2;86;95;137m'
FG='\033[38;2;192;202;245m'
NC='\033[0m'
BOLD='\033[1m'

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

log()   { echo -e "${GREEN}[transmux]${NC} $1"; }
warn()  { echo -e "${YELLOW}[transmux]${NC} $1"; }
error() { echo -e "${RED}[transmux]${NC} $1"; }
info()  { echo -e "${BLUE}[transmux]${NC} $1"; }

pane_target() {
  echo "$SESSION_NAME:0.$1"
}

resolve_pane() {
  case "${1:-}" in
    backend|api|0)  echo $PANE_BACKEND ;;
    frontend|web|1) echo $PANE_FRONTEND ;;
    log|logs|2)     echo $PANE_LOG ;;
    cli|shell|3)    echo $PANE_CLI ;;
    *)              echo "" ;;
  esac
}

session_exists() {
  tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
# Portless Helpers
# ═══════════════════════════════════════════════════════════════════════════

portless_available() {
  command -v portless &>/dev/null
}

portless_proxy_running() {
  portless_available && portless list &>/dev/null
}

portless_proxy_is_running_on_port() {
  local port="${1:-80}"
  if [[ "$port" == "80" ]]; then
    pgrep -f "portless proxy" &>/dev/null
  else
    portless_proxy_running
  fi
}

ensure_portless_proxy() {
  if ! portless_available; then
    error "portless not found. Install globally: bun install -g portless"
    exit 1
  fi

  if portless_proxy_is_running_on_port "$PORTLESS_PORT"; then
    log "Portless proxy already running on port $PORTLESS_PORT"
    return 0
  fi

  log "Starting portless proxy on port $PORTLESS_PORT..."

  if [[ "$PORTLESS_PORT" == "80" ]]; then
    info "Port 80 requires sudo privileges."
    info "You may be prompted for your password..."

    sudo -v || {
      error "Failed to get sudo credentials"
      exit 1
    }

    sudo portless proxy start -p 80 2>&1 || {
      error "Failed to start portless proxy on port 80"
      exit 1
    }

    log "Portless proxy started on port 80"
  else
    portless proxy start 2>&1 || {
      error "Failed to start portless proxy"
      exit 1
    }
    log "Portless proxy started on port $PORTLESS_PORT"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Command Builders
# ═══════════════════════════════════════════════════════════════════════════

backend_cmd() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    echo "cd $PROJECT_ROOT && portless $PL_BACKEND_NAME bun run --filter $BACKEND_PACKAGE dev"
  else
    echo "cd $PROJECT_ROOT && bun run --filter $BACKEND_PACKAGE dev"
  fi
}

frontend_cmd() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    local backend_url
    if [[ "$PORTLESS_PORT" == "80" ]]; then
      backend_url="http://$PL_BACKEND_NAME.localhost"
    else
      backend_url="http://$PL_BACKEND_NAME.localhost:$PORTLESS_PORT"
    fi
    echo "cd $PROJECT_ROOT && VITE_API_URL=$backend_url portless $PL_FRONTEND_NAME bun run --filter $FRONTEND_PACKAGE dev"
  else
    echo "cd $PROJECT_ROOT && bun run --filter $FRONTEND_PACKAGE dev"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# URL Resolution
# ═══════════════════════════════════════════════════════════════════════════

get_urls() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    if [[ "$PORTLESS_PORT" == "80" ]]; then
      FRONTEND_URL="http://$PL_FRONTEND_NAME.localhost"
      BACKEND_URL="http://$PL_BACKEND_NAME.localhost"
    else
      FRONTEND_URL="http://$PL_FRONTEND_NAME.localhost:$PORTLESS_PORT"
      BACKEND_URL="http://$PL_BACKEND_NAME.localhost:$PORTLESS_PORT"
    fi
    URL_MODE="portless"
  else
    FRONTEND_URL="http://localhost:$FRONTEND_PORT"
    BACKEND_URL="http://localhost:$BACKEND_PORT"
    URL_MODE="direct"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Service Checks
# ═══════════════════════════════════════════════════════════════════════════

check_backend() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    local url
    if [[ "$PORTLESS_PORT" == "80" ]]; then
      url="http://$PL_BACKEND_NAME.localhost/health"
    else
      url="http://$PL_BACKEND_NAME.localhost:$PORTLESS_PORT/health"
    fi
    curl -sf --max-time 2 "$url" &>/dev/null && echo "1" || echo "0"
  else
    curl -sf --max-time 2 "http://localhost:$BACKEND_PORT/health" &>/dev/null && echo "1" || echo "0"
  fi
}

check_frontend() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    local url
    if [[ "$PORTLESS_PORT" == "80" ]]; then
      url="http://$PL_FRONTEND_NAME.localhost"
    else
      url="http://$PL_FRONTEND_NAME.localhost:$PORTLESS_PORT"
    fi
    curl -sf --max-time 2 "$url" &>/dev/null && echo "1" || echo "0"
  else
    curl -sf --max-time 2 "http://localhost:$FRONTEND_PORT" &>/dev/null && echo "1" || echo "0"
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

# ═══════════════════════════════════════════════════════════════════════════
# Banner
# ═══════════════════════════════════════════════════════════════════════════

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
  echo -e "  ${MUTED}Session:${NC}  ${FG}$SESSION_NAME${NC}  ${MUTED}│${NC}  ${MUTED}Mode:${NC} ${FG}$URL_MODE${NC}"
  echo ""
  echo -e "  ${MUTED}┌─────────────────────────────┬─────────────────────────────┐${NC}"
  echo -e "  ${MUTED}│${NC} ${BLUE}${BOLD}0:api${NC} ${MUTED}Elysia Backend${NC}       ${MUTED}│${NC} ${GREEN}${BOLD}1:web${NC} ${MUTED}Vite Frontend${NC}       ${MUTED}│${NC}"
  echo -e "  ${MUTED}│${NC}   ${FG}$BACKEND_URL${NC}        ${MUTED}│${NC}   ${FG}$FRONTEND_URL${NC}       ${MUTED}│${NC}"
  echo -e "  ${MUTED}├─────────────────────────────┼─────────────────────────────┤${NC}"
  echo -e "  ${MUTED}│${NC} ${YELLOW}${BOLD}2:logs${NC} ${MUTED}tail -f log${NC}          ${MUTED}│${NC} ${PURPLE}${BOLD}3:shell${NC} ${MUTED}CLI + Tests${NC}        ${MUTED}│${NC}"
  echo -e "  ${MUTED}│${NC}   ${FG}$LOG_FILE${NC}  ${MUTED}│${NC}   ${FG}transmux-cli ready${NC}       ${MUTED}│${NC}"
  echo -e "  ${MUTED}└─────────────────────────────┴─────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${MUTED}Shortcuts:${NC}"
  echo -e "    ${FG}Ctrl+b Q${NC}    ${MUTED}Exit session (popup confirm)${NC}"
  echo -e "    ${FG}Ctrl+b 0-3${NC}   ${MUTED}Jump to pane by index${NC}"
  echo -e "    ${FG}Ctrl+b arrows${NC} ${MUTED}Navigate between panes${NC}"
  echo ""
  echo -e "  ${MUTED}CLI Commands (tracked via API):${NC}"
  echo -e "    ${FG}./dev.sh cli basic${NC}           ${MUTED}10s transmux test${NC}"
  echo -e "    ${FG}./dev.sh cli seek 300${NC}        ${MUTED}Seek to 5min${NC}"
  echo -e "    ${FG}./dev.sh cli stop${NC}            ${MUTED}Stop running session${NC}"
  echo -e "    ${FG}./dev.sh cli sessions${NC}        ${MUTED}List tracked sessions${NC}"
  echo -e "    ${FG}./dev.sh grep ac3${NC}            ${MUTED}Filter AC3 logs${NC}"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# Pane Styling
# ═══════════════════════════════════════════════════════════════════════════

style_panes() {
  # Enable mouse support
  tmux set-option -t "$SESSION_NAME" mouse on 2>/dev/null || true

  # Enable pane border status on top
  tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-border-format \
    " #{?pane_active,#[fg=$C_BLUE#,bold],#[fg=$C_MUTED]} #{pane_index}:#{pane_title} #[default]" 2>/dev/null || true

  # Border colors
  tmux set-option -t "$SESSION_NAME" pane-border-style "fg=$C_MUTED" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" pane-active-border-style "fg=$C_BLUE" 2>/dev/null || true

  # Pane titles
  tmux select-pane -t "$(pane_target $PANE_BACKEND)"  -T "api"   2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_FRONTEND)" -T "web"   2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_LOG)"      -T "logs"  2>/dev/null || true
  tmux select-pane -t "$(pane_target $PANE_CLI)"      -T "shell" 2>/dev/null || true

  # Status bar
  get_urls
  local status_left="#[fg=$C_BLUE,bold] TRANSMUX #[default]#[fg=$C_MUTED]│#[default]"
  status_left+=" #[fg=white]${URL_MODE}#[default]"

  local status_right="#[fg=$C_MUTED]Exit:#[fg=white] Ctrl+b Q#[default]"
  status_right+=" #[fg=$C_MUTED]│#[default]"
  status_right+=" #[fg=$C_BLUE]%H:%M:%S#[default]"

  tmux set-option -t "$SESSION_NAME" status on 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-position bottom 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-style "bg=#1a1b26,fg=$C_MUTED" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-left "$status_left " 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-left-length 30 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-right " $status_right" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-right-length 40 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" status-justify centre 2>/dev/null || true

  # Window status
  tmux set-option -t "$SESSION_NAME" window-status-format \
    "#[fg=$C_MUTED] #I:#W #[default]" 2>/dev/null || true
  tmux set-option -t "$SESSION_NAME" window-status-current-format \
    "#[fg=$C_BLUE,bold] #[fg=white]#I:#W #[fg=$C_BLUE]#[default]" 2>/dev/null || true

  # Exit key binding
  tmux bind-key -T prefix Q confirm-before -p "Kill $SESSION_NAME session? (y/n) " \
    "kill-session -t $SESSION_NAME" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════
# Session Creation
# ═══════════════════════════════════════════════════════════════════════════

create_session() {
  # Ensure log file exists
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  # Ensure portless proxy if needed
  if [[ "$USE_PORTLESS" == "1" ]]; then
    ensure_portless_proxy
  fi

  log "Creating development session..."

  # Create session with 2x2 grid
  tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_ROOT"

  # Split into 4 panes
  tmux split-window -v -t "$SESSION_NAME"
  tmux select-pane -t "$(pane_target 0)"
  tmux split-window -h -t "$SESSION_NAME"
  tmux select-pane -t "$(pane_target 2)"
  tmux split-window -h -t "$SESSION_NAME"

  # Style panes
  style_panes

  # Start services in each pane
  tmux send-keys -t "$(pane_target $PANE_BACKEND)" \
    "clear && echo -e '\\033[38;2;122;162;247m▶ Starting Elysia API server...\\033[0m' && $(backend_cmd)" Enter

  tmux send-keys -t "$(pane_target $PANE_FRONTEND)" \
    "clear && echo -e '\\033[38;2;158;206;106m▶ Starting Vite dev server...\\033[0m' && $(frontend_cmd)" Enter

  tmux send-keys -t "$(pane_target $PANE_LOG)" \
    "clear && echo -e '\\033[38;2;224;175;104m▶ Tailing transmux logs...\\033[0m' && tail -f $LOG_FILE" Enter

  tmux send-keys -t "$(pane_target $PANE_CLI)" \
    "clear && cd $TRANSMUX_DIR && echo -e '\\033[38;2;187;154;247m▶ TransmuxCore CLI ready\\033[0m' && echo -e '\\033[38;2;86;95;137m  Usage: $TRANSMUX_CLI <input> [--seek N] [--duration N] [--verbose]\\033[0m' && echo ''" Enter

  # Focus API pane
  tmux select-pane -t "$(pane_target $PANE_BACKEND)"

  print_banner

  # Attach
  exec tmux attach -t "$SESSION_NAME"
}

# ═══════════════════════════════════════════════════════════════════════════
# Subcommands
# ═══════════════════════════════════════════════════════════════════════════

cmd_restart() {
  local target="${1:-all}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found. Run ./dev.sh first."
    exit 1
  fi

  # Detect portless mode
  if portless_available && portless list 2>/dev/null | grep -q "$PL_BACKEND_NAME"; then
    USE_PORTLESS=1
  fi

  case "$target" in
    backend|api|0)
      log "Restarting API (pane 0)..."
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" "$(backend_cmd)" Enter
      log "API restarted"
      ;;
    frontend|web|1)
      log "Restarting Web (pane 1)..."
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" "$(frontend_cmd)" Enter
      log "Web restarted"
      ;;
    all)
      log "Restarting all services..."
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" C-c
      tmux send-keys -t "$(pane_target $PANE_BACKEND)" "$(backend_cmd)" Enter
      tmux send-keys -t "$(pane_target $PANE_FRONTEND)" "$(frontend_cmd)" Enter
      log "All services restarted"
      ;;
    *)
      error "Unknown target: $target (use api|web|all)"
      exit 1
      ;;
  esac
}

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

  # API
  local be_status
  be_status=$(check_backend)
  if [[ "$be_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} API (0):       ${FG}healthy${NC}"
  else
    echo -e "  ${RED}●${NC} API (0):       ${MUTED}unreachable${NC}"
  fi

  # Web
  local fe_status
  fe_status=$(check_frontend)
  if [[ "$fe_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} Web (1):       ${FG}running${NC}"
  else
    echo -e "  ${RED}●${NC} Web (1):       ${MUTED}unreachable${NC}"
  fi

  # CLI
  local cli_status
  cli_status=$(check_cli 2>/dev/null)
  if [[ "$cli_status" == "1" ]]; then
    echo -e "  ${GREEN}●${NC} CLI:           ${FG}available${NC}"
  else
    echo -e "  ${YELLOW}●${NC} CLI:           ${MUTED}not built${NC}"
  fi

  # Portless
  if portless_available; then
    if portless_proxy_running; then
      echo -e "  ${GREEN}●${NC} Portless:      ${FG}proxy running${NC}"
    else
      echo -e "  ${MUTED}●${NC} Portless:      ${MUTED}proxy stopped${NC}"
    fi
  fi

  # URLs
  echo -e "  ${MUTED}─${NC}"
  echo -e "  ${MUTED}Mode:${NC}         ${FG}$URL_MODE${NC}"
  echo -e "  ${MUTED}Web:${NC}          ${FG}$FRONTEND_URL${NC}"
  echo -e "  ${MUTED}API:${NC}          ${FG}$BACKEND_URL${NC}"

  # Portless routes
  if [[ "$USE_PORTLESS" == "1" ]] && portless_available; then
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
    echo -e "  ${MUTED}─${NC}"
    echo -e "  ${MUTED}Log file:${NC}     ${FG}$LOG_FILE${NC} (${lines} lines)"
  fi

  echo ""
}

cmd_output() {
  local pane_name="${1:-api}"
  local lines="${2:-50}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found."
    exit 1
  fi

  local pane_idx
  pane_idx=$(resolve_pane "$pane_name")

  if [[ -z "$pane_idx" ]]; then
    error "Unknown pane: $pane_name (use api|web|logs|shell or 0|1|2|3)"
    exit 1
  fi

  tmux capture-pane -t "$(pane_target "$pane_idx")" -p | tail -"$lines"
}

cmd_log() {
  local lines="${1:-50}"

  if ! session_exists; then
    tail -"$lines" "$LOG_FILE" 2>/dev/null || echo "Log file not found: $LOG_FILE"
    return
  fi

  tmux capture-pane -t "$(pane_target $PANE_LOG)" -p | tail -"$lines"
}

cmd_clean() {
  log "Cleaning environment..."

  # Stop all CLI sessions via API first
  if [[ "$(check_backend)" == "1" ]]; then
    log "Stopping CLI sessions via API..."
    local sessions
    sessions=$(api_get_sessions 2>/dev/null | jq -r '.sessions[] | select(.status == "running") | .sessionId' 2>/dev/null)
    for sid in $sessions; do
      log "Stopping session: $sid"
      api_stop_session "$sid" >/dev/null 2>&1
    done
  fi

  # Kill tmux session
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

  # Kill any remaining processes
  pkill -f "bun run dev" 2>/dev/null || true
  pkill -f "bun run --filter" 2>/dev/null || true
  pkill -f "vite" 2>/dev/null || true
  pkill -f "elysia" 2>/dev/null || true
  pkill -f "transmux-cli" 2>/dev/null || true

  # Unlink portless routes
  portless unlink "$PL_BACKEND_NAME" 2>/dev/null || true
  portless unlink "$PL_FRONTEND_NAME" 2>/dev/null || true

  log "Clean complete"
  echo ""
  echo -e "  ${MUTED}Portless proxy still running (use 'portless proxy stop' to stop)${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# API Helpers (for tracked CLI execution)
# ═══════════════════════════════════════════════════════════════════════════

get_api_url() {
  if [[ "$USE_PORTLESS" == "1" ]]; then
    if [[ "$PORTLESS_PORT" == "80" ]]; then
      echo "http://$PL_BACKEND_NAME.localhost"
    else
      echo "http://$PL_BACKEND_NAME.localhost:$PORTLESS_PORT"
    fi
  else
    echo "http://localhost:$BACKEND_PORT"
  fi
}

api_run_cli() {
  local input="$1"
  local seek="${2:-0}"
  local duration="${3:-10}"
  local api_url
  api_url=$(get_api_url)

  local payload="{\"input\":\"$input\""
  if [[ "$seek" != "0" ]]; then
    payload+=",\"seek\":$seek"
  fi
  payload+=",\"duration\":$duration,\"verbose\":true}"

  local response
  response=$(curl -sf -X POST "$api_url/cli/run" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)

  if [[ $? -ne 0 ]]; then
    error "Failed to call API at $api_url/cli/run"
    return 1
  fi

  echo "$response"
}

api_stop_session() {
  local session_id="$1"
  local api_url
  api_url=$(get_api_url)

  curl -sf -X POST "$api_url/cli/stop/$session_id" 2>/dev/null
}

api_get_sessions() {
  local api_url
  api_url=$(get_api_url)
  curl -sf "$api_url/cli/sessions" 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════
# CLI Commands
# ═══════════════════════════════════════════════════════════════════════════

cmd_cli() {
  local action="${1:-basic}"
  local input="${2:-$PRIMARY_TEST_FILE}"
  local seek_time="${3:-300}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found. Run ./dev.sh first."
    exit 1
  fi

  # Check API is running
  local api_status
  api_status=$(check_backend)
  if [[ "$api_status" != "1" ]]; then
    error "Backend API not running. Start with: ./dev.sh restart api"
    exit 1
  fi

  case "$action" in
    basic)
      log "Running basic transmux (10s) via API on: $input"
      local response
      response=$(api_run_cli "$input" 0 10)
      if [[ $? -eq 0 ]]; then
        local session_id pid
        session_id=$(echo "$response" | jq -r '.sessionId' 2>/dev/null)
        pid=$(echo "$response" | jq -r '.pid' 2>/dev/null)
        log "Started session: $session_id (PID: $pid)"
        log "Monitor: ./dev.sh output logs 20"
        log "Stop:     ./dev.sh cli stop $session_id"
      else
        error "Failed to start CLI via API"
      fi
      ;;
    seek)
      log "Running seek test (seek=${seek_time}s, duration=20s) via API on: $input"
      local response
      response=$(api_run_cli "$input" "$seek_time" 20)
      if [[ $? -eq 0 ]]; then
        local session_id pid
        session_id=$(echo "$response" | jq -r '.sessionId' 2>/dev/null)
        pid=$(echo "$response" | jq -r '.pid' 2>/dev/null)
        log "Started session: $session_id (PID: $pid)"
      else
        error "Failed to start CLI via API"
      fi
      ;;
    remote)
      log "Running remote transmux (10s) via API: $input"
      local response
      response=$(api_run_cli "$input" 0 10)
      if [[ $? -eq 0 ]]; then
        local session_id pid
        session_id=$(echo "$response" | jq -r '.sessionId' 2>/dev/null)
        pid=$(echo "$response" | jq -r '.pid' 2>/dev/null)
        log "Started session: $session_id (PID: $pid)"
      else
        error "Failed to start CLI via API"
      fi
      ;;
    stop)
      local session_id="${2:-}"
      if [[ -z "$session_id" ]]; then
        # List active sessions and stop the first running one
        local sessions
        sessions=$(api_get_sessions | jq -r '.sessions[] | select(.status == "running") | .sessionId' 2>/dev/null | head -1)
        if [[ -z "$sessions" ]]; then
          error "No running sessions found"
          exit 1
        fi
        session_id="$sessions"
      fi
      log "Stopping session: $session_id"
      api_stop_session "$session_id" | jq . 2>/dev/null || echo "Session stopped"
      ;;
    sessions)
      log "Active sessions:"
      api_get_sessions | jq '.sessions[] | {id: .sessionId, status: .status, pid: .pid, input: .input}' 2>/dev/null
      ;;
    custom)
      # Custom still uses direct CLI execution (for advanced debugging)
      shift
      if [[ ! -f "$TRANSMUX_CLI" ]]; then
        error "CLI not found: $TRANSMUX_CLI"
        info "Build: cd $TRANSMUX_DIR && swift build --product transmux-cli"
        exit 1
      fi
      log "Running custom CLI (untracked): $*"
      warn "Note: Custom CLI runs untracked. Use 'basic|seek|remote' for tracked execution."
      tmux send-keys -t "$(pane_target $PANE_CLI)" "clear && $TRANSMUX_CLI $*" Enter
      ;;
    *)
      error "Unknown action: $action"
      echo "  Usage: ./dev.sh cli basic|seek|remote|stop|sessions|custom"
      echo ""
      echo "  Actions:"
      echo "    basic    - Run 10s transmux (tracked via API)"
      echo "    seek N   - Seek to N seconds, 20s duration (tracked)"
      echo "    remote   - Run with remote URL (tracked)"
      echo "    stop ID  - Stop session by ID (or auto-stop first running)"
      echo "    sessions - List all tracked sessions"
      echo "    custom   - Run raw CLI command (untracked, for debugging)"
      exit 1
      ;;
  esac
}

cmd_grep() {
  local pattern="${1:-}"
  local lines="${2:-50}"

  if [[ -z "$pattern" ]]; then
    error "Usage: ./dev.sh grep <tag> [lines]"
    echo "  Tags: ac3, seek, remux, segment, error, warn, dts, offset, service"
    exit 1
  fi

  # Map shortcuts
  case "$pattern" in
    ac3)     pattern="AC3" ;;
    seek)    pattern="SEEK" ;;
    remux)   pattern="REMUX" ;;
    segment) pattern="SEGMENTER" ;;
    error)   pattern="ERROR" ;;
    warn)    pattern="WARN" ;;
    dts)     pattern="DTS" ;;
    offset)  pattern="OFFSET" ;;
    service) pattern="SERVICE" ;;
  esac

  if [[ -f "$LOG_FILE" ]]; then
    grep -i "$pattern" "$LOG_FILE" 2>/dev/null | tail -"$lines"
  else
    error "Log file not found: $LOG_FILE"
    exit 1
  fi
}

cmd_test() {
  local preset="${1:-seek-basic}"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found. Run ./dev.sh first."
    exit 1
  fi

  # Check API is running
  local api_status
  api_status=$(check_backend)
  if [[ "$api_status" != "1" ]]; then
    error "Backend API not running. Start with: ./dev.sh restart api"
    exit 1
  fi

  case "$preset" in
    seek-basic)
      log "Running seek-basic test (seek=300, duration=20)"
      cmd_cli seek "$PRIMARY_TEST_FILE" 300
      ;;
    seek-deep)
      log "Running seek-deep test (seek=600, duration=60)"
      local response
      response=$(api_run_cli "$PRIMARY_TEST_FILE" 600 60)
      if [[ $? -eq 0 ]]; then
        local session_id pid
        session_id=$(echo "$response" | jq -r '.sessionId' 2>/dev/null)
        pid=$(echo "$response" | jq -r '.pid' 2>/dev/null)
        log "Started session: $session_id (PID: $pid)"
      fi
      ;;
    ac3-init)
      log "Running AC3 init phase test (duration=5)"
      local response
      response=$(api_run_cli "$PRIMARY_TEST_FILE" 0 5)
      if [[ $? -eq 0 ]]; then
        local session_id pid
        session_id=$(echo "$response" | jq -r '.sessionId' 2>/dev/null)
        pid=$(echo "$response" | jq -r '.pid' 2>/dev/null)
        log "Started session: $session_id (PID: $pid)"
      fi
      ;;
    remote-sample)
      local data_file="$PROJECT_ROOT/data.json"
      if [[ ! -f "$data_file" ]]; then
        error "Data file not found: $data_file"
        exit 1
      fi
      local url
      url=$(jq -r '.[0].url' "$data_file" 2>/dev/null)
      if [[ -n "$url" && "$url" != "null" ]]; then
        log "Running remote test with: $url"
        cmd_cli remote "$url"
      else
        error "Could not read URL from $data_file"
        exit 1
      fi
      ;;
    stop-all)
      log "Stopping all running sessions..."
      local sessions
      sessions=$(api_get_sessions | jq -r '.sessions[] | select(.status == "running") | .sessionId' 2>/dev/null)
      if [[ -z "$sessions" ]]; then
        log "No running sessions"
      else
        for sid in $sessions; do
          log "Stopping: $sid"
          api_stop_session "$sid" >/dev/null
        done
        log "All sessions stopped"
      fi
      ;;
    *)
      error "Unknown preset: $preset"
      echo "  Available: seek-basic, seek-deep, ac3-init, remote-sample, stop-all"
      exit 1
      ;;
  esac
}

cmd_send() {
  local pane_name="${1:-shell}"
  shift
  local command="$*"

  if ! session_exists; then
    error "Session '$SESSION_NAME' not found. Run ./dev.sh first."
    exit 1
  fi

  local pane_idx
  pane_idx=$(resolve_pane "$pane_name")

  if [[ -z "$pane_idx" ]]; then
    error "Unknown pane: $pane_name (use api|web|logs|shell or 0|1|2|3)"
    exit 1
  fi

  tmux send-keys -t "$(pane_target $pane_idx)" "$command" Enter
  log "Sent to $pane_name: $command"
}

cmd_watch() {
  local interval="${1:-3}"
  local json_mode="${2:-}"

  if [[ "$interval" == "--json" ]]; then
    json_mode="--json"
    interval="${2:-3}"
  fi

  while true; do
    if [[ "$json_mode" == "--json" ]]; then
      local log_lines=0
      local last_error=""
      [[ -f "$LOG_FILE" ]] && log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
      [[ -f "$LOG_FILE" ]] && last_error=$(grep -i "ERROR" "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/"/\\"/g')
      echo "{\"timestamp\":\"$(date -Iseconds)\",\"backend\":$(check_backend),\"frontend\":$(check_frontend),\"log_lines\":$log_lines,\"last_error\":\"$last_error\"}"
    else
      local log_lines=0
      [[ -f "$LOG_FILE" ]] && log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ')
      echo "[$(date +%H:%M:%S)] API=$(check_backend) WEB=$(check_frontend) LOGS=$log_lines"
    fi
    sleep "$interval"
  done
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Entry
# ═══════════════════════════════════════════════════════════════════════════

main() {
  if session_exists; then
    error "Session '$SESSION_NAME' already exists"
    echo ""
    echo -e "  ${FG}Attach:${NC}   tmux attach -t $SESSION_NAME"
    echo -e "  ${FG}Kill:${NC}     tmux kill-session -t $SESSION_NAME"
    echo -e "  ${FG}Clean:${NC}    ./dev.sh clean"
    echo -e "  ${FG}Status:${NC}   ./dev.sh status"
    echo ""
    exit 1
  fi

  check_cli >/dev/null 2>&1
  create_session
}

# ═══════════════════════════════════════════════════════════════════════════
# CLI Router
# ═══════════════════════════════════════════════════════════════════════════

CMD="${1:-}"

case "$CMD" in
  clean|--clean)
    cmd_clean
    ;;
  restart|r)
    shift
    cmd_restart "${1:-all}"
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  output|o)
    shift
    cmd_output "${1:-api}" "${2:-50}"
    ;;
  log|l)
    shift
    cmd_log "${1:-50}"
    ;;
  cli)
    shift
    cmd_cli "${1:-basic}" "${2:-}" "${3:-}"
    ;;
  grep|g)
    shift
    cmd_grep "${1:-}" "${2:-50}"
    ;;
  test|t)
    shift
    cmd_test "${1:-seek-basic}"
    ;;
  send|s)
    shift
    cmd_send "${1:-shell}" "${@:2}"
    ;;
  watch|w)
    shift
    cmd_watch "${1:-3}" "${2:-}"
    ;;
  q|exit|quit)
    cmd_clean
    ;;
  "")
    main
    ;;
  *)
    error "Unknown command: $CMD"
    echo ""
    echo "Usage:"
    echo "  ./dev.sh                        Start dev session"
    echo "  ./dev.sh clean                  Kill session + processes"
    echo "  ./dev.sh restart api|web|all    Restart services"
    echo "  ./dev.sh stop                   Stop all panes"
    echo "  ./dev.sh status                 Health checks"
    echo "  ./dev.sh output <pane> [N]      Capture pane output"
    echo ""
    echo "  Panes: api (0), web (1), logs (2), shell (3)"
    echo ""
    echo "CLI (tracked via API):"
    echo "  ./dev.sh cli basic [file]            Run 10s transmux (tracked)"
    echo "  ./dev.sh cli seek [file] [time]      Seek to time, 20s duration"
    echo "  ./dev.sh cli remote <url>            Run with remote URL"
    echo "  ./dev.sh cli stop [session]          Stop session (or first running)"
    echo "  ./dev.sh cli sessions                List all tracked sessions"
    echo "  ./dev.sh cli custom <args>           Raw CLI (untracked)"
    echo ""
    echo "Testing:"
    echo "  ./dev.sh test seek-basic             Seek 300s + 20s duration"
    echo "  ./dev.sh test seek-deep              Seek 600s + 60s duration"
    echo "  ./dev.sh test ac3-init               5s duration for AC3 init"
    echo "  ./dev.sh test remote-sample          First URL from data.json"
    echo "  ./dev.sh test stop-all               Stop all running sessions"
    echo ""
    echo "Debugging:"
    echo "  ./dev.sh grep <tag> [N]              Filter logs (ac3|seek|error...)"
    echo "  ./dev.sh send <pane> <cmd>           Send command to pane"
    echo "  ./dev.sh watch [interval]            Continuous monitoring"
    echo ""
    echo "Config: $ENV_FILE"
    exit 1
    ;;
esac

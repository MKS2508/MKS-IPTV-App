#!/usr/bin/env bash

###
# TransmuxCore Testing Workflow
#
# Crea una sesión tmux con 3 panes para testing completo:
# - Pane 1 (top): Log viewer server (Bun + Elysia)
# - Pane 2 (bottom-left): CLI tests ejecutables
# - Pane 3 (bottom-right): tail -f logs en tiempo real
#
# Uso:
#   ./test-workflow.sh
#
# Comandos útiles dentro de la sesión:
#   - Prefix + z: Zoom en pane activo
#   - Prefix + q: Mostrar números de pane
#   - Prefix + arrow: Navegar entre panes
#   - Prefix + d: Detach de la sesión
###

SESSION="transmux-test"

# Verificar si la sesión ya existe
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "⚠️  Sesión '$SESSION' ya existe"
  echo "Opciones:"
  echo "  1. Attach: tmux attach -t $SESSION"
  echo "  2. Kill:   tmux kill-session -t $SESSION"
  exit 1
fi

# Crear sesión con primer pane
tmux new-session -d -s "$SESSION" -n "transmux-testing"

# Pane 1 (top): Log viewer server
tmux send-keys -t "$SESSION:0.0" "cd $(pwd)" C-m
tmux send-keys -t "$SESSION:0.0" "echo '🚀 Starting Log Viewer Server...'" C-m
tmux send-keys -t "$SESSION:0.0" "bun run dev" C-m

# Split horizontal - crear pane 2 (bottom)
tmux split-window -t "$SESSION:0" -v -p 50

# Split vertical del pane bottom - crear pane 3
tmux split-window -t "$SESSION:0.1" -h -p 50

# Pane 2 (bottom-left): CLI tests
tmux send-keys -t "$SESSION:0.1" "cd /Users/mks/Documents/MKS-IPTV-App/TransmuxCore" C-m
tmux send-keys -t "$SESSION:0.1" "clear" C-m
tmux send-keys -t "$SESSION:0.1" "echo '📦 TransmuxCore CLI Ready'" C-m
tmux send-keys -t "$SESSION:0.1" "echo ''" C-m
tmux send-keys -t "$SESSION:0.1" "echo 'Test Files:'" C-m
tmux send-keys -t "$SESSION:0.1" "ls -lh /Volumes/KODAK1TB/*.mkv 2>/dev/null || echo 'No MKV files found'" C-m
tmux send-keys -t "$SESSION:0.1" "echo ''" C-m
tmux send-keys -t "$SESSION:0.1" "echo 'Commands:'" C-m
tmux send-keys -t "$SESSION:0.1" "echo '  1. Basic: .build/debug/transmux-cli <file> --verbose'" C-m
tmux send-keys -t "$SESSION:0.1" "echo '  2. Seek:  .build/debug/transmux-cli <file> --seek 300 --duration 20 --verbose'" C-m
tmux send-keys -t "$SESSION:0.1" "echo ''" C-m

# Pane 3 (bottom-right): tail logs
tmux send-keys -t "$SESSION:0.2" "clear" C-m
tmux send-keys -t "$SESSION:0.2" "echo '📝 TransmuxCore Logs (tail -f)'" C-m
tmux send-keys -t "$SESSION:0.2" "echo ''" C-m
tmux send-keys -t "$SESSION:0.2" "echo 'Filters:'" C-m
tmux send-keys -t "$SESSION:0.2" "echo '  AC3:    tail -f /tmp/mks-iptv-transmux.log | grep AC3'" C-m
tmux send-keys -t "$SESSION:0.2" "echo '  SEEK:   tail -f /tmp/mks-iptv-transmux.log | grep SEEK'" C-m
tmux send-keys -t "$SESSION:0.2" "echo '  ERROR:  tail -f /tmp/mks-iptv-transmux.log | grep ERROR'" C-m
tmux send-keys -t "$SESSION:0.2" "echo '  ALL:    tail -f /tmp/mks-iptv-transmux.log'" C-m
tmux send-keys -t "$SESSION:0.2" "echo ''" C-m
tmux send-keys -t "$SESSION:0.2" "echo 'Waiting for logs...'" C-m
tmux send-keys -t "$SESSION:0.2" "echo ''" C-m
tmux send-keys -t "$SESSION:0.2" "tail -f /tmp/mks-iptv-transmux.log 2>/dev/null || echo 'Log file will be created when transmux-cli runs'" C-m

# Set focus to CLI pane (pane 1 = bottom-left)
tmux select-pane -t "$SESSION:0.1"

# Attach to session
echo "✅ Sesión '$SESSION' creada"
echo ""
echo "Layout:"
echo "┌─────────────────────────────────────┐"
echo "│  Log Viewer Server (Bun + Elysia)  │"
echo "├──────────────────┬──────────────────┤"
echo "│  CLI Tests       │  tail -f logs    │"
echo "└──────────────────┴──────────────────┘"
echo ""
echo "Web UI: http://localhost:3000"
echo ""
echo "Attaching..."
sleep 2
tmux attach -t "$SESSION"

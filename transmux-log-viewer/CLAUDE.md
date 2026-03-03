# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Transmux Log Viewer** is a web-based testing and debugging tool for the TransmuxCore CLI. It's part of the larger **MKS-IPTV-App** ecosystem.

### Parent Project Structure

```
/Users/mks/Documents/MKS-IPTV-App/
├── TransmuxCore/              # Swift Package - Transmuxing engine
│   ├── Sources/
│   │   ├── TransmuxCore/      # Core library (TransmuxingService, HLSSegmenter, etc.)
│   │   └── transmux-cli/      # CLI tool for testing
│   └── Package.swift
├── transmux-cli/              # CLI wrapper (alternative)
├── mks-multiplatform-iptv/    # Main SwiftUI app (iOS/macOS/tvOS)
├── transmux-log-viewer/       # ← This project (Web UI for testing)
└── docs/                      # Documentation
```

### How It Connects

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TRANSMUX LOG VIEWER (This Project)               │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Frontend (React + Vite)                                        ││
│  │  - Select test source (local file or IPTV URL from data.json)   ││
│  │  - Configure CLI args (--seek, --duration)                      ││
│  │  - Real-time log viewer (SSE)                                   ││
│  │  - HLS.js player preview                                        ││
│  └─────────────────────────────────────────────────────────────────┘│
│                              │ Eden Treaty                          │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Backend (Elysia + Bun)                                         ││
│  │  - SSE streaming from /tmp/mks-iptv-transmux.log                ││
│  │  - CLI execution endpoint                                       ││
│  │  - Log history and filtering                                    ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Executes CLI
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    TRANSMUX CLI (Swift)                             │
│  .build/debug/transmux-cli <input> [--seek TIME] [--verbose]       │
│                                                                     │
│  Output:                                                            │
│  - /tmp/mks-iptv-transmux-<sessionID>/stream.mp4                   │
│  - /tmp/mks-iptv-transmux-<sessionID>/stream.m3u8                  │
│  - /tmp/mks-iptv-transmux.log (logs)                               │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Uses
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    TRANSMUX CORE (Swift Package)                    │
│  - TransmuxingService: Main transmux orchestrator                  │
│  - HLSSegmenter: Generates fMP4 + HLS playlist                     │
│  - AC3 init phase fix: Truncates output after moov generation      │
│  - Timestamp rebasing: Handles seeking with GLOBAL OFFSET          │
└─────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| **Runtime** | Bun | Package manager + runtime |
| **Backend** | Elysia | Type-safe HTTP server |
| **Frontend** | React 19 + Vite 8 | UI with hot reload |
| **Type Safety** | Eden Treaty | E2E typed API client |
| **Logger** | @mks2508/better-logger | Structured logging |
| **Styling** | Tailwind CSS v4 | Utility-first CSS |
| **UI Components** | @mks2508/mks-ui | Component library |
| **Future** | HLS.js | Video playback preview |

## Monorepo Structure

```
transmux-log-viewer/
├── package.json              # Root workspace config
├── tsconfig.json             # Path aliases (@backend/*, @frontend/*)
├── packages/
│   ├── backend/              # Elysia API server
│   │   ├── src/
│   │   │   ├── index.ts      # Main server (exports App type for Eden)
│   │   │   └── modules/
│   │   │       ├── logs/     # SSE streaming, history, clear
│   │   │       └── health/   # Health check
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── frontend/
│       └── mks-iptv-client/  # React + Vite app
│           ├── src/
│           │   ├── lib/
│           │   │   └── api.ts    # Eden Treaty client
│           │   ├── components/
│           │   └── types/
│           ├── public/
│           │   └── data.json     # IPTV test URLs
│           └── package.json
└── data.json                 # IPTV streams for testing (root copy)
```

## Development Commands

### ⚠️ IMPORTANT: Session Management Roles

| Role | Action | Commands |
|------|--------|----------|
| **USER** | Create/destroy session | `./dev.sh`, `./dev.sh clean`, `./dev.sh q` |
| **AGENT** | Interact with existing session | `./dev.sh status`, `./dev.sh restart`, `./dev.sh cli`, etc. |

**The agent NEVER creates sessions.** The agent only interacts with sessions created by the user.

### User Commands (Session Management)

```bash
# 1. Create development session (portless on port 80, requires sudo password)
./dev.sh

# 2. Quick exit from WITHIN tmux session (popup confirmation)
#    Press: Ctrl+b then Shift+Q
#    Confirm with 'y' to kill session

# 3. Exit from OUTSIDE tmux session
./dev.sh q
# Or: ./dev.sh exit, ./dev.sh quit

# 4. Clean up everything (session + processes + portless routes)
./dev.sh clean
```

### Agent Commands (Interaction Only)

```bash
# Check status (use first to verify session exists)
./dev.sh status

# Restart services (NOT the session)
./dev.sh restart api      # or: ./dev.sh restart 0
./dev.sh restart web      # or: ./dev.sh restart 1
./dev.sh restart all

# Stop services (Ctrl+C to all panes)
./dev.sh stop

# CLI testing
./dev.sh cli basic
./dev.sh cli seek 300
./dev.sh test seek-basic

# Log filtering
./dev.sh grep ac3
./dev.sh grep error 50

# Output capture
./dev.sh output api 30    # or: ./dev.sh output 0 30
./dev.sh output shell 50  # or: ./dev.sh output 3 50
```

### URLs (Portless Mode - Default)

| Service | URL |
|---------|-----|
| Frontend | `http://transmux-app.localhost` |
| Backend | `http://transmux-api.localhost` |

### tmux Session Layout

The `dev.sh` script creates a tmux session with 4 panes and a custom status bar:

| Index | Name | Purpose | URL/Path |
|-------|------|---------|----------|
| 0 | `api` | Elysia Backend | `http://transmux-api.localhost` |
| 1 | `web` | Vite Frontend | `http://transmux-app.localhost` |
| 2 | `logs` | Log tail | `/tmp/mks-iptv-transmux.log` |
| 3 | `shell` | CLI + Tests | TransmuxCore CLI |

**Navigation:**
- `Ctrl+b 0-3` — Jump to pane by index
- `Ctrl+b arrows` — Navigate between panes
- `Ctrl+b Q` — Exit session (popup confirmation)

**Status Bar (bottom):** Shows mode (portless), exit shortcut, and time.

### Individual Package Commands

```bash
# Individual packages (if not using tmux)
bun run dev:backend   # http://localhost:3000
bun run dev:frontend  # http://localhost:5173

# Build, lint, format
bun run build
bun run typecheck
bun run lint
bun run format
```

## TransmuxCore CLI Integration

### Building the CLI

```bash
cd /Users/mks/Documents/MKS-IPTV-App/TransmuxCore
swift build --product transmux-cli
```

### CLI Usage

```bash
# Basic transmux
.build/arm64-apple-macosx/debug/transmux-cli "/path/to/video.mkv" --verbose

# Test seeking (critical for VOD performance)
.build/arm64-apple-macosx/debug/transmux-cli "/path/to/video.mkv" --seek 300 --duration 20 --verbose

# Remote URL
.build/arm64-apple-macosx/debug/transmux-cli "http://example.com/stream.mkv" --verbose
```

### CLI Output

- **Logs**: `/tmp/mks-iptv-transmux.log`
- **Stream**: `/tmp/mks-iptv-transmux-<sessionID>/stream.mp4`
- **Playlist**: `/tmp/mks-iptv-transmux-<sessionID>/stream.m3u8`

### Log Format

```
[TIMESTAMP] [TAG] Message
```

**Tags**: SERVICE, REMUX, SEGMENTER, AC3, SEEK, OFFSET, DTS, ERROR
**Levels**: ERROR, WARN, INFO, DEBUG

## Test Data Sources

### Local Files (`/Volumes/KODAK1TB/`)

- `Crímenes Bellvitge (2026) 1x03.mkv` (1.8GB) - Primary test file
- `Crímenes Bellvitge (2026) 1x01.mp4`
- `Crímenes Bellvitge (2026) 1x02.mp4`
- `FBI 1080P S63E04.mp4`
- Other MKV/MP4 files

### IPTV URLs (`data.json`)

JSON array with stream objects:
```typescript
interface IStreamSource {
  category: string;           // e.g., "ESTRENOS (BDRip 1080 dual AC3)"
  containerExtension: string; // "mkv" | "mp4"
  id: string;                 // "movie_311368"
  name: string;               // "De las cenizas: Bajo tierra"
  streamId: number;           // 311368
  type: "movie" | "series";
  url: string;                // HTTP stream URL
}
```

## Development Rules

### JSDoc (Required)

All exported functions, classes, interfaces, and types must have JSDoc comments.

### Logging

Use `@mks2508/better-logger` exclusively. Never use `console.log/warn/error/debug`.

### Result Pattern

For operations that can fail, use `Result<T, E>` from `@mks2508/no-throw`.

### Naming Conventions

- Interfaces: `ILogEntry`, `IStreamSource` (prefix `I`)
- Types: `LogLevel` (no prefix)

### Barrel Exports

Every directory with multiple files must have an `index.ts` barrel export.

## Related Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| CLI Testing Plan | `../CLI-TESTING-PLAN.md` | Detailed testing workflow |
| TransmuxCore Summary | `../TRANSMUX-CORE-SUMMARY.md` | Architecture overview |
| Integration Guide | `../INTEGRATION-GUIDE.md` | Xcode integration steps |
| TransmuxCore README | `../TransmuxCore/README.md` | Swift package docs |

## Working with tmux Session

### Pane Usage for AI Agents

```bash
# Execute commands in specific panes
tmux send-keys -t transmux-dev:0.0 "command" Enter  # API pane
tmux send-keys -t transmux-dev:0.1 "command" Enter  # Web pane
tmux send-keys -t transmux-dev:0.2 "command" Enter  # Logs pane
tmux send-keys -t transmux-dev:0.3 "command" Enter  # Shell pane

# Capture output from panes
tmux capture-pane -t transmux-dev:0.0 | tail -20  # API output
tmux capture-pane -t transmux-dev:0.2 | tail -50  # Log output (most used)
tmux capture-pane -t transmux-dev:0.3 | tail -10  # Shell output

# Monitor development in background
nohup tmux capture-pane -t transmux-dev:0.2 > /tmp/tmux-log-output.txt &
tail -f /tmp/tmux-log-output.txt  # Continuous log monitoring
```

### Key Panes for Development

- **Pane 0 (api)**: Elysia server logs, health checks
- **Pane 1 (web)**: Vite dev server, build output
- **Pane 2 (logs)**: **PRIMARY PANE** - Real-time TransmuxCore CLI logs
- **Pane 3 (shell)**: Execute TransmuxCore CLI with various test files

### Session Management

```bash
# List all panes in session
tmux list-panes -t transmux-dev -F "#{pane_index}:#{pane_current_command}:#{pane_title}"

# Switch between panes (tmux shortcuts)
Ctrl+b o    # Select pane
Ctrl+b 0-3   # Select pane by index
Ctrl+b arrow  # Navigate panes

# Detach from session (returns to your terminal)
Ctrl+b d
```

---

## Debugging Workflow (Human + Agent Collaboration)

### ⚠️ CRITICAL: Roles and Responsibilities

```
┌─────────────────────────────────────────────────────────────────┐
│  USER (Human)                                                   │
│  - Creates tmux session with ./dev.sh                          │
│  - Destroys session with ./dev.sh clean or ./dev.sh q          │
│  - Watches real-time logs in tmux pane 2 (Log Tail)            │
│  - Reviews agent findings and decides next steps               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Session exists
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AGENT (Claude)                                                 │
│  - Verifies session with ./dev.sh status                       │
│  - Runs tests with ./dev.sh cli/test                           │
│  - Filters logs with ./dev.sh grep                             │
│  - Captures output with ./dev.sh output                        │
│  - Restarts services with ./dev.sh restart                     │
│  - NEVER creates or destroys sessions                          │
└─────────────────────────────────────────────────────────────────┘
```

### Quick Reference - Agent Commands

| Command | Description |
|---------|-------------|
| `./dev.sh status` | Check services health (ALWAYS run first) |
| `./dev.sh cli basic` | Basic transmux (10s) |
| `./dev.sh cli seek 300` | Seek test at 5min |
| `./dev.sh grep ac3` | Filter AC3 logs |
| `./dev.sh grep error 100` | Last 100 errors |
| `./dev.sh test seek-basic` | Run preset test |
| `./dev.sh send shell "cmd"` | Send command to shell pane |
| `./dev.sh output api 30` | Capture API output |
| `./dev.sh restart api` | Restart API service |
| `./dev.sh watch 5` | Continuous monitoring |
| `./dev.sh q` | Quick exit (from outside session) |

### CLI Shortcuts (`./dev.sh cli`)

```bash
# Basic transmux (10 seconds)
./dev.sh cli basic                     # Uses PRIMARY_TEST_FILE
./dev.sh cli basic "/path/to/file.mkv" # Custom file

# Seek testing (CRITICAL for VOD)
./dev.sh cli seek                      # Seek to 300s (5min), duration 20s
./dev.sh cli seek "/path/file.mkv" 600 # Seek to 600s (10min)

# Remote URL testing
./dev.sh cli remote "http://example.com/stream.mkv"

# Custom arguments
./dev.sh cli custom "/path/file.mkv" --seek 120 --duration 30 --verbose
```

### Log Filtering (`./dev.sh grep`)

```bash
# Available tags:
./dev.sh grep ac3      # AC3 init phase (delay_moov handling)
./dev.sh grep seek     # Seek operations (timestamp rebasing)
./dev.sh grep remux    # Remux operations
./dev.sh grep segment  # Segmenter (fMP4 + HLS generation)
./dev.sh grep error    # All errors
./dev.sh grep warn     # Warnings
./dev.sh grep dts      # DTS timestamps (sync verification)
./dev.sh grep offset   # Timestamp offsets (GLOBAL OFFSET)

# With line count:
./dev.sh grep seek 100   # Last 100 seek-related logs
./dev.sh grep error 200  # Last 200 errors
```

### Preset Tests (`./dev.sh test`)

| Preset | Description | Use Case |
|--------|-------------|----------|
| `seek-basic` | Seek 300s + 20s duration | Quick seek validation |
| `seek-deep` | Seek 600s + 60s duration | Deep seek testing |
| `ac3-init` | Duration 5s only | AC3 init phase capture |
| `remote-sample` | First URL from data.json | Remote streaming test |

```bash
./dev.sh test seek-basic    # Quick seek test
./dev.sh test seek-deep     # Extended seek test
./dev.sh test ac3-init      # Capture AC3 init quickly
./dev.sh test remote-sample # Test with remote URL
```

### Sending Commands (`./dev.sh send`)

```bash
# Send to specific pane (use name or index)
./dev.sh send shell "ls -la"         # List files in shell pane
./dev.sh send api "clear"            # Clear API pane
./dev.sh send logs "tail -20"        # Custom log command

# Pane names: api (0), web (1), logs (2), shell (3)
```

### Continuous Monitoring (`./dev.sh watch`)

```bash
# Human-readable output (every 3 seconds)
./dev.sh watch

# Custom interval
./dev.sh watch 5

# JSON output for agents/scripts
./dev.sh watch --json 2

# Example JSON output:
# {"timestamp":"2025-01-15T10:30:00-03:00","backend":1,"frontend":1,"log_lines":1234,"last_error":"..."}
```

---

## Standard Debugging Workflow

### Scenario 1: Seek Testing (Primary Use Case)

```bash
# 1. Start session (human)
./dev.sh

# 2. Check status (agent)
./dev.sh status

# 3. Run seek test (agent)
./dev.sh test seek-basic

# 4. Monitor logs (agent)
./dev.sh grep seek 20     # Seek operations
./dev.sh grep dts 20      # DTS timestamps
./dev.sh grep error 10    # Any errors

# 5. If issues, capture full output
./dev.sh output cli 50

# 6. Human watches real-time in tmux pane 2 (Log Tail)
```

### Scenario 2: AC3 Init Phase Debugging

```bash
# 1. Run short test to capture init
./dev.sh test ac3-init

# 2. Filter AC3 logs
./dev.sh grep ac3 30

# 3. Check for errors
./dev.sh grep error

# 4. Verify DTS values
./dev.sh grep dts
```

### Scenario 3: Remote URL Testing

```bash
# 1. Test with sample URL from data.json
./dev.sh test remote-sample

# 2. Or specify custom URL
./dev.sh cli remote "http://..."

# 3. Monitor for network/remux errors
./dev.sh grep error
./dev.sh grep remux
```

### Scenario 4: Agent Continuous Monitoring

```bash
# Start monitoring in background
./dev.sh watch --json > /tmp/transmux-monitor.json &

# Agent can read status periodically
tail -1 /tmp/transmux-monitor.json | jq '.'

# Or watch in foreground
./dev.sh watch 3
```

---

## Direct tmux Commands for Agents

When `./dev.sh` shortcuts aren't enough:

```bash
# Send command to specific pane
tmux send-keys -t transmux-dev:0.3 "command" Enter

# Capture pane output
tmux capture-pane -t transmux-dev:0.2 | tail -50

# Pane indices: 0=api, 1=web, 2=logs, 3=shell

# Check if session exists
tmux has-session -t transmux-dev 2>/dev/null && echo "exists" || echo "not found"

# Kill specific pane command (Ctrl+C)
tmux send-keys -t transmux-dev:0.3 C-c
```

---

## Log File Reference

**Location**: `/tmp/mks-iptv-transmux.log`

**Format**: `[HH:mm:ss.SSS] [LEVEL] [TAG] Message`

**Tags**:
- `SERVICE` - TransmuxingService lifecycle
- `REMUX` - FFmpeg remux operations
- `SEGMENTER` - HLS/fMP4 generation
- `AC3` - AC3/EAC3 handling (delay_moov)
- `SEEK` - Seek operations
- `OFFSET` - Timestamp rebasing (GLOBAL OFFSET)
- `DTS` - DTS timestamps for A/V sync
- `ERROR` - Errors
- `WARN` - Warnings

**Levels**: `DBG`, `INF`, `WRN`, `ERR`

**Example**:
```
[10:30:45.123] [INF] [SEEK] Seeking to 300.0 seconds
[10:30:45.456] [DBG] [OFFSET] GLOBAL OFFSET: -300.0
[10:30:45.789] [INF] [AC3] AC3 init phase completed
```

## Future Features

1. **CLI Execution API**: Endpoint to run transmux-cli with selected source
2. **HLS.js Player**: Preview of generated HLS stream
3. **Seek Testing UI**: Interactive seek controls
4. **Session Management**: Multiple concurrent transmux sessions
5. **Stats Dashboard**: Real-time metrics (errors, seeks, DTS values)

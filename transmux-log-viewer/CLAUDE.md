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

### Using tmux Session (Recommended)

```bash
# Main development command (idempotent)
bun run dev

# Clean all tmux sessions and processes
bun run dev:clean
```

The `dev.sh` script creates an idempotent tmux session with 4 split panes:

- **Backend (top-left)**: Runs on port 3000
- **Frontend (top-right)**: Runs on port 5173  
- **Log Tail (bottom-left)**: Real-time log viewer
- **CLI/Tests (bottom-right)**: TransmuxCore CLI execution and testing

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

## Working with the tmux Session

### For AI Agents/External Control

```bash
# Attach to existing session
tmux attach -t transmux-dev

# Execute commands in specific panes
tmux send-keys -t transmux-dev:0.0 "command" Enter  # Backend pane
tmux send-keys -t transmux-dev:0.1 "command" Enter  # Frontend pane
tmux send-keys -t transmux-dev:0.2 "command" Enter  # Log tail pane
tmux send-keys -t transmux-dev:0.3 "command" Enter  # CLI/Tests pane

# Capture output from panes
tmux capture-pane -t transmux-dev:0.0 | tail -10  # Backend output
tmux capture-pane -t transmux-dev:0.2 | tail -20  # Log output
tmux capture-pane -t transmux-dev:0.3 | tail -10  # CLI output

# List all windows/panes
tmux list-windows -t transmux-dev
tmux list-panes -t transmux-dev
```

### Session Layout Reference

```
Pane Index:   Pane Index:   Window Name:
─────────────────────────────────────────────
0.0           Backend      dev:0
0.1           Frontend     dev:0
0.2           Log Tail     dev:0
0.3           CLI/Tests    dev:0
```

### Monitoring and Verification

```bash
# Verify services are running
curl -s http://localhost:3000/health  # Backend health
curl -s http://localhost:5173             # Frontend

# Check log file directly
tail -f /tmp/mks-iptv-transmux.log

# Test CLI from tests pane
/Users/mks/Documents/MKS-IPTV-App/TransmuxCore/.build/arm64-apple-macosx/debug/transmux-cli "/Volumes/KODAK1TB/test.mkv" --verbose
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
tmux send-keys -t transmux-dev:0.0 "bun run dev:backend" Enter     # Backend pane
tmux send-keys -t transmux-dev:0.1 "bun run dev:frontend" Enter    # Frontend pane
tmux send-keys -t transmux-dev:0.2 "tail -f /tmp/mks-iptv-transmux.log" Enter  # Log tail pane
tmux send-keys -t transmux-dev:0.3 "cd /Users/mks/Documents/MKS-IPTV-App/TransmuxCore" Enter  # CLI/Tests pane

# Capture output from panes
tmux capture-pane -t transmux-dev:0.0 | tail -20  # Backend output
tmux capture-pane -t transmux-dev:0.2 | tail -50  # Log output (most used)
tmux capture-pane -t transmux-dev:0.3 | tail -10  # CLI output

# Monitor development in background
nohup tmux capture-pane -t transmux-dev:0.2 > /tmp/tmux-log-output.txt &
tail -f /tmp/tmux-log-output.txt  # Continuous log monitoring
```

### Key Panes for Development

- **Pane 0.0 (Backend)**: API server logs, health checks
- **Pane 0.1 (Frontend)**: Vite dev server, build output
- **Pane 0.2 (Log Tail)**: **PRIMARY PANE** - Real-time TransmuxCore CLI logs
- **Pane 0.3 (CLI/Tests)**: Execute TransmuxCore CLI with various test files

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

## Future Features

1. **CLI Execution API**: Endpoint to run transmux-cli with selected source
2. **HLS.js Player**: Preview of generated HLS stream
3. **Seek Testing UI**: Interactive seek controls
4. **Session Management**: Multiple concurrent transmux sessions
5. **Stats Dashboard**: Real-time metrics (errors, seeks, DTS values)

# AGENTS.md

Guide for AI agents working in the Transmux Log Viewer codebase.

## Project Overview

**Transmux Log Viewer** is a web-based testing and debugging tool for the TransmuxCore CLI (Swift). It's part of the larger **MKS-IPTV-App** ecosystem.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Frontend (React + Vite)                                        │
│  - Real-time log viewer (SSE)                                   │
│  - HLS.js player preview                                        │
│  - Source selection (local files / IPTV URLs)                   │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Eden Treaty (E2E typed API)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Backend (Elysia + Bun)                                         │
│  - SSE streaming from /tmp/mks-iptv-transmux.log                │
│  - CLI execution and session management                         │
│  - HLS serving (fMP4 + m3u8)                                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Spawns CLI process
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  TransmuxCore CLI (Swift)                                       │
│  Location: ../TransmuxCore/.build/.../debug/transmux-cli        │
│  Output: /tmp/mks-iptv-transmux-<sessionID>/                    │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| **Runtime** | Bun | Package manager + runtime |
| **Backend** | Elysia | Type-safe HTTP server |
| **Frontend** | React 19 + Vite 8 | UI with hot reload |
| **Type Safety** | Eden Treaty | E2E typed API client |
| **Logger** | @mks2508/better-logger | Structured logging |
| **Linter/Formatter** | Biome | Code quality |
| **Styling** | Tailwind CSS v4 | Utility-first CSS |
| **UI Components** | @mks2508/mks-ui | Component library |

## Monorepo Structure

```
transmux-log-viewer/
├── package.json              # Root workspace config
├── tsconfig.json             # Path aliases (@backend/*, @frontend/*)
├── biome.json                # Linter/formatter config
├── dev.sh                    # tmux dev session script
├── data.json                 # IPTV streams for testing
└── packages/
    ├── backend/              # Elysia API server
    │   ├── src/
    │   │   ├── index.ts      # Main server (exports App type for Eden)
    │   │   └── modules/
    │   │       ├── logs/     # SSE streaming, history, clear
    │   │       ├── health/   # Health check
    │   │       ├── cli/      # CLI execution, session management
    │   │       ├── hls/      # HLS file serving
    │   │       └── sources/  # Test data endpoints
    │   └── package.json
    └── frontend/
        └── mks-iptv-client/  # React + Vite app
            ├── src/
            │   ├── lib/
            │   │   └── api.ts     # Eden Treaty client
            │   ├── hooks/         # useLogStream, useCLISession, useHLSPlayer
            │   ├── components/    # LogViewer, HLSPlayer, SourcePanel
            │   └── types/         # ILogEntry, IStreamSource, etc.
            └── package.json
```

## Development Commands

### Session Management (User Role)

| Command | Description |
|---------|-------------|
| `./dev.sh` | Start dev session (portless on port 80, requires sudo) |
| `./dev.sh clean` | Kill session and cleanup |
| `./dev.sh q` | Quick exit from outside session |

### Interaction Commands (Agent Role)

| Command | Description |
|---------|-------------|
| `./dev.sh status` | Check services health (ALWAYS run first) |
| `./dev.sh restart api` | Restart backend service |
| `./dev.sh restart web` | Restart frontend service |
| `./dev.sh restart all` | Restart all services |
| `./dev.sh stop` | Send Ctrl+C to all panes |
| `./dev.sh output <pane> [N]` | Capture pane output (api/web/logs/shell or 0/1/2/3) |
| `./dev.sh cli basic` | Basic transmux test (10s) |
| `./dev.sh cli seek 300` | Seek test at 5min |
| `./dev.sh test seek-basic` | Run preset test |
| `./dev.sh grep ac3` | Filter AC3 logs |
| `./dev.sh grep error 50` | Last 50 errors |

### Package Commands

```bash
# Individual packages (if not using tmux)
bun run dev:backend   # http://localhost:3000
bun run dev:frontend  # http://localhost:5173

# Build, typecheck, lint
bun run build         # Build all packages
bun run typecheck     # Type-check all packages
bun run lint          # Biome check (specific paths)
bun run format        # Biome format --write
bun run check         # Biome check --write
```

### URLs (Portless Mode - Default)

| Service | URL |
|---------|-----|
| Frontend | `http://transmux-app.localhost` |
| Backend | `http://transmux-api.localhost` |

## Code Patterns

### Backend (Elysia)

**Module Structure:**
```typescript
// modules/example/index.ts
import { Elysia } from "elysia";
import { exampleModels } from "./model";
import { ExampleService } from "./service";

export const exampleModule = new Elysia({ prefix: "/example" })
  .decorate("exampleService", new ExampleService())
  .model(exampleModels)
  .get("/endpoint", ({ exampleService }) => exampleService.getData(), {
    response: { 200: "ExampleResponse" },
    detail: { summary: "Description", tags: ["example"] }
  });
```

**Service Pattern:**
```typescript
// modules/example/service.ts
import logger from "@mks2508/better-logger";

const serviceLog = logger.component("ExampleService");

export class ExampleService {
  async getData(): Promise<IExampleData> {
    serviceLog.info("Fetching data");
    // Implementation
  }
}
```

**Model Pattern (TypeBox):**
```typescript
// modules/example/model.ts
import { t } from "elysia";

export interface IExampleData {
  id: string;
  name: string;
}

export const exampleModels = {
  ExampleResponse: t.Object({
    id: t.String(),
    name: t.String(),
  }),
};
```

### Frontend (React)

**Eden Treaty Client:**
```typescript
// src/lib/api.ts
import type { App } from "@backend/index";
import { treaty } from "@elysiajs/eden";

const API_BASE = import.meta.env.VITE_API_URL || "http://localhost:3000";
export const api = treaty<App>(API_BASE);

// Usage:
const { data, error } = await api.logs.history.get();
```

**Hook Pattern:**
```typescript
// src/hooks/useExample.ts
import { useState, useEffect, useRef, useCallback } from "react";

export function useExample() {
  const [state, setState] = useState(initialState);
  const refRef = useRef<Type>(initial);

  useEffect(() => {
    // Mount logic
    return () => {
      // Cleanup
    };
  }, []); // Stable deps

  const action = useCallback(() => {
    // Action logic
  }, []);

  return { state, action };
}
```

**Component Pattern:**
```typescript
// src/components/Example.tsx
import { useLogStream } from "@/hooks";

export function Example() {
  const { logs, connected } = useLogStream();

  return (
    <div className="...">
      {/* JSX */}
    </div>
  );
}
```

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Interfaces | `IPrefix` | `ILogEntry`, `IStreamSource` |
| Types | `PascalCase` | `LogLevel`, `SessionStatus` |
| Components | `PascalCase` | `LogViewer`, `SourcePanel` |
| Hooks | `usePascalCase` | `useLogStream`, `useCLISession` |
| Services | `PascalCase` | `LogService`, `CLIService` |
| Modules | `camelCase` | `logsModule`, `cliModule` |
| Files | `kebab-case.ts` | `log-viewer.tsx`, `use-log-stream.ts` |

## Development Rules

### JSDoc (Required)

All exported functions, classes, interfaces, and types must have JSDoc comments:

```typescript
/**
 * Description of the function/class/interface
 *
 * @param paramName - Description of parameter
 * @returns Description of return value
 *
 * @example
 * ```typescript
 * const result = functionName(arg);
 * ```
 */
```

### Logging

Use `@mks2508/better-logger` exclusively. Never use `console.log/warn/error/debug`:

```typescript
import logger from "@mks2508/better-logger";

const log = logger.component("ComponentName");
log.info("Message");
log.error("Error message", { error });
log.debug("Debug info", { data });
```

### Result Pattern

For operations that can fail, use `Result<T, E>` from `@mks2508/no-throw`:

```typescript
import { Result } from "@mks2508/no-throw";

type OperationResult = Result<ISuccessData, IError>;
```

### Barrel Exports

Every directory with multiple files must have an `index.ts` barrel export:

```typescript
// src/hooks/index.ts
export { useLogStream } from "./useLogStream";
export { useCLISession } from "./useCLISession";
export { useHLSPlayer } from "./useHLSPlayer";
```

### Path Aliases

Configured in root `tsconfig.json`:

| Alias | Path |
|-------|------|
| `@backend/*` | `./packages/backend/src/*` |
| `@frontend/*` | `./packages/frontend/mks-iptv-client/src/*` |
| `@/*` (frontend only) | `./src/*` |

## Biome Configuration

From `biome.json`:

- **Indent**: 2 spaces
- **Line width**: 100 characters
- **Quotes**: Double quotes
- **Semicolons**: Always
- **Trailing commas**: ES5

Key lint rules:
- `noUnusedImports`: error
- `noUnusedVariables`: warn
- `noNonNullAssertion`: off
- `noExplicitAny`: off

## TransmuxCore CLI Integration

### CLI Location

```
../TransmuxCore/.build/arm64-apple-macosx/debug/transmux-cli
```

### CLI Output

- **Logs**: `/tmp/mks-iptv-transmux.log`
- **Stream**: `/tmp/mks-iptv-transmux-<sessionID>/stream.mp4`
- **Playlist**: `/tmp/mks-iptv-transmux-<sessionID>/stream.m3u8`

### Log Format

```
[HH:mm:ss.SSS] [LEVEL] [TAG] Message
```

**Levels**: `DBG`, `INF`, `WRN`, `ERR`
**Tags**: `SERVICE`, `REMUX`, `SEGMENTER`, `AC3`, `SEEK`, `OFFSET`, `DTS`, `ERROR`, `SESSION`

### Session Modes

| Mode | Description | CLI Flag |
|------|-------------|----------|
| `interactive` | Accepts SEEK/STOP commands via stdin | `--interactive` |
| `seek` | One-shot seek mode, no stdin | `--seek <time>` |
| `test-seek` | Self-terminating test mode | `--test-seek <time>` |

## Test Data Sources

### Local Files

Located at `/Volumes/KODAK1TB/` - MKV/MP4 files for testing.

### IPTV URLs

Located in `data.json` (root) with structure:

```typescript
interface IStreamSource {
  category: string;
  containerExtension: "mkv" | "mp4" | "avi" | "m4v";
  id: string;
  name: string;
  streamId: number;
  type: "movie" | "series";
  url: string;
}
```

## tmux Session Layout

The `dev.sh` script creates a tmux session with 4 panes:

| Index | Name | Purpose |
|-------|------|---------|
| 0 | `api` | Elysia Backend |
| 1 | `web` | Vite Frontend |
| 2 | `logs` | Log tail (`/tmp/mks-iptv-transmux.log`) |
| 3 | `shell` | CLI + Tests |

**Navigation:**
- `Ctrl+b 0-3` — Jump to pane by index
- `Ctrl+b arrows` — Navigate between panes
- `Ctrl+b Q` — Exit session (popup confirmation)

## Important Gotchas

### Tailwind v4 Consumer Setup

`@mks2508/mks-ui` ships compiled JS with Tailwind class strings. Tailwind v4's `@tailwindcss/vite` plugin does not scan `node_modules` by default.

Required in `src/index.css`:
```css
@source "../node_modules/@mks2508/mks-ui/dist";
```

### SSE Connection

The frontend uses native `EventSource` for SSE, not Eden Treaty streaming. The `useLogStream` hook handles:
- Auto-reconnect with exponential backoff
- Buffer management (max 5000 entries)
- Incremental stats calculation

### CLI Session Management

The `CLIService` class manages CLI processes:
- Sessions are keyed by UUID from CLI output
- Initial session IDs are `pending-<pid>` until CLI reports actual UUID
- Log file watcher is used to capture session metadata
- Interactive mode supports SEEK/STOP commands via stdin

### Portless Mode

Default development uses portless (port 80) with `.localhost` domains:
- Requires `sudo` password on first run
- Backend: `http://transmux-api.localhost`
- Frontend: `http://transmux-app.localhost`

Environment variables are set by `dev.sh`:
- `PORT` — Backend port
- `VITE_API_URL` — Frontend API URL

## Agent Workflow

### Role Separation

| Role | Actions |
|------|---------|
| **USER** | Create/destroy session (`./dev.sh`, `./dev.sh clean`, `./dev.sh q`) |
| **AGENT** | Interact with existing session (`./dev.sh status`, `./dev.sh restart`, etc.) |

**The agent NEVER creates sessions.** Always verify session exists with `./dev.sh status` first.

### Debugging Workflow

```bash
# 1. Verify session (agent)
./dev.sh status

# 2. Run test
./dev.sh test seek-basic

# 3. Monitor logs
./dev.sh grep seek 20
./dev.sh grep error 10

# 4. Capture output if needed
./dev.sh output logs 50
```

### Direct tmux Commands

When `./dev.sh` shortcuts aren't enough:

```bash
# Send command to pane
tmux send-keys -t transmux-dev:0.3 "command" Enter

# Capture pane output
tmux capture-pane -t transmux-dev:0.2 | tail -50

# Check if session exists
tmux has-session -t transmux-dev 2>/dev/null && echo "exists" || echo "not found"
```

import { type Stats, watch } from "node:fs";
import { stat } from "node:fs/promises";
import logger from "@mks2508/better-logger";
import type { IActiveSession, SessionMode, SessionStatus } from "./model";

const cliLog = logger.component("CLIService");

/** Map of session ID -> log file watcher close function */
type WatcherHandle = {
  close: () => void;
  lastSize: number;
};

/**
 * Path to the TransmuxCore CLI executable
 */
const TRANSMUX_CLI_PATH =
  "/Volumes/KODAK1TB/MKS-IPTV-App/TransmuxCore/.build/arm64-apple-macosx/debug/transmux-cli";

/** Log file written by TransmuxCore CLI */
const LOG_FILE_PATH = "/tmp/mks-iptv-transmux.log";

/**
 * Service for managing TransmuxCore CLI execution
 *
 * Handles spawning CLI processes, parsing stdout for session info,
 * tracking active sessions, and stopping sessions.
 *
 * CLI stdout format (with emoji prefixes):
 * ```
 * ✅ Transmux started: <sessionID>
 *    📦 Output: <outputPath>
 *    📋 Playlist: <playlistPath>
 *    🎞️  Init segment: <bytes> bytes
 *    ⏱️  Duration: <seconds>s
 * ```
 *
 * @example
 * ```typescript
 * const service = new CLIService();
 * const session = await service.runCLI({ input: "/path/to/video.mkv", duration: 10 });
 * const sessions = service.getSessions();
 * await service.stopSession(session.sessionId);
 * ```
 */
export class CLIService {
  private sessions: Map<string, IActiveSession> = new Map();
  private processes: Map<string, ReturnType<typeof Bun.spawn>> = new Map();
  private logWatchers: Map<string, WatcherHandle> = new Map();
  private pollTimers: Map<string, ReturnType<typeof setInterval>> = new Map();

  /**
   * Run the TransmuxCore CLI with the given options
   *
   * Spawns the CLI process, parses stdout for session metadata,
   * and tracks the session in the active sessions map.
   *
   * @param opts - CLI execution options
   * @param opts.input - Input file path or URL
   * @param opts.seek - Seek time in seconds (default: 0)
   * @param opts.duration - Duration in seconds (default: 10)
   * @param opts.verbose - Enable verbose logging (default: true)
   * @returns The active session info
   */
  async runCLI(opts: {
    input: string;
    seek?: number;
    duration?: number;
    verbose?: boolean;
    testSeek?: number;
  }): Promise<IActiveSession> {
    const { input, seek = 0, duration = 10, verbose = true, testSeek } = opts;

    const args = [TRANSMUX_CLI_PATH, input];

    // Determine session mode based on arguments
    let mode: SessionMode;
    if (testSeek != null && testSeek > 0) {
      // Self-terminating test mode — no interactive
      args.push("--test-seek", String(testSeek));
      args.push("--duration", String(duration));
      mode = "test-seek";
    } else if (seek > 0) {
      // One-shot seek mode
      args.push("--seek", String(seek));
      args.push("--duration", String(duration));
      mode = "seek";
    } else {
      // Interactive mode — backend manages lifecycle via stdin commands
      args.push("--interactive");
      mode = "interactive";
    }

    if (verbose) {
      args.push("--verbose");
    }

    cliLog.info(`Spawning CLI: ${args.join(" ")}`);

    const proc = Bun.spawn(args, {
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env },
    });

    const tempSessionId = `pending-${proc.pid}`;
    const session: IActiveSession = {
      sessionId: tempSessionId,
      pid: proc.pid,
      input,
      outputPath: "",
      playlistPath: "",
      initSegmentSize: 0,
      duration,
      mode,
      status: "running",
      startedAt: new Date().toISOString(),
    };

    this.sessions.set(tempSessionId, session);
    this.processes.set(tempSessionId, proc);

    // Parse stdout asynchronously for session metadata
    this.parseStdout(proc, session);

    // Read stderr for error reporting
    this.readStderr(proc, session);

    // Watch log file for session metadata (CLI writes to log, not stdout)
    this.watchLogFile(session);

    // Monitor process exit
    this.monitorProcess(proc, session);

    return session;
  }

  /**
   * Stop an active CLI session
   *
   * Sends STOP command via stdin (for interactive mode graceful shutdown),
   * then kills the process as a fallback.
   *
   * @param sessionId - Session ID to stop
   * @returns Success/error result
   */
  async stopSession(sessionId: string): Promise<{ success: boolean; message: string }> {
    const proc = this.processes.get(sessionId);

    if (!proc) {
      cliLog.warn(`Session not found: ${sessionId}`);
      return { success: false, message: `Session not found: ${sessionId}` };
    }

    try {
      // Send STOP via stdin for graceful shutdown in interactive mode
      this.writeToStdin(sessionId, "STOP");

      // Kill after short grace period
      setTimeout(() => {
        try {
          proc.kill();
        } catch {
          // Process may have already exited
        }
      }, 500);

      this.updateSessionStatus(sessionId, "killed");
      this.cleanupWatcher(sessionId);
      cliLog.info(`Killed session: ${sessionId}`);
      return { success: true, message: `Session ${sessionId} killed` };
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      cliLog.error(`Failed to kill session ${sessionId}: ${msg}`);
      return { success: false, message: msg };
    }
  }

  /**
   * Send a seek command to an active interactive CLI session
   *
   * Writes `SEEK <time>` to the process stdin. The CLI reads this and
   * calls `session.seekHandle.requestSeek(to:)` in TransmuxCore.
   *
   * @param sessionId - Session ID to seek
   * @param time - Target time in seconds
   * @returns Success/error result
   */
  async seekSession(
    sessionId: string,
    time: number
  ): Promise<{ success: boolean; message: string }> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return { success: false, message: `Session not found: ${sessionId}` };
    }

    if (session.status !== "running") {
      return { success: false, message: `Session ${sessionId} is not running (status: ${session.status})` };
    }

    if (session.mode !== "interactive") {
      return {
        success: false,
        message: `Seek requires interactive mode (session ${sessionId} is in "${session.mode}" mode)`,
      };
    }

    const written = this.writeToStdin(sessionId, `SEEK ${time}`);
    if (!written) {
      return { success: false, message: `Failed to write to stdin for session ${sessionId}` };
    }

    cliLog.info(`Seek command sent: session=${sessionId} time=${time}s`);
    return { success: true, message: `Seek to ${time}s requested` };
  }

  /**
   * Write a command line to a process's stdin
   *
   * @param sessionId - Session whose process to write to
   * @param command - Command string (newline appended automatically)
   * @returns Whether the write succeeded
   */
  private writeToStdin(sessionId: string, command: string): boolean {
    const proc = this.processes.get(sessionId);
    if (!proc) return false;

    try {
      const stdin = (proc as any).stdin;
      if (stdin && typeof stdin.write === "function") {
        stdin.write(`${command}\n`);
        if (typeof stdin.flush === "function") {
          stdin.flush();
        }
        return true;
      }
      cliLog.warn(`No stdin pipe for session ${sessionId}`);
      return false;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      cliLog.error(`stdin write error for ${sessionId}: ${msg}`);
      return false;
    }
  }

  /**
   * Get all tracked sessions (active and completed)
   *
   * @returns Array of all session info objects
   */
  getSessions(): { sessions: IActiveSession[]; count: number } {
    const sessions = Array.from(this.sessions.values());
    return { sessions, count: sessions.length };
  }

  /**
   * Parse CLI stdout for session metadata
   *
   * Reads stdout line by line, extracting session ID, output paths,
   * init segment size, and duration. Handles emoji-prefixed output
   * from the Swift CLI.
   *
   * @param proc - The spawned process
   * @param session - The session to update with parsed data
   */
  private async parseStdout(
    proc: ReturnType<typeof Bun.spawn>,
    session: IActiveSession
  ): Promise<void> {
    if (!proc.stdout || typeof proc.stdout === "number") return;

    const reader = (proc.stdout as ReadableStream<Uint8Array>).getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          this.processLine(line, session);
        }
      }

      // Process remaining buffer
      if (buffer.trim()) {
        this.processLine(buffer, session);
      }
    } catch (error) {
      cliLog.error(
        `Error reading stdout: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Read stderr output for session metadata and error reporting
   *
   * The TransmuxCore CLI writes ALL output to stderr (including the
   * session metadata lines with emoji prefixes). We parse stderr for
   * session metadata in addition to logging it.
   *
   * @param proc - The spawned process
   * @param session - The session context
   */
  private async readStderr(
    proc: ReturnType<typeof Bun.spawn>,
    session: IActiveSession
  ): Promise<void> {
    if (!proc.stderr || typeof proc.stderr === "number") return;

    const reader = (proc.stderr as ReadableStream<Uint8Array>).getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          if (line.trim()) {
            // Parse session metadata from stderr too (CLI writes there)
            this.processLine(line, session);
          }
        }
      }

      if (buffer.trim()) {
        this.processLine(buffer, session);
      }
    } catch (error) {
      cliLog.error(
        `Error reading stderr: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Watch the TransmuxCore log file for session metadata
   *
   * The CLI writes structured session info to /tmp/mks-iptv-transmux.log,
   * NOT to stdout/stderr. This watcher reads new lines appended after
   * the current offset and processes them for session metadata.
   *
   * @param session - The session context to update
   */
  private watchLogFile(session: IActiveSession): void {
    // Get current file size and read existing content BEFORE watching
    stat(LOG_FILE_PATH)
      .then((stats: Stats) => {
        const initialSize = stats.size;
        cliLog.info(`Watching log file from offset ${initialSize}`);

        // Read and process any existing content first
        if (initialSize > 0) {
          this.readAndProcessLogFile(session, 0, initialSize);
        }

        startWatcher(initialSize);
      })
      .catch(() => {
        // File doesn't exist yet, poll until it appears
        cliLog.info("Log file doesn't exist, polling for creation...");
        this.pollForLogFile(session);
      });

    const startWatcher = (startOffset: number) => {
      let lastSize = startOffset;
      let lastSessionId = session.sessionId;

      // Use try-catch in case file is deleted between stat and watch
      let watcher: ReturnType<typeof watch> | null = null;
      try {
        watcher = watch(LOG_FILE_PATH, (eventType) => {
          if (eventType !== "change") return;

          stat(LOG_FILE_PATH)
            .then((stats: Stats) => {
              const newSize = stats.size;
              if (newSize <= lastSize) return;

              // Read only the new bytes
              const fd = Bun.file(LOG_FILE_PATH);
              fd.text()
                .then((content) => {
                  const newContent = content.slice(lastSize);
                  lastSize = newSize;

                  const lines = newContent.split("\n");
                  for (const line of lines) {
                    if (line.trim()) {
                      this.processLogLine(line, session);
                    }
                  }

                  // Update watcher handle if session ID changed
                  if (session.sessionId !== lastSessionId) {
                    const oldHandle = this.logWatchers.get(lastSessionId);
                    if (oldHandle) {
                      this.logWatchers.delete(lastSessionId);
                      this.logWatchers.set(session.sessionId, {
                        close: () => watcher?.close(),
                        lastSize,
                      });
                    }
                    lastSessionId = session.sessionId;
                  }
                })
                .catch((err) => {
                  cliLog.error(`Error reading log file: ${err}`);
                });
            })
            .catch(() => {
              // File might have been deleted
            });
        });
      } catch (err) {
        cliLog.error(`Failed to watch log file: ${err}`);
        return;
      }

      // Store watcher handle for cleanup
      this.logWatchers.set(session.sessionId, {
        close: () => watcher?.close(),
        lastSize: startOffset,
      });
    };
  }

  /**
   * Read and process a range of the log file
   *
   * @param session - Session to update
   * @param start - Start byte offset
   * @param end - End byte offset
   */
  private readAndProcessLogFile(session: IActiveSession, start: number, end: number): void {
    const fd = Bun.file(LOG_FILE_PATH);
    fd.text()
      .then((content) => {
        const range = content.slice(start, end);
        const lines = range.split("\n");
        for (const line of lines) {
          if (line.trim()) {
            this.processLogLine(line, session);
          }
        }
      })
      .catch((err) => {
        cliLog.error(`Error reading initial log content: ${err}`);
      });
  }

  /**
   * Process a log file line for session metadata
   *
   * Separate from processLine() to avoid double-logging lines that come
   * from the log file (which already have timestamps).
   *
   * @param line - Raw log line
   * @param session - Session to update
   */
  private processLogLine(line: string, session: IActiveSession): void {
    const trimmed = line.trim();
    if (!trimmed) return;

    cliLog.debug(`[log-file] ${trimmed}`);

    // Match: Starting progressive transmux session <UUID>
    const sessionMatch = trimmed.match(
      /Starting progressive transmux session\s+([0-9A-Fa-f-]{36})/
    );
    if (sessionMatch) {
      const newId = sessionMatch[1];
      const oldId = session.sessionId;

      session.sessionId = newId;
      this.sessions.delete(oldId);
      this.sessions.set(newId, session);

      const proc = this.processes.get(oldId);
      if (proc) {
        this.processes.delete(oldId);
        this.processes.set(newId, proc);
      }

      // Move watcher handle to new session ID
      const watcherHandle = this.logWatchers.get(oldId);
      if (watcherHandle) {
        this.logWatchers.delete(oldId);
        this.logWatchers.set(newId, watcherHandle);
      }

      // Migrate poll timer to new session ID
      const pollTimer = this.pollTimers.get(oldId);
      if (pollTimer) {
        this.pollTimers.delete(oldId);
        this.pollTimers.set(newId, pollTimer);
      }

      cliLog.info(`Session re-keyed from log: ${oldId} -> ${newId}`);
    }

    // Match: Output dir: <path>
    const outputDirMatch = trimmed.match(/Output dir:\s*(.+)/);
    if (outputDirMatch) {
      session.outputPath = outputDirMatch[1].trim();
      cliLog.info(`Output path: ${session.outputPath}`);
    }

    // Match: Created: fmp4=<path>, playlist=<path>, initSize=<bytes>, duration=<s>s
    const createdMatch = trimmed.match(
      /Created:.*?playlist=([^,]+).*?initSize=(\d+).*?duration=([\d.]+)s/
    );
    if (createdMatch) {
      session.playlistPath = createdMatch[1].trim();
      session.initSegmentSize = parseInt(createdMatch[2], 10);
      session.duration = parseFloat(createdMatch[3]);
      cliLog.info(`Playlist: ${session.playlistPath}, initSize: ${session.initSegmentSize}`);
    }
  }

  /**
   * Process a single stdout/stderr line for session metadata extraction
   *
   * Parses both the log file format and legacy emoji format:
   *
   * Log format (actual CLI output):
   * - `Starting progressive transmux session <UUID>`
   * - `Output dir: <path>`
   * - `Created: fmp4=<path>, playlist=<path>, initSize=<bytes>, duration=<s>s`
   * - `Duration: <s>s, bitrate: ...`
   *
   * @param line - Raw output line
   * @param session - Session to update
   */
  private processLine(line: string, session: IActiveSession): void {
    const trimmed = line.trim();
    if (!trimmed) return;

    cliLog.info(`[stdout:${session.pid}] ${trimmed}`);

    // Match: Starting progressive transmux session <UUID>
    const sessionMatch = trimmed.match(
      /Starting progressive transmux session\s+([0-9A-Fa-f-]{36})/
    );
    if (sessionMatch) {
      const newId = sessionMatch[1];
      const oldId = session.sessionId;

      session.sessionId = newId;
      this.sessions.delete(oldId);
      this.sessions.set(newId, session);

      const proc = this.processes.get(oldId);
      if (proc) {
        this.processes.delete(oldId);
        this.processes.set(newId, proc);
      }

      // Migrate poll timer to new session ID
      const pollTimer = this.pollTimers.get(oldId);
      if (pollTimer) {
        this.pollTimers.delete(oldId);
        this.pollTimers.set(newId, pollTimer);
      }

      cliLog.info(`Session re-keyed: ${oldId} -> ${newId}`);
    }

    // Match: Output dir: <path>
    const outputDirMatch = trimmed.match(/Output dir:\s*(.+)/);
    if (outputDirMatch) {
      session.outputPath = outputDirMatch[1].trim();
      cliLog.info(`Output path: ${session.outputPath}`);
    }

    // Match: Created: fmp4=<path>, playlist=<path>, initSize=<bytes>, duration=<s>s
    const createdMatch = trimmed.match(
      /Created:.*?playlist=([^,]+).*?initSize=(\d+).*?duration=([\d.]+)s/
    );
    if (createdMatch) {
      session.playlistPath = createdMatch[1].trim();
      session.initSegmentSize = parseInt(createdMatch[2], 10);
      session.duration = parseFloat(createdMatch[3]);
      cliLog.info(`Playlist: ${session.playlistPath}, initSize: ${session.initSegmentSize}`);
    }

    // Fallback: legacy emoji format (✅ Transmux started: <id>)
    if (!sessionMatch) {
      const legacyStart = trimmed.match(/Transmux started:\s*(.+)/i);
      if (legacyStart) {
        const newId = legacyStart[1].trim();
        const oldId = session.sessionId;

        session.sessionId = newId;
        this.sessions.delete(oldId);
        this.sessions.set(newId, session);

        const proc = this.processes.get(oldId);
        if (proc) {
          this.processes.delete(oldId);
          this.processes.set(newId, proc);
        }

        // Migrate poll timer to new session ID
        const pollTimer = this.pollTimers.get(oldId);
        if (pollTimer) {
          this.pollTimers.delete(oldId);
          this.pollTimers.set(newId, pollTimer);
        }

        cliLog.info(`Session re-keyed (legacy): ${oldId} -> ${newId}`);
      }
    }
  }

  /**
   * Monitor process exit and update session status accordingly
   *
   * @param proc - The spawned process
   * @param session - The session to update on exit
   */
  private async monitorProcess(
    proc: ReturnType<typeof Bun.spawn>,
    session: IActiveSession
  ): Promise<void> {
    try {
      const exitCode = await proc.exited;

      // Clean up log watcher
      this.cleanupWatcher(session.sessionId);

      if (session.status === "killed") return;

      if (exitCode === 0) {
        this.updateSessionStatus(session.sessionId, "completed");
        cliLog.info(`Session ${session.sessionId} completed (exit 0)`);
      } else {
        this.updateSessionStatus(session.sessionId, "failed");
        cliLog.error(`Session ${session.sessionId} failed (exit ${exitCode})`);
      }
    } catch (error) {
      this.cleanupWatcher(session.sessionId);
      this.updateSessionStatus(session.sessionId, "failed");
      cliLog.error(
        `Session ${session.sessionId} error: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /**
   * Update a session's status
   *
   * @param sessionId - Session to update
   * @param status - New status
   */
  private updateSessionStatus(sessionId: string, status: SessionStatus): void {
    const session = this.sessions.get(sessionId);
    if (session) {
      session.status = status;
    }
  }

  /**
   * Poll for the log file to appear, then start watching it
   *
   * Used when the CLI hasn't created the log file yet at spawn time.
   * Polls every 500ms up to 30 times (15s) then gives up.
   *
   * @param session - Session to attach watcher to
   */
  private pollForLogFile(session: IActiveSession): void {
    let attempts = 0;
    const maxAttempts = 30;

    const timer = setInterval(() => {
      attempts++;
      stat(LOG_FILE_PATH)
        .then(() => {
          clearInterval(timer);
          this.pollTimers.delete(session.sessionId);
          cliLog.info("Log file appeared, starting watcher");
          this.watchLogFile(session);
        })
        .catch(() => {
          if (attempts >= maxAttempts) {
            clearInterval(timer);
            this.pollTimers.delete(session.sessionId);
            cliLog.warn("Log file never appeared after polling");
          }
        });
    }, 500);

    this.pollTimers.set(session.sessionId, timer);
  }

  /**
   * Close and remove the log file watcher for a session
   *
   * @param sessionId - Session to clean up
   */
  private cleanupWatcher(sessionId: string): void {
    const handle = this.logWatchers.get(sessionId);
    if (handle) {
      handle.close();
      this.logWatchers.delete(sessionId);
      cliLog.debug(`Closed log watcher for session ${sessionId}`);
    }

    // Also clear any active poll timer for this session
    const pollTimer = this.pollTimers.get(sessionId);
    if (pollTimer) {
      clearInterval(pollTimer);
      this.pollTimers.delete(sessionId);
      cliLog.debug(`Cleared poll timer for session ${sessionId}`);
    }
  }
}
